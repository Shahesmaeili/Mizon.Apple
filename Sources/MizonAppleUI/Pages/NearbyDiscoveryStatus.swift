#if os(macOS) || os(iOS)
import Foundation
import MizonAppleCore
import Observation
#if os(macOS)
import SystemConfiguration
#else
import UIKit
#endif

enum NearbyDiscoveryStatus: Equatable {
    case off, searching, ready, permissionDenied, unavailable
}

@MainActor @Observable
final class NearbyDiscoveryModel {
    var enabled = false
    private(set) var peers: [NearbyDiscoveredPeer] = []
    private(set) var status: NearbyDiscoveryStatus = .off

    @ObservationIgnored private let service: any NearbyDiscovering
    @ObservationIgnored private var generation: UInt = 0

    init(service: any NearbyDiscovering = NearbyDiscoveryService()) {
        self.service = service
    }

    func discover(inForeground: Bool, publicUsername: String?, displayName: String?) async {
        generation &+= 1
        let currentGeneration = generation
        peers = []
        status = enabled && inForeground ? .searching : .off
        guard enabled, inForeground, !Task.isCancelled else { return }
        let identity = Self.advertisement(publicUsername: publicUsername, displayName: displayName)
        let events = await service.start(advertising: identity)
        for await event in events {
            guard !Task.isCancelled, generation == currentGeneration else { return }
            switch event {
            case .peers(let detected):
                peers = detected
                status = .ready
            case .searching:
                status = .searching
            case .unavailable:
                peers = []
                status = .unavailable
            case .permissionDenied:
                peers = []
                status = .permissionDenied
            }
        }
    }

    private static func advertisement(publicUsername: String?, displayName: String?) -> NearbyPresenceAdvertisement {
        #if os(macOS)
        let platform: NearbyPeerPlatform = .macOS
        let deviceName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac"
        #else
        let platform: NearbyPeerPlatform = .iOS
        let deviceName = UIDevice.current.name
        #endif
        let account = publicUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
        let publicAccount = account.flatMap { name in
            !name.isEmpty && AuthIdentifierInput.isAllowed(name, allowsEmail: false) ? name : nil
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return .local(id: UUID(), platform: platform, appVersion: version,
                      deviceName: deviceName, account: publicAccount, displayName: displayName)
    }
}
#endif
