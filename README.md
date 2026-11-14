# Hesam Void 4SUPER

> **A local-first Android connection navigator for user-owned VPN and SSH configurations.**

Hesam Void is an Android client for people who manage their own proxy and SSH profiles. It imports supported configuration links, establishes a device VPN tunnel through Xray or SSH/SOCKS, and helps the user make a transparent, on-device decision about which profile is most reliable right now.

**4SUPER** turns Hesam Void into an Alive Signal workspace: a local-first experience for choosing a route, understanding its health, connecting with intention and reviewing what happened afterwards. The app does not sell VPN servers, require an account, upload raw configuration URLs, or make guaranteed availability claims.

## Download 4SUPER APK

<p align="center">
  <a href="https://github.com/hesaaam/hesam-void/releases/latest/download/hesam-void-4super-universal.apk">
    <img src="assets/images/hesam-void-4super-download-qr.png" width="280" alt="Scan to download Hesam Void 4SUPER Universal APK directly">
  </a>
</p>

<p align="center"><strong>Scan the QR Code to download the 4SUPER Universal APK directly.</strong></p>

The QR Code always points to the APK of the latest Release, so it stays valid for future versions. On most Android phones, scanning opens the browser download flow immediately. You can also use the direct link: [Download Hesam Void 4SUPER Universal APK](https://github.com/hesaaam/hesam-void/releases/latest/download/hesam-void-4super-universal.apk).

> Android may ask you to allow installation from your browser or file manager. If an older build was signed with a different key, uninstall it before installing this test release.

## New in 4.3 — Night Signal

| Capability | What the user gets |
|---|---|
| **Live route** | Particles flow between your phone and the server at the speed of your real traffic. |
| **Smart Connect radar** | Watch every route being tested on a radar; the best one is pulled to the centre. |
| **Insights** | Protected time, data, apps used while protected, a five-week calendar and your usual hours — kept only on this phone. |
| **New navigation** | Connect, Routes, Insights and Settings in a bottom bar; folders open in place. |

## New in 4.2 — Subscriptions

| Capability | What the user gets |
|---|---|
| **Subscription folders** | A subscription link becomes one folder on the Servers tab with its routes inside, so the list stays tidy. |
| **Usage at a glance** | Data used, allowance and days left when the provider shares them, plus best latency per folder. |
| **One-tap updates** | Update keeps unchanged routes and their history, adds new ones and removes retired ones; folders refresh automatically when due. |
| **Xray JSON** | Complete JSON profiles from subscriptions or the clipboard connect like any other route. |

## New in 4.1 — Smart Connect

| Capability | What the user gets |
|---|---|
| **Smart Connect** | One tap checks every saved route, measures real traffic on the most promising ones, connects to the best and automatically tries the next route if one fails. |
| **Verified internet** | After connecting, a test request travels through the tunnel; the app shows `Internet verified • N ms` or a clear warning with a one-tap alternative. |
| **Readable errors** | Failures are explained in plain language with a suggested next step instead of raw engine messages. |
| **Calmer, lighter app** | No vibration every second while connected, lower background CPU use, faster start and the last selected route remembered. |

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
| VLESS, including Reality | Yes | Xray VPN | Uses the `flutter_v2ray` engine integration. |
| VMess | Yes | Xray VPN | Standard encoded VMess links are supported. |
| Trojan | Yes | Xray VPN | Standard Trojan links are supported. |
| Shadowsocks | Yes | Xray VPN | SIP002 and legacy credential encodings are parsed. |
| NPVT SSH / SSH | Yes | SSH → loopback SOCKS5 → Xray VPN | Direct SSH, SSH over TLS and SSH over WebSocket are supported. |
| Xray JSON (single or list) | Yes | Xray VPN | Complete configs from subscriptions or paste; a SOCKS inbound is added and the server outbound placed first when needed. |
| Subscription links (base64, plain or JSON) | Yes | Per route | Shown as folders with usage, expiry and automatic updates. Clash and sing-box formats are reported as unsupported. |
| SSH over SlowDNS | Import preserved | Not connected in v4 | The app reports this transport as unsupported rather than silently falling back to direct SSH. |

## Connection Navigator

The Navigator is intentionally **rule-based and explainable**. It is not a black-box model and it does not claim to detect a user’s network environment. For each profile, the score considers successful local checks, recently measured latency, score freshness and unexpected tunnel drops. When no local evidence exists, the app shows `Needs a first check` instead of pretending that a profile is healthy.

Use `Best now` to select the strongest locally observed profile. Selection does not start a tunnel automatically; the user remains in control of the final connect action.

## Privacy and safety model

Hesam Void is designed as a local-first client. It does not need a user account or a remote control plane. The project’s profile storage is encrypted with a locally generated AES-256 key, and the wrapping key is stored through the operating system’s secure-storage implementation. The Connection Navigator masks configuration URLs and password-like fragments before retaining an error explanation.

The app cannot guarantee that a third-party server is available, safe, private or suitable for a particular network. Users should import configurations only from sources they trust and must comply with applicable laws and service terms.

## Use the app

1. Open **SERVERS** and use the add action to import from clipboard, scan a QR code, or enter a supported URL manually. Several links pasted at once are imported together.
2. Press **Smart Connect** to let the app test your routes and connect to the best one, or select a profile and run a health check yourself.
3. Open **CONNECT**. The Connection Navigator displays the selected profile’s known health or recommends a better locally observed profile.
4. Press the connect control and approve Android’s VPN permission when asked.
5. Configure Auto-reconnect and Split Tunneling in settings only when you need them. A manual disconnect is never automatically retried.

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

## Development standards for 4SUPER

Every new user-facing network feature should satisfy three requirements before it is shown as stable: it must be wired into the actual connection pipeline, validated through tests, and documented without overclaiming. Features that require a platform-specific implementation should fail clearly on unsupported platforms instead of simulating a result.

The repository’s `test/` directory contains regression tests for the configuration parser, NPVT SSH round-trip behavior, Smart Connect route ranking, error explanations, the connection canvas and the app splash lifecycle. Run the checks above before opening a pull request.

## Releasing a new version

Releases are published automatically; nothing is uploaded by hand.

1. Start the version on a feature branch:
   ```bash
   python3 scripts/bump_version.py 4.2.0 "4SUPER Subscriptions"
   ```
   This raises `version` in `pubspec.yaml` (including the Android build number) and opens a dated `CHANGELOG.md` section. Fill in its tables; empty sections are left out of the release notes.
2. Open a pull request to `main`. **Flutter Quality** checks formatting, analysis, tests and the release build, and attaches the APKs to the run for testing on a device.
3. Merge. After **Flutter Quality** passes on `main`, **Publish Release** creates the `vX.Y.Z` tag and the GitHub Release from the same tested APKs, with the `CHANGELOG.md` section as notes and `SHA256SUMS.txt` attached.

A version that already has a release is skipped, so merges that do not change `version` publish nothing. The README download link and QR code always point to the latest release.

## License

This project is distributed under the [MIT License](LICENSE).
