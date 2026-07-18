#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutexName[] =
    L"AgentBatteryFlutterSingleInstance";
constexpr wchar_t kMainWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

void RestoreExistingWindow() {
  HWND existing_window = FindWindowW(kMainWindowClassName, nullptr);

  if (!existing_window) {
    return;
  }

  if (IsIconic(existing_window)) {
    ShowWindow(existing_window, SW_RESTORE);
  }
  ShowWindow(existing_window, SW_SHOW);
  SetForegroundWindow(existing_window);

  FLASHWINFO flash_info{};
  flash_info.cbSize = sizeof(flash_info);
  flash_info.hwnd = existing_window;
  flash_info.dwFlags = FLASHW_TRAY;
  flash_info.uCount = 1;
  flash_info.dwTimeout = 0;
  FlashWindowEx(&flash_info);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance_mutex =
      CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  const DWORD mutex_error = GetLastError();
  if (!single_instance_mutex) {
    return EXIT_FAILURE;
  }
  if (mutex_error == ERROR_ALREADY_EXISTS) {
    RestoreExistingWindow();
    CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"agent_battery_flutter", origin, size)) {
    CloseHandle(single_instance_mutex);
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  CloseHandle(single_instance_mutex);
  return EXIT_SUCCESS;
}
