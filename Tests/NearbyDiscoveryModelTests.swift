#if os(macOS) || os(iOS)
import Foundation
import MizonAppleCore
import Testing
@testable import MizonAppleUI

@MainActor
struct NearbyDiscoveryModelTests {
    @Test func waitsForOptInAndStopsShowingPeersOutsideTheForeground() async {
        let neighbor = NearbyDiscoveredPeer(advertisement: NearbyPresenceAdvertisement(
            id: UUID(), platform: .windows, appVersion: "1.0", deviceName: "Fixture PC", account: "other-account"
        ))
        let service = FixtureNearbyDiscovery(events: [.searching, .peers([neighbor])])
        let model = NearbyDiscoveryModel(service: service)
        await model.discover(inForeground: true, publicUsername: "mizon_user", displayName: "Mizon User")
        #expect(service.advertisements.isEmpty)
        #expect(model.status == .off)

        model.enabled = true
        await model.discover(inForeground: true, publicUsername: "mizon_user", displayName: "Mizon User")
        #expect(service.advertisements.last?.account == "mizon_user")
        #expect(model.peers == [neighbor])
        #expect(model.status == .ready)

        await model.discover(inForeground: false, publicUsername: "mizon_user", displayName: "Mizon User")
        #expect(service.advertisements.count == 1)
        #expect(model.peers.isEmpty)
        #expect(model.status == .off)
    }

    @Test func omitsAnEmailLikeIdentifierAndShowsPermissionDenial() async {
        let service = FixtureNearbyDiscovery(events: [.searching, .permissionDenied])
        let model = NearbyDiscoveryModel(service: service)
        model.enabled = true
        await model.discover(inForeground: true, publicUsername: "someone@example.org", displayName: "Public profile")
        #expect(service.advertisements.count == 1)
        #expect(service.advertisements.last?.account == nil)
        #expect(service.advertisements.last?.displayName == "Public profile")
        #expect(model.status == .permissionDenied)
        #expect(model.peers.isEmpty)
    }
}

@MainActor
private final class FixtureNearbyDiscovery: NearbyDiscovering {
    let events: [NearbyDiscoveryEvent]
    private(set) var advertisements: [NearbyPresenceAdvertisement] = []

    init(events: [NearbyDiscoveryEvent]) {
        self.events = events
    }

    func start(advertising advertisement: NearbyPresenceAdvertisement) async -> AsyncStream<NearbyDiscoveryEvent> {
        advertisements.append(advertisement)
        let (stream, continuation) = AsyncStream<NearbyDiscoveryEvent>.makeStream()
        events.forEach { continuation.yield($0) }
        continuation.finish()
        return stream
    }

    func stop() async {}
}
#endif
