import Foundation

#if canImport(Darwin)
import Darwin
#endif

struct Conflict: Identifiable, Equatable {
    let id = UUID()
    let tunnelA: String
    let tunnelB: String
    let overlap: String
}

struct CIDR: Equatable {
    let original: String
    let prefix: Int
    let isIPv6: Bool

    // IPv4
    let address: UInt32

    // IPv6
    let ipv6Bytes: [UInt8]?

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        self.original = trimmed

        if trimmed.contains(":") {
            // IPv6
            self.isIPv6 = true
            self.address = 0
            let parts = trimmed.split(separator: "/")
            guard let addrPart = parts.first else { return nil }

            var bytes = [UInt8](repeating: 0, count: 16)
            let ok = addrPart.withCString { inet_pton(AF_INET6, $0, &bytes) == 1 }
            guard ok else { return nil }

            self.ipv6Bytes = bytes
            self.prefix = parts.count > 1 ? Int(parts[1]) ?? 128 : 128
        } else {
            // IPv4
            self.isIPv6 = false
            self.ipv6Bytes = nil
            let parts = trimmed.split(separator: "/")
            guard let addrPart = parts.first else { return nil }

            var addr = in_addr()
            let ok = addrPart.withCString { inet_pton(AF_INET, $0, &addr) == 1 }
            guard ok else { return nil }

            // `s_addr` is in network (big-endian) byte order; convert to host order.
            self.address = UInt32(addr.s_addr).byteSwapped
            self.prefix = parts.count > 1 ? Int(parts[1]) ?? 32 : 32
        }
    }

    func networkAddress() -> UInt32 {
        guard !isIPv6 else { return 0 }
        let mask: UInt32 = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix))
        return address & mask
    }

    func overlaps(with other: CIDR) -> Bool {
        guard isIPv6 == other.isIPv6 else { return false }

        if isIPv6 {
            return overlapsIPv6(with: other)
        } else {
            return overlapsIPv4(with: other)
        }
    }

    private func overlapsIPv4(with other: CIDR) -> Bool {
        let minPrefix = min(prefix, other.prefix)
        let mask: UInt32 = minPrefix == 0 ? 0 : (0xFFFFFFFF << (32 - minPrefix))
        return (address & mask) == (other.address & mask)
    }

    private func overlapsIPv6(with other: CIDR) -> Bool {
        let minPrefix = min(prefix, other.prefix)
        let fullBytes = minPrefix / 8
        let remainingBits = minPrefix % 8

        for i in 0..<fullBytes {
            if ipv6Bytes![i] != other.ipv6Bytes![i] { return false }
        }

        if remainingBits > 0 {
            let mask: UInt8 = 0xFF << (8 - remainingBits)
            return (ipv6Bytes![fullBytes] & mask) == (other.ipv6Bytes![fullBytes] & mask)
        }

        return true
    }
}

struct ConflictDetector {
    static func conflicts(among tunnels: [Tunnel]) -> [Conflict] {
        var conflicts: [Conflict] = []

        for i in 0..<tunnels.count {
            for j in (i + 1)..<tunnels.count {
                let a = tunnels[i]
                let b = tunnels[j]
                let cidrsA = collectCIDRs(from: a.config)
                let cidrsB = collectCIDRs(from: b.config)

                for cidrA in cidrsA {
                    for cidrB in cidrsB {
                        if cidrA.overlaps(with: cidrB) {
                            conflicts.append(Conflict(
                                tunnelA: a.name,
                                tunnelB: b.name,
                                overlap: cidrA.original
                            ))
                        }
                    }
                }
            }
        }

        return conflicts
    }

    private static func collectCIDRs(from config: WireGuardConfig) -> [CIDR] {
        var result: [CIDR] = []
        result.append(contentsOf: config.interface.addresses.compactMap { CIDR($0) })
        for peer in config.peers {
            result.append(contentsOf: peer.allowedIPs.compactMap { CIDR($0) })
        }
        return result
    }
}
