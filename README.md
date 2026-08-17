# Hesam Void 4.1SUPER

> **A local-first Android connection navigator for user-owned VPN and SSH configurations.**

Hesam Void is an Android client for people who manage their own proxy and SSH profiles. It imports supported configuration links, establishes a device VPN tunnel through Xray or SSH/SOCKS, and helps the user make a transparent, on-device decision about which profile is most reliable right now.

**4SUPER** turns Hesam Void into an Alive Signal workspace: a local-first experience for choosing a route, understanding its health, connecting with intention and reviewing what happened afterwards. The app does not sell VPN servers, require an account, upload raw configuration URLs, or make guaranteed availability claims.

## Download 4.1SUPER APK

<p align="center">
  <a href="https://github.com/hesaaam/hesam-void/releases/download/v4.1.0/hesam-void-4-1-super-universal.apk">
    <img src="assets/images/hesam-void-4-1-super-download-qr.png" width="280" alt="Scan to download Hesam Void 4.1SUPER Universal APK directly">
  </a>
</p>

<p align="center"><strong>Scan the QR Code to download the 4.1SUPER Universal APK directly.</strong></p>

The QR Code contains the direct APK asset URL, not the Release page. On most Android phones, scanning opens the browser download flow immediately. You can also use the direct link: [Download Hesam Void 4.1SUPER Universal APK](https://github.com/hesaaam/hesam-void/releases/download/v4.1.0/hesam-void-4-1-super-universal.apk).

> Android may ask you to allow installation from your browser or file manager. If an older build was signed with a different key, uninstall it before installing this test release.

## What makes 4SUPER different

| Capability | What the user gets | What stays local |
|---|---|---|
| **Alive Signal Canvas** | The home screen now shows actual engine states for ready, connecting, protected, disconnecting and attention; it is not a timer-driven mock animation. | Current status and local traffic statistics. |
| **Quick Connect** | A route sheet with the selected profile, `Best now` recommendation, local health reasons and direct connect action. | Profile ranking, latency and health events. |
| **Connection Story** | A readable timeline for local checks, successful connects, errors and unexpected drops, including the current redacted error when present. | Event time, latency, success/failure and sanitized reason. |
| **Server Studio** | Rich profile cards with health score, latest local latency, success rate, per-profile actions and persistent Favorites. | Favorite profile identifiers and health evidence. |
| **Experience Controls** | Motion can be Standard, Reduced or Off; Server Studio can use a compact density. These preferences never change routing behavior. | UI preferences only. |
| **Connection Navigator** | A 0–100 profile health score, a `Best now` recommendation, and a readable explanation based on success, latency, recency and unexpected drops. | Connection events, latency results and profile ranking. |
| **Reliable recovery** | Auto-reconnect distinguishes a manual disconnect from an unexpected failure. A user-selected server queue can fail over after the configured retry budget. | Retry policy and profile order. |
| **Real profile import and routing** | Clipboard import, manual entry, QR scanning and Android app-routing policies are connected to the actual import and VPN paths. | Imported content, installed-app list and route policy. |
| **Encrypted profile store** | Profile and app-setting boxes use AES-256 encryption with an on-device key through the platform secure-storage provider. | Configuration URLs, SSH credentials and app settings. |

## Supported configuration formats

| Family | Import | Tunnel mode | Notes |
|---|---:|---:|---|
| VLESS, including TCP + Reality + Vision and current ML-KEM/0-RTT encryption links | Yes | Xray VPN | Uses a vendored AndroidLibXrayLite 26.7.31 adapter; current Reality settings are retained in the generated Core JSON. |
| VMess | Yes | Xray VPN | Standard encoded VMess links are supported. |
| Trojan | Yes | Xray VPN | Standard Trojan links are supported. |
| Shadowsocks | Yes | Xray VPN | SIP002 and legacy credential encodings are parsed. |
| NPVT SSH / SSH | Yes | SSH → loopback SOCKS5 → Xray VPN | Direct SSH, SSH over TLS and SSH over WebSocket are supported. |
| SSH over SlowDNS | Import preserved | Not connected in v4 | The app reports this transport as unsupported rather than silently falling back to direct SSH. |

## Connection Navigator

The Navigator is intentionally **rule-based and explainable**. It is not a black-box model and it does not claim to detect a user’s network environment. For each profile, the score considers successful local checks, recently measured latency, score freshness and unexpected tunnel drops. When no local evidence exists, the app shows `Needs a first check` instead of pretending that a profile is healthy.

Use `Best now` to select the strongest locally observed profile. Selection does not start a tunnel automatically; the user remains in control of the final connect action.

## Privacy and safety model

Hesam Void is designed as a local-first client. It does not need a user account or a remote control plane. The project’s profile storage is encrypted with a locally generated AES-256 key, and the wrapping key is stored through the operating system’s secure-storage implementation. The Connection Navigator masks configuration URLs and password-like fragments before retaining an error explanation.

The app cannot guarantee that a third-party server is available, safe, private or suitable for a particular network. Users should import configurations only from sources they trust and must comply with applicable laws and service terms.

## Use the app

1. Open **SERVERS** and use the add action to import from clipboard, scan a QR code, or enter a supported URL manually.
2. Select a profile and run a ping check when you want initial local evidence.
3. Open **CONNECT**. The Connection Navigator displays the selected profile’s known health or recommends a better locally observed profile.
4. Press the connect control and approve Android’s VPN permission when asked.
5. Configure Auto-reconnect and Split Tunneling in settings only when you need them. A manual disconnect is never automatically retried. If a VLESS Reality route cannot start, 4.1SUPER now exits Connecting after 25 seconds with a local error instead of waiting indefinitely.

## Build from source

The repository is configured for Flutter **3.35.4** and Dart **3.9.2**.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The resulting APK is written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Development standards for 4.1SUPER

Every new user-facing network feature should satisfy three requirements before it is shown as stable: it must be wired into the actual connection pipeline, validated through tests, and documented without overclaiming. Features that require a platform-specific implementation should fail clearly on unsupported platforms instead of simulating a result.

The repository’s `test/` directory contains regression tests for the configuration parser, NPVT SSH round-trip behavior and the app splash lifecycle. Run the checks above before opening a pull request.

## License

This project is distributed under the [MIT License](LICENSE).
