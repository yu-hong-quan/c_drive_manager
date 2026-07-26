#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>

#include <algorithm>

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

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
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
