# Windows TUN reference note

Source: https://xtls.github.io/en/config/inbounds/tun.html

The official Xray TUN inbound documentation states that Windows is supported and describes a `settings` object containing `name`, `desc`, `mtu`, `gateway`, `dns`, `userLevel`, `autoSystemRoutingTable`, and `autoOutboundsInterface`. It states that `autoSystemRoutingTable` can direct full IPv4/IPv6 traffic into the created interface, and that `autoOutboundsInterface: "auto"` keeps Xray's own upstream traffic outside its TUN to avoid a routing loop. The documentation also notes that TUN setup may require OS-side routing support.

This note supports the Windows 4SUPER configuration contract and should be used with the primary documentation rather than as a replacement for it.
