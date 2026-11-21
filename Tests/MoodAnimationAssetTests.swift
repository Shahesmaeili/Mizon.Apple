#if os(macOS) || os(iOS)
import Foundation
import MizonAPI
import Testing
@testable import MizonAppleCore

struct MoodAnimationAssetTests {
    @Test func tgsDecodesToAnAtomicallyCachedLottieFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let json = Data(#"{"v":"5.7.4","fr":30,"ip":0,"op":30,"w":208,"h":208,"layers":[]}"#.utf8)
        let source = directory.appending(path: "effect.tgs")
        try CompressionMethod.gzip.compress(json).write(to: source)
        let decoded = try await MoodAnimationAsset.jsonFile(for: source)
        #expect(decoded != source)
        #expect(try Data(contentsOf: decoded) == json)
        #expect(try await MoodAnimationAsset.jsonFile(for: source) == decoded)
    }

    @Test func truncatedAndOversizedGzipAreRejected() throws {
        let gzip = try CompressionMethod.gzip.compress(Data(repeating: 0x41, count: 4096))
        #expect(throws: LoginFailure.self) { try MoodAnimationAsset.expandGzip(gzip.dropLast()) }
        #expect(throws: LoginFailure.self) { try MoodAnimationAsset.expandGzip(gzip, limit: 1024) }
    }
}
#endif
