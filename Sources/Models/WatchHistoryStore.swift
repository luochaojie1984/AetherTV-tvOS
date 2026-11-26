import Foundation

struct WatchHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    var id: String { item.id }
    var item: MediaItem
    var lastPositionSeconds: Double
    var durationSeconds: Double
    var updatedAt: Date

    /// 单片轨道与画面比例记忆
    var audioTrackId: Int? = nil
    var primarySubtitleTrackId: Int? = nil
    var primarySubtitleDisabled: Bool? = nil
    var secondarySubtitleTrackId: Int? = nil
    var aspectMode: VideoAspectMode? = nil

    var progress: Double {
        guard durationSeconds > 1 else { return 0 }
        return min(max(lastPositionSeconds / durationSeconds, 0), 1)
    }

    var isFinished: Bool {
        progress >= 0.94
    }
}

@MainActor
final class WatchHistoryStore: ObservableObject {
    static let shared = WatchHistoryStore()

    @Published var history: [WatchHistoryEntry] = [] {
        didSet {
            guard !isLoading else { return }
            saveHistory()
        }
    }
    @Published var favorites: [MediaItem] = [] {
        didSet {
            guard !isLoading else { return }
            saveFavorites()
        }
    }

    private let historyKey = "AetherTV.WatchHistory.v1"
    private let favoritesKey = "AetherTV.Favorites.v1"
    private var isLoading = false

    private init() {
        load()
    }

    var continueWatching: [WatchHistoryEntry] {
        history
            .filter { !$0.isFinished && $0.lastPositionSeconds > 10 }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func savedPosition(for itemId: String) -> Double? {
        guard let entry = history.first(where: { $0.id == itemId }),
              !entry.isFinished,
              entry.lastPositionSeconds > 8 else { return nil }
        return entry.lastPositionSeconds
    }

    func trackMemory(for itemId: String) -> WatchHistoryEntry? {
        history.first(where: { $0.id == itemId })
    }

    func recordProgress(item: MediaItem, position: Double, duration: Double) {
        guard duration > 5, position.isFinite else { return }
        let existing = history.first(where: { $0.id == item.id })
        let entry = WatchHistoryEntry(
            item: item.sanitizedForPersistence(),
            lastPositionSeconds: position,
            durationSeconds: duration,
            updatedAt: Date(),
            audioTrackId: existing?.audioTrackId,
            primarySubtitleTrackId: existing?.primarySubtitleTrackId,
            primarySubtitleDisabled: existing?.primarySubtitleDisabled,
            secondarySubtitleTrackId: existing?.secondarySubtitleTrackId,
            aspectMode: existing?.aspectMode
        )
        history.removeAll { $0.id == item.id }
        history.insert(entry, at: 0)
        if history.count > 80 {
            history = Array(history.prefix(80))
        }
    }

    /// 记录用户为单部影片选择的音轨 / 主副字幕轨 / 画面比例（不改变已保存的续播时间点）
    func recordTrackSelection(
        for item: MediaItem,
        audioTrackId: Int? = nil,
        primarySubtitleTrackId: Int? = nil,
        primarySubtitleDisabled: Bool? = nil,
        secondarySubtitleTrackId: Int? = nil,
        clearSecondarySubtitle: Bool = false,
        aspectMode: VideoAspectMode? = nil
    ) {
        var entry = history.first(where: { $0.id == item.id }) ?? WatchHistoryEntry(
            item: item.sanitizedForPersistence(),
            lastPositionSeconds: 0,
            durationSeconds: item.durationSeconds ?? 0,
            updatedAt: Date()
        )
        entry.item = item.sanitizedForPersistence()
        if let audioTrackId {
            entry.audioTrackId = audioTrackId
        }
        if let primarySubtitleDisabled {
            entry.primarySubtitleDisabled = primarySubtitleDisabled
            if primarySubtitleDisabled {
                entry.primarySubtitleTrackId = nil
            }
        }
        if let primarySubtitleTrackId {
            entry.primarySubtitleTrackId = primarySubtitleTrackId
            entry.primarySubtitleDisabled = false
        }
        if clearSecondarySubtitle {
            entry.secondarySubtitleTrackId = nil
        } else if let secondarySubtitleTrackId {
            entry.secondarySubtitleTrackId = secondarySubtitleTrackId
        }
        if let aspectMode {
            entry.aspectMode = aspectMode
        }

        if let idx = history.firstIndex(where: { $0.id == item.id }) {
            history[idx] = entry
        } else {
            history.insert(entry, at: 0)
            if history.count > 80 {
                history = Array(history.prefix(80))
            }
        }
    }

    func clearProgress(for itemId: String) {
        history.removeAll { $0.id == itemId }
    }

    func isFavorite(_ item: MediaItem) -> Bool {
        favorites.contains { $0.id == item.id }
    }

    func toggleFavorite(_ item: MediaItem) {
        if let idx = favorites.firstIndex(where: { $0.id == item.id }) {
            favorites.remove(at: idx)
        } else {
            favorites.insert(item.sanitizedForPersistence(), at: 0)
        }
    }

    func reloadFromStorage() {
        load()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([WatchHistoryEntry].self, from: data) {
            let cleaned = decoded.map { entry -> WatchHistoryEntry in
                var copy = entry
                copy.item = entry.item.sanitizedForPersistence()
                return copy
            }
            history = cleaned
            if cleaned != decoded {
                saveHistory()
            }
        }
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([MediaItem].self, from: data) {
            let cleaned = decoded.map { $0.sanitizedForPersistence() }
            favorites = cleaned
            if cleaned != decoded {
                saveFavorites()
            }
        }
    }

    private func saveHistory() {
        let sanitized = history.map { entry -> WatchHistoryEntry in
            var copy = entry
            copy.item = entry.item.sanitizedForPersistence()
            return copy
        }
        if let encoded = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }

    private func saveFavorites() {
        let sanitized = favorites.map { $0.sanitizedForPersistence() }
        if let encoded = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(encoded, forKey: favoritesKey)
        }
    }
}
