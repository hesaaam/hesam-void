# Hesam Void - Professional VPN Client

<p align="center">
  <img src="assets/icons/app_icon.png" width="120" alt="Hesam Void Logo">
</p>

<p align="center">
  <strong>A powerful, secure, and beautifully designed VPN client for Android</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.35.4-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.9.2-0175C2?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Xray_Core-25.3.6-green" alt="Xray Core">
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="License">
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android" alt="Platform">
</p>

---

## Features

- **Multi-Protocol Support**: VLESS, VMess, Trojan, Shadowsocks
- **Reality Protocol**: Full support for VLESS + Reality (best for Iran)
- **Beautiful UI**: Terminal Green theme with smooth animations
- **QR Code**: Import/Export configs via QR code
- **Clipboard Support**: Quick import from clipboard
- **Ping Test**: Measure server latency
- **Live Stats**: Real-time upload/download speed and duration
- **Secure Storage**: Encrypted local storage with Hive
- **Sorting**: Sort servers by ping, name, date, or protocol

---

## Screenshots

| Connect Screen | Servers Screen | QR Scanner |
|:--------------:|:--------------:|:----------:|
| ![Connect](screenshots/connect.png) | ![Servers](screenshots/servers.png) | ![QR](screenshots/qr.png) |

---

## Supported Protocols

| Protocol | Status | Description |
|----------|--------|-------------|
| VLESS + Reality | ✅ Full | Best for bypassing censorship |
| VLESS + TLS | ✅ Full | Secure with TLS encryption |
| VMess + WS | ✅ Full | WebSocket transport |
| VMess + TCP | ✅ Full | Direct TCP connection |
| Trojan | ✅ Full | HTTPS-like traffic |
| Shadowsocks | ✅ Full | Lightweight and fast |

---

## Installation

### Download APK
Download the latest APK from [Releases](../../releases).

### Build from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/hesam-void.git
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

1. **Add Server**: Go to SERVERS tab → Tap + → Import from clipboard or scan QR
2. **Select Server**: Tap on a server card to select it
3. **Connect**: Go to CONNECT tab → Tap the power button
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
│   ├── config_parser_service.dart  # Config URL parser
│   └── ping_service.dart     # Server latency test
├── providers/
│   └── config_provider.dart  # Config state management
├── screens/
│   ├── home_screen.dart      # Main screen (Connect + Servers)
│   ├── splash_screen.dart    # Splash screen
│   └── qr_scanner_screen.dart # QR scanner
├── widgets/
│   ├── connect_button.dart   # Animated connect button
│   ├── config_card.dart      # Server config card
│   ├── animated_background.dart # Matrix-style background
│   └── qr_dialog.dart        # QR display dialog
└── utils/
    └── app_theme.dart        # Terminal Green theme
```

---

## Building for Production

### Android APK
```bash
flutter build apk --release
```

### Android App Bundle (for Play Store)
```bash
flutter build appbundle --release
```

### Split APKs by Architecture
The project is configured to build split APKs for different architectures:
- `arm64-v8a` (most modern devices)
- `armeabi-v7a` (older devices)
- `x86_64` (emulators)

---

## Configuration

### Android Manifest Permissions
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.CAMERA"/>
```

### Bypass Subnets
Local network traffic is automatically bypassed:
- `10.0.0.0/8`
- `192.168.0.0/16`
- `172.16.0.0/12`

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
  Made with ❤️ by <a href="https://github.com/YOUR_USERNAME">Hesam</a>
</p>
