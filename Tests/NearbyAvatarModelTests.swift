#if os(macOS) || os(iOS)
import CoreGraphics
import Foundation
import MizonAppleCore
import Testing
@testable import MizonAppleUI

@MainActor
struct NearbyAvatarModelTests {
    @Test func resolvesEachPublicAccountOnceAndReusesResultsWhenReopened() async throws {
        let model = NearbyAvatarModel()
        let avatar = try fixtureImage()
        let fetches = AvatarFetches()
        let names = NearbyAvatarModel.usernames(for: [
            fixturePeer(account: " Test.User "),
            fixturePeer(account: "test.user"),
            fixturePeer(account: "display@example.org"),
            fixturePeer(account: nil),
            fixturePeer(account: "missing")
        ])
        #expect(names == ["missing", "test.user"])
        let load: @Sendable (String) async throws -> CGImage? = { name in
            await fetches.record(name)
            return name == "test.user" ? avatar : nil
        }
        await model.load(for: names, using: load)
        #expect(model.images["test.user"] != nil)
        #expect(model.images["missing"] == nil)
        await model.load(for: [], using: load)
        #expect(model.images.isEmpty)
        await model.load(for: names, using: load)
        #expect(await fetches.usernames.sorted() == names)
        #expect(model.images["test.user"] != nil)
    }

    @Test func aClosedPickerCancelsAndIgnoresALateImage() async throws {
        let model = NearbyAvatarModel()
        let avatar = try fixtureImage()
        let (started, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let request = Task {
            await model.load(for: ["test.user"]) { _ in
                signal.yield(())
                try? await Task.sleep(for: .seconds(10))
                return avatar
            }
        }
        var events = started.makeAsyncIterator()
        _ = await events.next()
        request.cancel()
        await model.load(for: []) { _ in nil }
        await request.value
        #expect(model.images.isEmpty)
    }

    private func fixturePeer(account: String?) -> NearbyDiscoveredPeer {
        NearbyDiscoveredPeer(advertisement: .init(id: UUID(), platform: .windows, appVersion: "1.0",
                                                  deviceName: "Fixture", account: account, displayName: "display"))
    }

    private func fixtureImage() throws -> CGImage {
        try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
    }
}

private actor AvatarFetches {
    private(set) var usernames: [String] = []
    func record(_ username: String) { usernames.append(username) }
}
#endif
