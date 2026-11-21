# Changelog

All notable changes to Hesam Void are documented in this file.

## [4.4.0] - 2026-11-21 — Xray 26 engine

### Changed

| Area | Change |
|---|---|
| VPN engine | Upgraded the bundled Xray core from 1.8.17 (2024) to **26.7.28** through `flutter_v2ray` 2.0.0, with its reworked Android VPN service lifecycle. |
| Engine version pin | The core is pinned to Xray 26.7.28, the newest release that still accepts VLESS and Trojan without TLS to public servers. Xray 26.9.9 and newer refuse them, which would break common plain-WebSocket panel profiles. |
| Xray JSON | Profiles written for current Xray versions run as they are; the translations needed by the old core are removed. |
| Settings | Settings › General shows the Xray version reported by the engine itself instead of a fixed text. |

### Added

| Area | Change |
|---|---|
| Transports | XHTTP and VLESS Vision profiles now connect, from links, subscriptions and JSON. |

### Fixed

| Area | Fix |
|---|---|
| Core version | The Xray Core entry no longer claims 25.3.6 while 1.8.17 was running. |

### Notes

- Links that use `allowInsecure` no longer turn off TLS certificate checks; such servers need a valid certificate.
- Validated on desktop Xray 26.7.28: VLESS (Reality Vision, WebSocket TLS, gRPC, XHTTP, plain WebSocket), VMess, Trojan, Shadowsocks, SSH and panel JSON profiles start cleanly.

## [4.3.0] - 2026-11-14 — Night Signal

### Added

| Area | Change |
|---|---|
| Night Signal look | A new default look: deep night background, one signal colour for live state and monospace numbers. Themes chosen in Settings still change the accent colour. |
| Navigation | A floating bottom bar with Connect, Routes, Insights and Settings replaces the two top tabs. |
| Live route | The Connect screen draws the route between your phone and the server. While protected, light particles travel along it — downloads towards the phone, uploads towards the server — and their speed follows the real traffic. Connecting shows a moving dashed route. |
| Smart Connect radar | Smart Connect opens a radar where every route is a blip: distance from the centre is its latency, unreachable routes sit on the edge in red, measured ones light up, and the winner is pulled into the centre. Steps and a Real Delay ranking are shown underneath. |
| Routes | Subscription folders show a data-usage ring and days left and open in place. Each route is a compact line with a four-bar signal indicator; long-press or the menu opens its actions. |
| Insights | Protected time, data, sessions and drops for Day, Week or Month; the apps used while protected (with Usage access); a five-week calendar; the hours you usually connect; and data per day. Everything stays on the phone and can be cleared. |

### Changed

| Area | Change |
|---|---|
| Connect screen | One clear power button, the selected route with a Smart shortcut, and Session, Data and Internet status at a glance. Tapping during connecting cancels. |
| Motion | The matrix background is gone. All new animations follow the Motion setting in Settings. |

### Removed

- The previous canvas, health card, server card, speed graph and matrix background widgets.

## [4.2.0] - 2026-11-14 — 4SUPER Subscriptions

### Added

