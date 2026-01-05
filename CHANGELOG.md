# Changelog

All notable changes to Hesam Void will be documented in this file.

## [2.2.0] - 2025-01-04

### Added
- Full VPN functionality with Xray Core 25.3.6
- VLESS + Reality protocol support (best for Iran)
- VMess, Trojan, Shadowsocks protocol support
- Live connection statistics (upload/download speed, duration)
- Bypass subnets for local network traffic
- Animated connect button with pulse and glow effects

### Fixed
- VPN tunnel now routes traffic correctly
- Config parsing using official flutter_v2ray methods
- Native library extraction for Android

### Changed
- Updated Android build configuration for proper ABI splits
- Improved VpnService based on official flutter_v2ray example

## [2.1.0] - 2025-01-04

### Added
- Big animated Connect button
- Connection statistics display
- Two-tab layout (CONNECT / SERVERS)

### Fixed
- Config parsing improvements

## [2.0.0] - 2025-01-04

### Added
- flutter_v2ray integration for real VPN functionality
- VPN mode (routes all traffic)
- Permission request handling

## [1.0.0] - 2025-01-04

### Added
- Initial release
- Terminal Green UI theme
- Config import from clipboard
- Config import from QR code
- Config export to QR code
- Config export to clipboard
- Delete config with confirmation
- Ping test for servers
- Sort by ping/name/date/protocol
- Secure local storage with Hive
- Animated background (Matrix style)
- JetBrains Mono font
