#if os(macOS) || os(iOS)
import CZlib
import Foundation

enum MoodAnimationAsset {
    static let maximumBytes = 8 * 1024 * 1024

    @concurrent
    static func jsonFile(for source: URL) async throws -> URL {
        try Task.checkCancellation()
        let data = try Data(contentsOf: source, options: [.mappedIfSafe])
        guard !data.isEmpty, data.count <= maximumBytes else { throw LoginFailure.invalidResponse }
        guard data.starts(with: [0x1F, 0x8B]) else {
            guard source.pathExtension.lowercased() != "tgs" else { throw LoginFailure.invalidResponse }
            return source
        }

        // Cache beside the original hash-keyed media file. Atomic writes allow two
        // views to request the same asset without observing a partially decoded file.
        let target = source.appendingPathExtension("json")
        if let length = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           length > 0, length <= maximumBytes { return target }
        let decoded = try expandGzip(data)
        try Task.checkCancellation()
        try decoded.write(to: target, options: .atomic)
        return target
    }

    static func expandGzip(_ data: Data, limit: Int = maximumBytes) throws -> Data {
        guard !data.isEmpty, data.count <= maximumBytes, limit > 0, limit <= maximumBytes else {
            throw LoginFailure.invalidResponse
        }
        var stream = z_stream()
        guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION,
                           Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw LoginFailure.invalidResponse }
        defer { inflateEnd(&stream) }

        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var expanded = Data()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            var status: Int32
            repeat {
                try Task.checkCancellation()
                let result = buffer.withUnsafeMutableBytes { bytes in
                    stream.next_out = bytes.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(bytes.count)
                    let status = inflate(&stream, Z_NO_FLUSH)
                    return (status, bytes.count - Int(stream.avail_out))
                }
                status = result.0
                guard status == Z_OK || status == Z_STREAM_END, result.1 <= limit - expanded.count else {
                    throw LoginFailure.invalidResponse
                }
                expanded.append(contentsOf: buffer.prefix(result.1))
            } while status != Z_STREAM_END
            guard !expanded.isEmpty, stream.avail_in == 0 else { throw LoginFailure.invalidResponse }
            return expanded
        }
    }
}
#endif
