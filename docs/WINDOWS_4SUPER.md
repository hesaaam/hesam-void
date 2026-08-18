# Hesam Void 4SUPER for Windows

## Scope

The Windows build is a **TUN-first desktop preview**. It shares the local profile model and configuration parser with Android but does not use the Android VPN plugin. A selected profile is converted to local Xray JSON at runtime, then a single bundled Xray process owns the Windows TUN adapter, its system routes and the outbound interface selection.

> A working process is not treated as proof that a remote server is reachable. A profile must be validated on the user’s Windows network before it is described as working.

## Runtime model

The desktop process remains idle while disconnected. When the user connects, the app copies the bundled `xray.exe` and `wintun.dll` to the user support directory only if the packaged version changed. It writes `active-xray.json` locally, validates it with `xray run -test`, then starts one Xray process. On disconnect, the process is terminated and no retry loop remains.

The generated TUN inbound uses `autoSystemRoutingTable` for IPv4 and IPv6 default routes and `autoOutboundsInterface: auto` to prevent Xray upstream traffic looping into its own adapter. This follows the official Xray TUN configuration model.[1]

## Build a Windows package

Run these commands in **PowerShell on Windows** with Flutter 3.35.4, Visual Studio C++ Desktop tooling and Inno Setup 6 installed.

```powershell
flutter pub get
.\tools\windows\fetch_runtime.ps1
flutter analyze --no-fatal-infos
flutter test
flutter build windows --release
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\windows\hesam_void_4super.iss
```

The installer is created under `dist\windows\`. It requests Administrator rights because Windows may require elevation to create or configure the virtual adapter.

## CI and release policy

The Windows GitHub Actions workflow downloads Xray `v26.3.27` and Wintun `0.14.1` during the runner build; generated `.exe` and `.dll` files are excluded from Git. On a pushed version tag, the workflow builds the Flutter Windows Release folder, creates the Inno Setup installer, computes SHA-256 and attaches both installer and checksum to the GitHub Release.

The Preview is intentionally **not Authenticode-signed**. A future production release must add a code-signing certificate via protected GitHub secrets and sign both the installer and all executable runtime files.

## References

[1]: https://xtls.github.io/en/config/inbounds/tun.html "Xray TUN inbound configuration"
