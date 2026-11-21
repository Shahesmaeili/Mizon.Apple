import Foundation
import Network
import Testing
@testable import MizonAppleCore

struct NearbyDiscoveryCodecTests {
    private let id = UUID(uuidString: "052a451b-cbe1-455d-8007-4f67d4f9bc36")!

    @Test func exchangesWindowsVersionOneTXTThroughNetworkFramework() throws {
        let wire = packet(["v=1", "id=052a451b-cbe1-455d-8007-4f67d4f9bc36", "platform=windows", "app=2.0.0",
            "device=Music PC", "account=public_user", "display=میزون"])
        let name = "Mizon-052a451b-cbe1-455d-8007-4f67d4f9bc36"
        let record = NWTXTRecord(wire)
        let expected = NearbyPresenceAdvertisement(id: id, platform: .windows, appVersion: "2.0.0",
            deviceName: "Music PC", account: "public_user", displayName: "میزون")
        #expect(NearbyAdvertisementCodec.serviceType == "_mizon-peer._tcp")
        #expect(NearbyAdvertisementCodec.domain == "local.")
        #expect(NearbyAdvertisementCodec.serviceName(for: id) == name)
        #expect(NearbyAdvertisementCodec.decode(record.data, serviceName: name) == expected)
        #expect(NearbyAdvertisementCodec.encode(expected) == wire)
        #expect(Set(NearbyPeerPlatform.allCases.map(\.rawValue)) == ["windows", "macos", "ios", "android", "watchos", "wearos"])

        let noIdentity = NearbyPresenceAdvertisement(id: id, platform: .iOS, appVersion: "2.0", deviceName: "Fixture iPhone")
        let publicRecord = NWTXTRecord(try #require(NearbyAdvertisementCodec.encode(noIdentity)))
        #expect(publicRecord.getEntry(for: "account") == nil)
        #expect(publicRecord.getEntry(for: "display") == nil)
    }

    @Test func publishesTheMediaPinAndKeepsPresenceWhenAnOptionalPinIsMalformed() throws {
        let pin = String(repeating: "a1", count: 32)
        let presence = NearbyPresenceAdvertisement(id: id, platform: .macOS, appVersion: "1",
                                                  deviceName: "Fixture Mac", mediaCertificateSHA256: pin)
        let name = NearbyAdvertisementCodec.serviceName(for: id)
        let record = try #require(NearbyAdvertisementCodec.encode(presence))
        #expect(NearbyAdvertisementCodec.decode(NWTXTRecord(record).data, serviceName: name) == presence)

        let broken = packet(["v=1", "id=052a451b-cbe1-455d-8007-4f67d4f9bc36", "platform=macos", "app=1",
                             "device=Fixture Mac", "media=1", "cert=\(pin.uppercased())"])
        let recovered = try #require(NearbyAdvertisementCodec.decode(broken, serviceName: name))
        #expect(recovered.id == id)
        #expect(recovered.mediaCertificateSHA256 == nil)
    }

    @Test func acceptsOnlyValidOptionalMediaPortsAndRetainsTheOriginalServiceOtherwise() throws {
        let pin = String(repeating: "d2", count: 32)
        let name = NearbyAdvertisementCodec.serviceName(for: id)
        let presence = ["v=1", "id=\(id.uuidString.lowercased())", "platform=windows", "app=1", "device=Fixture PC"]
        let media = presence + ["media=1", "cert=\(pin)"]

        let alternate = try #require(NearbyAdvertisementCodec.decode(packet(media + ["media-port=65535"]), serviceName: name))
        #expect(alternate.mediaPort == 65535)
        #expect(NearbyAdvertisementCodec.encode(alternate) == packet(media + ["media-port=65535"]))

        for value in ["", "0", "65536", "-2", "+2", "2 ", "۲", "2.0"] {
            let decoded = try #require(NearbyAdvertisementCodec.decode(packet(media + ["media-port=\(value)"]), serviceName: name))
            #expect(decoded.mediaCertificateSHA256 == pin)
            #expect(decoded.mediaPort == nil)
        }
        let absent = try #require(NearbyAdvertisementCodec.decode(packet(media), serviceName: name))
        #expect(absent.mediaCertificateSHA256 == pin)
        #expect(absent.mediaPort == nil)
        #expect(NearbyAdvertisementCodec.decode(packet(presence + ["media-port=4000"]), serviceName: name)?.mediaPort == nil)
    }

    @Test func rejectsMalformedAndUnrecognizedAnnouncements() {
        let prefix = ["v=1", "id=\(id.uuidString.lowercased())", "platform=windows", "app=2.1"]
        let serviceName = NearbyAdvertisementCodec.serviceName(for: id)
        let valid = packet(prefix + ["device=Windows PC"])
        let malformed = [
            valid.dropLast(), Data([1, 0xFF]), valid + Data([2, 0xFF, 0x3D]), valid + Data([0]),
            packet(prefix + ["device=First", "DEVICE=Second"]), packet(prefix + ["device"]),
            packet(prefix + ["device=   "]), packet(prefix + ["device=PC", "display=\u{202E}spoof"]),
            packet(prefix + ["device=PC", "account=\u{00}missing"]), packet(prefix + ["device=PC", "unknown=secret"]),
            packet(prefix + ["device=\(String(repeating: "é", count: 49))"]),
            packet(prefix + ["device=PC", "account=\(String(repeating: "a", count: 65))"]),
            packet(["v=2"] + prefix.dropFirst() + ["device=Future"]),
            packet(["v=1", "id=\(id.uuidString)", "platform=windows", "app=1.0", "device=Uppercase ID"]),
            packet(["v=1", "id=\(id.uuidString.lowercased())", "platform=other", "app=1.0", "device=Other OS"]),
            Data(repeating: 1, count: 401)
        ]
        #expect(NearbyAdvertisementCodec.decode(valid, serviceName: serviceName)?.deviceName == "Windows PC")
        for entry in malformed {
            #expect(NearbyAdvertisementCodec.decode(entry, serviceName: serviceName) == nil)
        }
        #expect(NearbyAdvertisementCodec.decode(valid, serviceName: NearbyAdvertisementCodec.serviceName(for: UUID())) == nil)
    }

    @Test func normalizesLocalLabelsAndTruncatesAtGraphemeBoundaries() throws {
        let longPrefix = String(repeating: "a", count: 95)
        let ad = NearbyPresenceAdvertisement.local(id: id, platform: .macOS, appVersion: "  e\u{0301}  ",
            deviceName: "\(longPrefix)👩🏽‍💻", account: "  \u{061C}\u{07} ", displayName: "  می‌\u{202E}زون ")
        #expect(Array(ad.appVersion.utf8) == [0xC3, 0xA9])
        #expect(ad.deviceName == longPrefix)
        #expect(ad.account == nil)
        #expect(ad.displayName == "می‌زون")
        let record = try #require(NearbyAdvertisementCodec.encode(ad))
        #expect(NearbyAdvertisementCodec.decode(record, serviceName: NearbyAdvertisementCodec.serviceName(for: id)) == ad)

        let fallback = NearbyPresenceAdvertisement.local(id: id, platform: .iOS, appVersion: "\n", deviceName: " \u{202E}")
        #expect(fallback.appVersion == "1.0")
        #expect(fallback.deviceName == "iPhone")
        #expect(fallback.displayName == nil)
        #expect(fallback.account == nil)
    }

    @Test func dropsTheLocalDeviceAndConflictingIdentitiesAndCapsTheList() {
        let duplicate = UUID()
        let conflict = UUID()
        let repeated = ad(duplicate, device: "Fixture 001")
        let backgroundPeers = (2...110).map { ad(UUID(), device: "Fixture \($0)") }
        let candidates = [ad(id, device: "Local"), repeated, repeated,
            ad(conflict, device: "Conflicted 1"), ad(conflict, device: "Conflicted 2")] + backgroundPeers
        let results = NearbyPeerList.make(from: candidates, excluding: id)
        #expect(results.count == 64)
        #expect(Set(results.map(\.id)).count == 64)
        #expect(!results.contains { $0.id == id || $0.id == conflict })
        #expect(results.first?.id == duplicate)
    }

    @Test func invalidAndCancelledStartsFinishWithoutStartingNetworkWork() async {
        let service = NearbyDiscoveryService()
        let invalid = await service.start(advertising: ad(id, device: "\u{00}"))
        var invalidEvents = invalid.makeAsyncIterator()
        #expect(await invalidEvents.next() == .unavailable)
        #expect(await invalidEvents.next() == nil)

        let cancelled = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await service.start(advertising: ad(id, device: "Valid Local Fixture"))
        }.value
        var cancelledEvents = cancelled.makeAsyncIterator()
        #expect(await cancelledEvents.next() == nil)
    }

    private func ad(_ id: UUID, device: String) -> NearbyPresenceAdvertisement {
        NearbyPresenceAdvertisement(id: id, platform: .windows, appVersion: "1.0", deviceName: device)
    }

    private func packet(_ entries: [String]) -> Data {
        var packet = Data()
        for entry in entries {
            packet.append(UInt8(entry.utf8.count))
            packet.append(contentsOf: entry.utf8)
        }
        return packet
    }
}
