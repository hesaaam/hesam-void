# Third-Party Runtime Notices

## Xray-core

The Windows Preview bundles `xray.exe` from the official [XTLS/Xray-core](https://github.com/XTLS/Xray-core) Windows AMD64 release, currently pinned in the build script to `v26.3.27`.

Xray-core is distributed under the Mozilla Public License 2.0. Its source and license are available at <https://github.com/XTLS/Xray-core>.

## Wintun

The Windows Preview bundles the signed AMD64 `wintun.dll` from the official Wintun distribution, currently pinned in the build script to `0.14.1`. The downloadable signed DLLs are the supported distribution form and are released under the license included in the official archive. The source project is GPL-2.0; see <https://www.wintun.net/> and <https://git.zx2c4.com/wintun/about/>.

The build workflow validates the official Wintun archive SHA-256 before staging `wintun.dll`. The runtime binaries are generated during a build and are deliberately excluded from the source repository.
