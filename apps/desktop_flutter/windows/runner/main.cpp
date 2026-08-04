#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>

#include <algorithm>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

Win32Window::Point CenterInPrimaryWorkArea(const Win32Window::Size& size) {
  RECT work_area{};
  SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);

  // Win32Window::Create applies DPI scaling to logical coordinates, so convert
  // the physical work area back to logical pixels before calculating origin.
  const UINT dpi = GetDpiForSystem();
  const double scale_factor = dpi / 96.0;
  const int work_width =
      static_cast<int>((work_area.right - work_area.left) / scale_factor);
  const int work_height =
      static_cast<int>((work_area.bottom - work_area.top) / scale_factor);
  const int work_left = static_cast<int>(work_area.left / scale_factor);
  const int work_top = static_cast<int>(work_area.top / scale_factor);
  const int x =
      work_left + std::max(0, (work_width - static_cast<int>(size.width)) / 2);
  const int y =
      work_top + std::max(0, (work_height - static_cast<int>(size.height)) / 2);
  return Win32Window::Point(static_cast<unsigned int>(x),
                            static_cast<unsigned int>(y));
}

bool PathContainsNonAscii(const std::wstring& path) {
  for (const wchar_t ch : path) {
    if (static_cast<unsigned int>(ch) > 127) {
      return true;
    }
  }
  return false;
}

std::wstring ParentDirectory(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  if (slash == std::wstring::npos) {
    return L"";
  }
  return path.substr(0, slash);
}

bool LaunchProcess(const std::wstring& exe_path, const std::wstring& work_dir) {
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  std::wstring command_line = L"\"" + exe_path + L"\"";
  std::vector<wchar_t> mutable_cmd(command_line.begin(), command_line.end());
  mutable_cmd.push_back(L'\0');

  const BOOL created = ::CreateProcessW(
      exe_path.c_str(), mutable_cmd.data(), nullptr, nullptr, FALSE, 0, nullptr,
      work_dir.empty() ? nullptr : work_dir.c_str(), &si, &pi);
  if (!created) {
    return false;
  }
  ::CloseHandle(pi.hThread);
  ::CloseHandle(pi.hProcess);
  return true;
}

// Prefer Windows 8.3 short path when the volume still generates them.
bool TryRelaunchViaShortPath(const std::wstring& module_path) {
  wchar_t short_path[MAX_PATH] = {};
  const DWORD short_len =
      ::GetShortPathNameW(module_path.c_str(), short_path, MAX_PATH);
  if (short_len == 0 || short_len >= MAX_PATH) {
    return false;
  }
  const std::wstring relaunch_path(short_path);
  if (PathContainsNonAscii(relaunch_path)) {
    return false;
  }
  if (_wcsicmp(module_path.c_str(), relaunch_path.c_str()) == 0) {
    return false;
  }

  const std::wstring work_dir = ParentDirectory(relaunch_path);
  return LaunchProcess(relaunch_path, work_dir);
}

// Fallback for machines with 8.3 disabled: junction under an ASCII Public path.
bool TryRelaunchViaPublicJunction(const std::wstring& module_path) {
  const std::wstring install_dir = ParentDirectory(module_path);
  if (install_dir.empty()) {
    return false;
  }

  const std::wstring bridge_root = L"C:\\Users\\Public\\CDriveManager";
  const std::wstring bridge_link = bridge_root + L"\\run";
  const std::wstring bridge_exe = bridge_link + L"\\c_drive_manager.exe";

  ::CreateDirectoryW(bridge_root.c_str(), nullptr);
  ::RemoveDirectoryW(bridge_link.c_str());

  std::wstring command = L"cmd.exe /c mklink /J \"" + bridge_link + L"\" \"" +
                         install_dir + L"\"";
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION pi{};
  std::vector<wchar_t> mutable_cmd(command.begin(), command.end());
  mutable_cmd.push_back(L'\0');
  if (!::CreateProcessW(nullptr, mutable_cmd.data(), nullptr, nullptr, FALSE,
                        CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
    return false;
  }
  ::WaitForSingleObject(pi.hProcess, 15000);
  DWORD exit_code = 1;
  ::GetExitCodeProcess(pi.hProcess, &exit_code);
  ::CloseHandle(pi.hThread);
  ::CloseHandle(pi.hProcess);
  if (exit_code != 0) {
    return false;
  }
  if (::GetFileAttributesW(bridge_exe.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return false;
  }
  return LaunchProcess(bridge_exe, bridge_link);
}

// Flutter 3.38 engines crash on non-ASCII install paths. Newer engines fixed
// it, but keep this relaunch bridge so Chinese install dirs stay usable.
bool RelaunchViaAsciiPathIfNeeded() {
  wchar_t already = 0;
  if (::GetEnvironmentVariableW(L"CDM_ASCII_RELAUNCH", &already, 1) > 0) {
    return false;
  }

  wchar_t module_path_buf[MAX_PATH] = {};
  const DWORD module_len =
      ::GetModuleFileNameW(nullptr, module_path_buf, MAX_PATH);
  if (module_len == 0 || module_len >= MAX_PATH) {
    return false;
  }
  const std::wstring module_path(module_path_buf);
  if (!PathContainsNonAscii(module_path)) {
    return false;
  }

  ::SetEnvironmentVariableW(L"CDM_ASCII_RELAUNCH", L"1");

  if (TryRelaunchViaShortPath(module_path) ||
      TryRelaunchViaPublicJunction(module_path)) {
    return true;
  }

  ::SetEnvironmentVariableW(L"CDM_ASCII_RELAUNCH", nullptr);
  // Message text uses Unicode escapes to stay encoding-safe under MSVC / CP936.
  ::MessageBoxW(
      nullptr,
      L"\u5f53\u524d\u5b89\u88c5\u76ee\u5f55\u5305\u542b\u4e2d\u6587\u6216\u7279"
      L"\u6b8a\u5b57\u7b26\uff0c\u4e14\u65e0\u6cd5\u81ea\u52a8\u521b\u5efa\u517c"
      L"\u5bb9\u8def\u5f84\u3002\n\u8bf7\u6539\u5b89\u88c5\u5230\u82f1\u6587\u76ee"
      L"\u5f55\uff08\u4f8b\u5982 C:\\Program Files\\CDriveManager\uff09\u3002",
      L"C \u76d8\u7ba1\u5bb6", MB_OK | MB_ICONERROR);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  if (RelaunchViaAsciiPathIfNeeded()) {
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  SetCurrentProcessExplicitAppUserModelID(L"CDriveManager.Local");

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Size size(1280, 860);
  Win32Window::Point origin = CenterInPrimaryWorkArea(size);
  if (!window.Create(L"C \u76D8\u7BA1\u5BB6", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
