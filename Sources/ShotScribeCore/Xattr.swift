import Foundation
import Darwin

/// One place for the two-call `getxattr` dance. `Naming` reads macOS's
/// capture flag through it; `EditStore` keeps its link to a kept edit in it.
enum Xattr {
    static func read(_ name: String, at path: String, limit: Int = 4096) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0, size <= limit else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard getxattr(path, name, &bytes, size, 0, 0) == size else { return nil }
        return Data(bytes)
    }

    @discardableResult
    static func write(_ data: Data, _ name: String, at path: String) -> Bool {
        data.withUnsafeBytes { setxattr(path, name, $0.baseAddress, data.count, 0, 0) == 0 }
    }

    static func remove(_ name: String, at path: String) {
        _ = removexattr(path, name, 0)
    }
}
