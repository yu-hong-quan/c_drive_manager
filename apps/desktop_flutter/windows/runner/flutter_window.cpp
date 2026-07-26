#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <windows.h>

#include "resource.h"

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayOpenCommand = 40001;
constexpr UINT kTrayExitCommand = 40002;
const UINT kTaskbarCreatedMessage = RegisterWindowMessage(L"TaskbarCreated");

HICON LoadTrayIcon() {
  return reinterpret_cast<HICON>(LoadImage(
      GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR | LR_SHARED));
}

void RestoreAppWindow(HWND hwnd) {
  ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOWNORMAL);
  SetForegroundWindow(hwnd);
}

void AddTrayIcon(HWND hwnd) {
  NOTIFYICONDATA nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = kTrayIconId;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid.uCallbackMessage = kTrayMessage;
  nid.hIcon = LoadTrayIcon();
  wcscpy_s(nid.szTip, L"C \u76D8\u7BA1\u5BB6");
  if (!Shell_NotifyIcon(NIM_ADD, &nid)) {
    Shell_NotifyIcon(NIM_MODIFY, &nid);
  }
  nid.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIcon(NIM_SETVERSION, &nid);
}

void RemoveTrayIcon(HWND hwnd) {
  NOTIFYICONDATA nid{};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = kTrayIconId;
  Shell_NotifyIcon(NIM_DELETE, &nid);
}

void ShowTrayMenu(HWND hwnd) {
  HMENU menu = CreatePopupMenu();
  AppendMenu(menu, MF_STRING, kTrayOpenCommand, L"\u6253\u5F00 C \u76D8\u7BA1\u5BB6");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kTrayExitCommand, L"\u9000\u51FA");

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(hwnd);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor.x, cursor.y,
      0, hwnd, nullptr);
  DestroyMenu(menu);

  if (command == kTrayOpenCommand) {
    RestoreAppWindow(hwnd);
  } else if (command == kTrayExitCommand) {
    RemoveTrayIcon(hwnd);
    DestroyWindow(hwnd);
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "c_drive_manager/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HWND hwnd = GetHandle();
        if (call.method_name() == "startDrag") {
          // Let Windows perform the move loop so dragging remains native-smooth
          // while Flutter keeps ownership of taps and navigation.
          ReleaseCapture();
          SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
          return;
        }
        if (call.method_name() == "minimize") {
          ShowWindow(hwnd, SW_MINIMIZE);
          result->Success();
          return;
        }
        if (call.method_name() == "toggleMaximize") {
          ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success();
          return;
        }
        if (call.method_name() == "close") {
          RemoveTrayIcon(hwnd);
          DestroyWindow(hwnd);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  AddTrayIcon(GetHandle());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon(GetHandle());
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kTaskbarCreatedMessage) {
    AddTrayIcon(hwnd);
    return 0;
  }

  switch (message) {
    case kTrayMessage:
      if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
        RestoreAppWindow(hwnd);
      } else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
        ShowTrayMenu(hwnd);
      }
      return 0;

    case WM_CLOSE:
      // Closing the app is a real exit; remove the notification icon before
      // destroying the HWND so Windows does not leave a stale tray entry.
      RemoveTrayIcon(hwnd);
      DestroyWindow(hwnd);
      return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
