import Foundation
import SystemConfiguration

/// The interface policy. Only Wi-Fi and wired Ethernet are ever offered.
/// VPN, tunnel, bridge, virtual, cellular, and loopback interfaces are not
/// listed and never carry a listener, a multicast group, or a reply.
struct NetworkInterface: Identifiable, Hashable {
    /// The BSD name, such as "en0". The stable identifier in Preferences.
    var name: String
    /// What System Settings calls it, such as "Wi-Fi".
    var displayName: String
    /// IPv4 addresses with their netmasks, as 32-bit host-order integers.
    var ipv4: [(address: UInt32, mask: UInt32)]

    var id: String { name }

    /// True when `address` sits on the same link as one of this interface's addresses.
    func isOnLink(_ address: UInt32) -> Bool {
        ipv4.contains { (address & $0.mask) == ($0.address & $0.mask) }
    }

    var addressStrings: [String] { ipv4.map { NetworkInterfaces.string(fromIPv4: $0.address) } }

    static func == (lhs: NetworkInterface, rhs: NetworkInterface) -> Bool {
        lhs.name == rhs.name && lhs.displayName == rhs.displayName
            && lhs.ipv4.map(\.address) == rhs.ipv4.map(\.address)
            && lhs.ipv4.map(\.mask) == rhs.ipv4.map(\.mask)
    }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

enum NetworkInterfaces {
    /// The eligible interfaces that are up and have an IPv4 address.
    static func eligible() -> [NetworkInterface] {
        let kinds = hardwareKinds()
        var byName: [String: NetworkInterface] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            guard let display = kinds[name] else { continue }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0 else { continue }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            var mask: UInt32 = 0xFFFF_FFFF
            if let netmask = entry.pointee.ifa_netmask {
                mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            }
            // Link-local 169.254/16 carries no service here.
            if address >> 16 == 0xA9FE { continue }
            var iface = byName[name] ?? NetworkInterface(name: name, displayName: display, ipv4: [])
            iface.ipv4.append((address, mask))
            byName[name] = iface
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    /// BSD name → display name, for Wi-Fi and Ethernet hardware only.
    private static func hardwareKinds() -> [String: String] {
        var out: [String: String] = [:]
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return out }
        for iface in all {
            guard let type = SCNetworkInterfaceGetInterfaceType(iface) as String?,
                  let bsd = SCNetworkInterfaceGetBSDName(iface) as String? else { continue }
            let allowed = type == (kSCNetworkInterfaceTypeIEEE80211 as String) || type == (kSCNetworkInterfaceTypeEthernet as String)
            guard allowed else { continue }
            let display = (SCNetworkInterfaceGetLocalizedDisplayName(iface) as String?) ?? bsd
            // Thunderbolt and USB bridges report as Ethernet; keep them, they are wires.
            out[bsd] = display
        }
        return out
    }

    /// The interfaces the user allows: the eligible ones, filtered by the
    /// names in Preferences. An empty list in Preferences means all eligible.
    static func allowed(prefs: Preferences) -> [NetworkInterface] {
        let all = eligible()
        let chosen = Set(prefs.transferInterfaces)
        if chosen.isEmpty { return all }
        return all.filter { chosen.contains($0.name) }
    }

    static func ipv4(from string: String) -> UInt32? {
        var addr = in_addr()
        guard inet_pton(AF_INET, string, &addr) == 1 else { return nil }
        return UInt32(bigEndian: addr.s_addr)
    }

    static func string(fromIPv4 value: UInt32) -> String {
        "\(value >> 24).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    /// True when the address is on the link of one allowed interface. IPv6
    /// peers are refused in this phase; the listener only binds IPv4.
    static func isOnAllowedLink(_ address: String, interfaces: [NetworkInterface]) -> Bool {
        guard let value = ipv4(from: address) else { return false }
        return interfaces.contains { $0.isOnLink(value) }
    }
}
