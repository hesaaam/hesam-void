# flutter_v2ray (bundled)

A copy of [flutter_v2ray](https://github.com/blueboy-tm/flutter_v2ray) 2.0.0
(MIT License, see `LICENSE`) kept in this repository so the Android VPN
service can be adjusted for Hesam Void. Only the Android plugin and its Dart
API are included.

## Changes from upstream 2.0.0

| File | Change |
|---|---|
| `android/.../services/V2rayVPNService.java` | The tunnel interface uses the private range `172.19.0.0/30` instead of `26.26.26.0/30`. Browsers hide private interface addresses from WebRTC, so pages can no longer read the tunnel address or recognise it as a V2Ray-style VPN. |

## Upgrading

1. Copy `android/`, `lib/`, `LICENSE` and `pubspec.yaml` from the new release
   (leave out `example/`, `test/`, `doc/`, `tool/` and the Gradle wrapper).
2. Re-apply every change listed above.
3. Review the Xray core pin in `android/build.gradle.kts` of the app.
