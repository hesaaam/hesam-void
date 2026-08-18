#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shellapi.h>
#include <windows.h>

#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

bool IsProcessElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }

  TOKEN_ELEVATION elevation{};
  DWORD bytes_returned = 0;
  const bool available = GetTokenInformation(
      token, TokenElevation, &elevation, sizeof(elevation), &bytes_returned);
  CloseHandle(token);
  return available && elevation.TokenIsElevated != 0;
}

bool RelaunchElevated() {
  wchar_t executable_path[MAX_PATH]{};
  if (GetModuleFileNameW(nullptr, executable_path, MAX_PATH) == 0) {
    return false;
  }

  const auto result = reinterpret_cast<INT_PTR>(
      ShellExecuteW(nullptr, L"runas", executable_path, nullptr, nullptr,
                    SW_SHOWNORMAL));
  return result > 32;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Xray's Windows TUN inbound creates a virtual adapter and system routes.
  // Relaunch once through UAC so the managed Core process inherits the required
  // elevated token. This avoids requiring a manifest that conflicts with the
  // Flutter runner's embedded resource pipeline.
  if (!IsProcessElevated()) {
    if (RelaunchElevated()) {
      return EXIT_SUCCESS;
    }
    MessageBoxW(nullptr,
                L"Hesam Void 4SUPER needs Administrator permission to create "
                L"the Windows TUN adapter. Approve the UAC prompt and try again.",
                L"Administrator permission required", MB_OK | MB_ICONWARNING);
    return EXIT_FAILURE;
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

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1440, 900);
  if (!window.Create(L"Hesam Void 4SUPER for Windows", origin, size)) {
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
