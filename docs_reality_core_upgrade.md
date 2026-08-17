# Reality / VLESS Encryption upgrade notes

## Why 4.1SUPER upgrades the Android Xray core

The 4.0.x Android bundle used `flutter_v2ray` 1.0.9 with an older Xray core. This was insufficient for newer VLESS Encryption share links that use an ML-KEM hybrid handshake string such as `mlkem768x25519plus.native.0rtt...`.

The maintained Xray documentation states that VLESS `encryption` cannot be left empty, and documents `mlkem768x25519plus` as the current handshake method, including `native` and `0rtt` blocks. It also documents `xtls-rprx-vision` as supported with TCP + TLS/REALITY. The Reality outbound object documents `serverName`, `fingerprint`, `password` (with `publicKey` retained as the old name), `shortId`, and `spiderX`.

4.1SUPER vendors a reviewed Android Core binding using the maintained `2dust/AndroidLibXrayLite` release `v26.7.31`, instead of retaining the historical `V2RayPoint` binding. The project keeps the existing Flutter service interface through a local adapter.

## Sources

1. Xray VLESS outbound documentation: https://xtls.github.io/en/config/outbounds/vless.html
2. Xray REALITY transport documentation: https://xtls.github.io/en/config/transports/reality.html
3. Xray command documentation for `mlkem768` and `vlessenc`: https://xtls.github.io/en/document/command.html
4. AndroidLibXrayLite release: https://github.com/2dust/AndroidLibXrayLite/releases/tag/v26.7.31
5. v2rayNG reference implementation: https://github.com/2dust/v2rayNG
