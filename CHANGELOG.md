# Changelog

All notable changes to Hesam Void are documented in this file.

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
