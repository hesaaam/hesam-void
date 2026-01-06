# Hesam Void - Professional VPN Client

<p align="center">
  <img src="assets/icons/app_icon.png" width="120" alt="Hesam Void Logo">
</p>

<p align="center">
  <strong>A powerful, secure, and beautifully designed VPN client for Android</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-3.0.0-green" alt="Version">
  <img src="https://img.shields.io/badge/Flutter-3.35.4-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.9.2-0175C2?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Xray_Core-25.3.6-green" alt="Xray Core">
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="License">
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android" alt="Platform">
</p>

---

## What's New in v3.0.0

### Advanced Features
- **Smart Config Optimizer**: Auto-optimize MTU, buffer size, DNS for better speed
- **Fragment/Noise Injection**: DPI bypass techniques for strict networks (Iran)
- **Auto-Reconnect & Failover**: Automatic reconnection with server switching
- **Multi-Server Load Balancing**: Distribute traffic across multiple servers

### Enhanced UI/UX
- **Real-time Speed Graph**: Live animated upload/download graph with 60s history
- **Connection Map**: Visual server connection with animated path
- **Theme System**: 8 beautiful themes (Terminal Green, Cyberpunk Purple, Ocean Blue, Blood Red, Neon Orange, Electric Teal, Midnight Gold, Clean White)
- **Haptic Feedback**: Satisfying vibration on connect/disconnect and UI interactions
- **Split Tunneling**: Choose which apps use VPN (bypass games, local apps)

---

## Features

### Core VPN
- **Multi-Protocol Support**: VLESS, VMess, Trojan, Shadowsocks
- **Reality Protocol**: Full support for VLESS + Reality (best for Iran)
- **Bypass Subnets**: Local network traffic bypass (10.x, 192.168.x, 172.x)
- **Secure Storage**: Encrypted local storage with Hive

### Config Management
- **QR Code**: Import/Export configs via QR code
- **Clipboard Support**: Quick import from clipboard
- **Ping Test**: Measure server latency
- **Sorting**: Sort servers by ping, name, date, or protocol

### UI/UX
- **Beautiful UI**: Multiple theme options with smooth animations
- **Live Stats**: Real-time upload/download speed and duration
- **Matrix Background**: Animated cyberpunk-style background
- **Connection Animation**: Visual feedback during connection

---

## Screenshots

| Connect Screen | Servers Screen | Settings |
|:--------------:|:--------------:|:--------:|
| ![Connect](screenshots/connect.png) | ![Servers](screenshots/servers.png) | ![Settings](screenshots/settings.png) |

---

## Supported Protocols

| Protocol | Status | Description |
|----------|--------|-------------|
| VLESS + Reality | Full | Best for bypassing censorship |
| VLESS + TLS | Full | Secure with TLS encryption |
| VMess + WS | Full | WebSocket transport |
| VMess + TCP | Full | Direct TCP connection |
| Trojan | Full | HTTPS-like traffic |
| Shadowsocks | Full | Lightweight and fast |

---

## Installation

### Download APK
Download the latest APK from [Releases](../../releases/latest).

### Requirements
- Android 5.0 (API 21) or higher
- ARM64, ARM, or x86_64 architecture

### Build from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/hesaaam/hesam-void.git
   cd hesam-void
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Build APK**
   ```bash
   flutter build apk --release
   ```

4. **Find APK at**
   ```
   build/app/outputs/flutter-apk/app-release.apk
   ```

---

## Usage

1. **Add Server**: Go to SERVERS tab - Tap + - Import from clipboard or scan QR
2. **Select Server**: Tap on a server card to select it
3. **Connect**: Go to CONNECT tab - Tap the power button
4. **Grant Permission**: Allow VPN permission when prompted
5. **Enjoy**: Your traffic is now encrypted!

### Config URL Formats

```
vless://uuid@server:port?type=tcp&security=reality&...#Name
vmess://base64_encoded_config
trojan://password@server:port?...#Name
ss://base64_encoded_config#Name
```

---

## Tech Stack

| Technology | Version | Purpose |
|------------|---------|---------|
| Flutter | 3.35.4 | UI Framework |
| Dart | 3.9.2 | Programming Language |
| flutter_v2ray | 1.0.9 | V2Ray/Xray Core Integration |
| Xray Core | 25.3.6 | VPN Engine |
| Hive | 2.2.3 | Encrypted Local Storage |
| Provider | 6.1.5+1 | State Management |

---

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── vpn_config.dart       # VPN config data model
├── services/
│   ├── vpn_service.dart      # VPN connection service
│   ├── config_optimizer_service.dart  # Config optimization
│   ├── fragment_service.dart # DPI bypass techniques
│   ├── auto_reconnect_service.dart    # Auto reconnect
│   ├── load_balancer_service.dart     # Load balancing
│   ├── split_tunneling_service.dart   # Split tunneling
│   ├── haptic_service.dart   # Haptic feedback
│   └── ping_service.dart     # Server latency test
├── providers/
│   └── config_provider.dart  # Config state management
├── screens/
│   ├── home_screen.dart      # Main screen
│   ├── settings_screen.dart  # Settings with themes
│   ├── splash_screen.dart    # Animated splash
│   └── qr_scanner_screen.dart # QR scanner
├── widgets/
│   ├── connect_button.dart   # Animated connect button
│   ├── config_card.dart      # Server config card
│   ├── speed_graph.dart      # Real-time speed graph
│   ├── connection_map.dart   # Connection visualization
│   ├── animated_background.dart # Matrix-style background
│   └── qr_dialog.dart        # QR display dialog
└── utils/
    ├── app_theme.dart        # Base theme
    └── theme_manager.dart    # Multi-theme system
```

---

## Themes

| Theme | Description |
|-------|-------------|
| Terminal Green | Classic Matrix-style (default) |
| Cyberpunk Purple | Neon purple aesthetic |
| Ocean Blue | Calm blue tones |
| Blood Red | Bold red theme |
| Neon Orange | Vibrant orange |
| Electric Teal | Fresh teal colors |
| Midnight Gold | Luxurious gold accents |
| Clean White | Light mode option |

---

## Anti-Filtering Features

### For Iran (and similar regions)
- **Fragment Injection**: Split TLS hello packets
- **TLS Padding**: Add random padding to bypass DPI
- **SNI Randomization**: Randomize server name indication
- **TLS Fingerprinting**: Mimic browser fingerprints (Chrome, Firefox, Safari)
- **Reality Protocol**: Undetectable VPN traffic

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Disclaimer

This software is for educational purposes only. Users are responsible for complying with local laws and regulations. The developers are not responsible for any misuse of this software.

---

## Acknowledgments

- [flutter_v2ray](https://github.com/blueboy-tm/flutter_v2ray) - V2Ray Flutter plugin
- [Xray-core](https://github.com/XTLS/Xray-core) - The core engine
- [Flutter](https://flutter.dev) - UI framework

---

<p align="center">
  Made with love by <a href="https://github.com/hesaaam">Hesam</a>
</p>
