import Foundation

struct WatchHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    var id: String { item.id }
    var item: MediaItem
    var lastPositionSeconds: Double
    var durationSeconds: Double
    var updatedAt: Date

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

    @Published var history: [WatchHistoryEntry] = [] { didSet { saveHistory() } }
    @Published var favorites: [MediaItem] = [] { didSet { saveFavorites() } }

    private let historyKey = "AetherTV.WatchHistory.v1"
    private let favoritesKey = "AetherTV.Favorites.v1"

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

    func recordProgress(item: MediaItem, position: Double, duration: Double) {
        guard duration > 5, position.isFinite else { return }
        let entry = WatchHistoryEntry(
            item: item,
            lastPositionSeconds: position,
            durationSeconds: duration,
            updatedAt: Date()
        )
        history.removeAll { $0.id == item.id }
        history.insert(entry, at: 0)
        if history.count > 80 {
            history = Array(history.prefix(80))
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
            favorites.insert(item, at: 0)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([WatchHistoryEntry].self, from: data) {
            history = decoded
        }
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([MediaItem].self, from: data) {
            favorites = decoded
        }
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }

    private func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encoded, forKey: favoritesKey)
        }
    }
}
