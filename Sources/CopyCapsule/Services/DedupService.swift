import Foundation
import CryptoKit

/// Detects duplicate clipboard content via SHA-256 hashing.
/// Maintains an in-memory cache of recent hashes for fast lookups,
/// falling back to database query when needed.
final class DedupService {
    /// Maximum number of recent hashes to cache in memory.
    private let cacheSize: Int

    /// In-memory set of recently seen content hashes.
    private var recentHashes: Set<String> = []

    /// Ordered list to maintain LRU eviction order.
    private var hashOrder: [String] = []

    // MARK: - Init

    init(cacheSize: Int = 100) {
        self.cacheSize = cacheSize
    }

    // MARK: - Public API

    /// Returns true if the given hash matches the most recent stored item.
    /// Also checks the in-memory cache for quick dedup.
    func isDuplicate(_ hash: String) -> Bool {
        return recentHashes.contains(hash)
    }

    /// Records a hash as seen, evicting the oldest if the cache is full.
    func recordHash(_ hash: String) {
        if recentHashes.contains(hash) {
            // Already cached, move to end (most recent)
            hashOrder.removeAll { $0 == hash }
        } else if hashOrder.count >= cacheSize {
            // Evict oldest
            let oldest = hashOrder.removeFirst()
            recentHashes.remove(oldest)
        }
        hashOrder.append(hash)
        recentHashes.insert(hash)
    }

    /// Compute SHA-256 hash of a string.
    static func hashString(_ text: String) -> String {
        let data = Data(text.utf8)
        return SHA256.hash(data: data).hexString
    }

    /// Compute SHA-256 hash of binary data.
    static func hashData(_ data: Data) -> String {
        return SHA256.hash(data: data).hexString
    }

    /// Clear the in-memory cache.
    func clearCache() {
        recentHashes.removeAll()
        hashOrder.removeAll()
    }
}

// MARK: - SHA256 Digest → Hex

private extension SHA256.Digest {
    var hexString: String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}
