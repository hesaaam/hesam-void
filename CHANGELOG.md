# Changelog

All notable changes to Hesam Void will be documented in this file.

## [3.0.1] - 2025-01-07

### Fixed 🐛
- **Settings Persistence**: All OPTIMIZE settings now persist after app restart
  - Auto Optimize Speed, DNS Provider, MTU Size
  - Fragment Injection, TLS Padding, SNI Randomization
  - Auto Reconnect, Reconnect Delay, Max Retries
- **UI Scroll Issues**: Fixed last item cut off in Theme and Optimize tabs
- **Tunnel Active Badge**: Moved badge to proper position (no longer overlaps server info)
- **Detailed View**: Improved Speed Graph layout with additional stats row

### Changed
- Added TLS Fingerprint selector in OPTIMIZE tab
- Better padding in all scrollable lists (bottom: 100px)
- Version updated to 3.0.1

### Technical
- Services now use Hive boxes for persistent storage
- ConfigOptimizerService, FragmentService, AutoReconnectService all support JSON serialization
- Settings initialized in main.dart before app starts

---

## [3.0.0] - 2025-01-06

### Added - Major Feature Update

#### Smart Optimization
- **Config Optimizer**: Auto-optimize MTU, buffer size, DNS for better speed
- **Fragment Injection**: DPI bypass with TCP packet splitting
- **TLS Padding**: Random padding to bypass deep packet inspection
- **SNI Randomization**: Randomize server name indication
- **TLS Fingerprinting**: Mimic browser fingerprints (Chrome, Firefox, Safari)

#### Connection Management
- **Auto-Reconnect**: Automatic reconnection when connection drops
- **Failover**: Switch to next server after max retries
- **Health Check**: Periodic connection health monitoring
- **Load Balancing**: Distribute traffic across multiple servers

#### Enhanced UI/UX
- **Real-time Speed Graph**: Animated upload/download graph with 60s history
- **Connection Map**: Visual server connection with animated path
- **8 Beautiful Themes**: Terminal Green, Cyberpunk Purple, Ocean Blue, Blood Red, Neon Orange, Electric Teal, Midnight Gold, Clean White
- **Custom Theme Creator**: Create your own theme with color picker
- **Haptic Feedback**: Satisfying vibration on all interactions

#### Split Tunneling
- **App Bypass**: Choose apps to bypass VPN (games, local apps)
- **VPN Only Mode**: Choose apps that use VPN exclusively
- **Popular Apps List**: Quick access to common apps

#### Settings Screen
- **Organized Settings**: 4-tab layout (Theme, Optimize, Split, General)
- **Visual DNS Selector**: Choose DNS provider with one tap
- **Slider Controls**: Easy adjustment for MTU, retries, delays

### Changed
- Updated version to 3.0.0
- Improved home screen with advanced stats toggle
- Enhanced connect button with theme support
- Better config card with theme colors

### Fixed
- Theme consistency across all screens
- Animation performance improvements

---

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
