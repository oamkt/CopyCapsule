import Foundation

/// Periodically purges clipboard items older than the configured retention period.
/// Favorited items are permanent. Pinned items expire after 7 days (auto-unpin).
/// Recent items follow the configured retentionDays setting.
@MainActor
final class RetentionService {
    private var timer: Timer?
    private let repository: ClipRepository
    private let settings: AppSettings

    /// Check interval: every hour
    private static let checkInterval: TimeInterval = 3600
    /// Pinned items auto-unpin after 7 days.
    private static let pinnedExpiryDays = 7

    init(repository: ClipRepository, settings: AppSettings) {
        self.repository = repository
        self.settings = settings
    }

    /// Start periodic cleanup. Also runs an immediate cleanup.
    func start() {
        purgeNow()

        timer = Timer.scheduledTimer(
            withTimeInterval: Self.checkInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.purgeNow()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Purge

    /// 1. Auto-unpin items pinned longer than 7 days → fall back to Recent
    /// 2. Delete non-favorited items older than the configured retention period
    func purgeNow() {
        // Step 1: expire old pinned items (7-day limit)
        do {
            let unpinned = try repository.expirePinned(days: Self.pinnedExpiryDays)
            if unpinned > 0 {
                print("[CopyCapsule] Retention: unpinned \(unpinned) item(s) (older than \(Self.pinnedExpiryDays) days)")
            }
        } catch {
            print("[CopyCapsule] Pinned expiry failed: \(error.localizedDescription)")
        }

        // Step 2: purge old non-favorited recent items
        let days = settings.retentionDays
        guard days > 0 else { return }

        do {
            let count = try repository.purgeOlderThan(days: days)
            if count > 0 {
                print("[CopyCapsule] Retention: purged \(count) items (older than \(days) day(s))")
            }
        } catch {
            print("[CopyCapsule] Retention purge failed: \(error.localizedDescription)")
        }
    }
}