| Area | Change |
|---|---|
| Subscriptions | Add a subscription link and its routes are kept together in a folder on the Servers tab instead of filling the list. Folders show route count, best latency, data used, allowance and days left when the provider shares them. |
| Folder view | Opening a folder shows its routes with Update, Check routes and Smart Connect limited to that folder, plus rename, automatic update interval, copy link and delete. Pull down to update. |
| Updates | Updating keeps unchanged routes with their latency and health history, adds new ones and removes routes the provider no longer lists. Folders update automatically on app start when their interval is due (12 hours by default, or the provider's suggestion). An empty or failed response never wipes a folder. |
| Xray JSON | Complete Xray JSON profiles (one object or a list) can be imported from subscriptions or pasted. They connect, run Real Delay and take part in Smart Connect like link profiles. |
| Import | Pasting base64 subscription content or JSON now works; a copied subscription link opens the subscription sheet directly. Scanning a QR code that holds a subscription link adds the folder. |

### Changed

| Area | Change |
|---|---|
| Unsupported content | Clash and sing-box profiles and links using protocols the engine cannot run (for example `hysteria2://`) are reported clearly instead of being silently ignored. |
| QR codes | Profiles too large for a QR code show a message pointing to Copy instead of failing. |
| Release pipeline | GitHub Actions now use the Node 24 versions of checkout and Java setup. |

### Fixed

| Area | Fix |
|---|---|
| Xray JSON DNS | JSON profiles with DNS-over-HTTPS or object DNS entries (common in panel subscriptions) no longer fail to start the tunnel. Their resolvers are reduced to IP addresses for Android, and DNS queries are routed through the server so answers are not tampered with. |
| Xray JSON compatibility | Settings written for newer Xray versions that the bundled engine rejects at start-up are translated where an equivalent exists (for example `nonIPQuery: reject`). Profiles using the XHTTP transport are reported as unsupported instead of hanging. |
| Stuck connecting | When the engine rejects a profile it reports nothing, which left the app on "Securing your route". The app now stops after 20 seconds with a clear explanation, and Smart Connect moves on to the next route. |

## [4.1.0] - 2026-11-14 — 4SUPER Smart Connect

### Added

| Area | Change |
|---|---|
| Smart Connect | One tap checks every saved route in parallel, measures real traffic (Real Delay) on the most promising ones, connects to the best and automatically falls back to the next route when one fails. Progress and a cancel action are shown on the Alive Signal canvas. |
| Internet check | After every connection the app sends a test request through the tunnel and shows `Internet verified • N ms` or a clear warning with a one-tap way to try another route. Results feed local route health. |
| Readable errors | Engine, socket and SSH errors are explained in plain language with a suggested next step (find a working route, open details, or dismiss). |
| Remembered route | The selected route is restored when the app opens again. |

### Changed

| Area | Change |
|---|---|
| Health checks | Results appear on each card as soon as that route finishes, with `CHECKING n/total` progress and a summary of how many routes answered. History and profiles are saved once per run instead of once per route. |
| Startup | Local services open in parallel behind a shorter splash; a storage failure now shows a retry screen instead of a blank app. |
| Battery and smoothness | Live traffic counters refresh only the widgets that show them. The background effect reuses pre-rendered glyphs, runs at 30 fps and stops completely when Motion is Reduced or Off. |
| Alive Signal canvas | Grows with its content on short screens and large font sizes instead of clipping. |
| Quick Connect | Lists every saved route (previously only the first eight) and includes Smart Connect. |
| Settings | Optimization and anti-filtering options are clearly marked as not yet applied to connections. |

### Fixed

| Area | Fix |
|---|---|
| Haptics | The phone no longer vibrates every second while connected; feedback fires only on real state changes. |
| Route health | Per-second engine updates no longer flood local history with duplicate `connected` events, which had pushed out real checks and made `Best now` unreliable. |
| Latency display | A failed check now clears the old latency instead of showing a stale value. |
| SSH | A failed VPN start now closes the SSH session behind it, and repeated connections no longer stack duplicate listeners. |
| Web latency | Removed simulated latency values; a failed measurement is shown as failed. |

### Removed

- Unused legacy splash screen, connection map widget and load balancer service.

## [4.0.2] - 2026-08-17 — 4SUPER

### Added

| Area | Change |
|---|---|
| Alive Signal Canvas | Replaced the static primary connection surface with a state-aware canvas driven by real engine states: ready, connecting, protected, disconnecting and error. |
| Quick Connect | Added a route-selection sheet with selected route, local `Best now` evidence, direct protect action and a real all-profile health-check action. |
| Connection Story | Added a local, redacted timeline for health checks, successful connections, failures and unexpected drops. It can surface the current engine error without showing raw profile URLs or credentials. |
| Server Studio | Replaced the basic profile list with health-aware cards showing protocol, selected state, score, latest latency, success rate, profile actions and persistent local Favorites. |
| Experience preferences | Added Standard, Reduced and Off motion settings plus Compact Server Studio density. These settings affect rendering only, never routing or tunnel behavior. |
| 4SUPER introduction | Added a one-time, dismissible launch sheet so new users can discover Alive Signal, Quick Connect and Connection Story. |

### Changed

| Area | Change |
|---|---|
| Home flow | The connect tab now provides Quick Connect and Connection Story directly from the primary surface; selected profile, recovery state and local health are visible in one context strip. |
| Versioning | Bumped Android package metadata to `versionName 4.0.2` and `versionCode 17`. |
| Download QR | README QR Code now targets the direct 4SUPER APK asset rather than a Release page. |

### Verified

- Flutter static analysis completed with no errors; existing project info-level lints remain documented.
- Existing parser, SSH round-trip and splash widget regression tests pass.
- The Release APK manifest is inspected before upload and must match `4.0.2+17`.

### Known limitations

| Feature | 4SUPER behavior |
|---|---|
| SSH over SlowDNS | Imported profiles retain their transport declaration, but connection remains clearly unsupported instead of falling back silently. |
| Kill Switch | Still not advertised as stable until an Android-native implementation is registered and tested under the actual application package. |
| Remote subscriptions | Not included in 4SUPER; the product remains focused on local user-owned profiles. |

---

## [4.0.0] - 2026-08-17

### Added

| Area | Change |
|---|---|
| Connection Navigator | Added a local-only, explainable profile-health score. It uses recorded successful checks, latency, recency and unexpected drops to recommend `Best now` without uploading profile data. |
| Connection history | Connection success, failure, probe result and unexpected drop events are retained locally for 14 days, with a maximum of 30 events per profile. |
| QR import | Replaced the scanner placeholder with a functional `mobile_scanner` camera flow, flash control, validation and manual-entry fallback. |
| Encrypted persistence | Moved profiles and settings into AES-256 encrypted Hive boxes. The wrapping key is created on-device and held by secure storage; legacy plaintext boxes are migrated once and removed after a successful copy. |
| Split Tunneling | Added Android platform-channel discovery of real launchable apps and passed selected app policy to both Xray and SSH-backed VPN starts. |
| SSH transports | Added explicit direct SSH, SSH-over-TLS and SSH-over-WebSocket transport handling. |
| Regression tests | Added tests for VLESS, VMess, Shadowsocks and NPVT SSH parsing, SSH round trips, unsupported schemes and splash lifecycle behavior. |

### Changed

| Area | Change |
|---|---|
| Auto-reconnect | A manual disconnect is now suppressed from recovery logic. Failover uses a configured profile queue and a bounded retry budget. |
| SSH/SOCKS gateway | Reworked the loopback-only SOCKS5 gateway with request parsing, IPv4/domain/IPv6 support, handshake timeout, per-channel cleanup and safer error handling. |
| NPVT export | SSH type values now round-trip correctly for direct, WebSocket, TLS and SlowDNS profile declarations. |
| Product language | README and in-app behavior now avoid security, availability and privacy overclaims. |

### Fixed

| Area | Fix |
|---|---|
| Hive adapter | Added the missing explicit `VpnConfigAdapter`, removing the dependency on a non-existent generated file. |
| App startup tests | Replaced uncancellable splash delays with disposable timers so widget tests do not leave pending timers. |
| Packaging | Added the missing `assets/images/` directory declared in `pubspec.yaml`. |

### Known limitations

| Feature | v4 behavior |
|---|---|
| SSH over SlowDNS | Import is retained, but connection stops with a clear unsupported-transport error instead of silently attempting a direct SSH session. |
| Kill Switch | Not exposed as a stable feature in v4 because the prior native implementation was not registered against the application package and was not safe to claim as enforced. |
| Remote subscriptions | v4 focuses on local user-owned profiles; subscription refresh is planned for a subsequent release. |

---

## [3.0.1] - 2025-01-07

### Fixed

- Settings persistence and scroll behavior were improved.
- Tunnel status and detailed connection statistics were refined.

## [3.0.0] - 2025-01-06

### Added

- Initial Xray profile management, animated connection UI, profile ping tests, themes and settings surfaces.

## [2.2.0] - 2025-01-04

### Added

- Initial Android VPN integration with VLESS, VMess, Trojan and Shadowsocks support.

## [1.0.0] - 2025-01-04

### Added

- Initial Hesam Void release.
