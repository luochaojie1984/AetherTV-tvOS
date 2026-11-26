import SwiftUI
import UIKit

/// 带请求头鉴权与局域网自签名证书支持的异步海报视图（替代无法注入 Token Header 的原生 AsyncImage）
struct AuthenticatedPosterImage<Placeholder: View>: View {
    let url: URL?
    let sourceId: UUID?
    @ViewBuilder let placeholder: () -> Placeholder

    @ObservedObject private var settings = PlayerSettingsStore.shared
    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadPoster()
        }
    }

    private func loadPoster() async {
        guard let url else {
            loadedImage = nil
            return
        }
        if let cached = PosterMemoryCache.shared.object(forKey: url as NSURL) {
            loadedImage = cached
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        if let sourceId,
           let source = MediaSourceStore.shared.sources.first(where: { $0.id == sourceId }) {
            for (k, v) in NetworkPitfallGuards.standardHTTPHeaders(for: source) {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }

        let session = NetworkPitfallGuards.sharedSession(allowSelfSignedLAN: settings.allowSelfSignedCertificates)
        guard let (data, resp) = try? await session.data(for: request),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let uiImage = UIImage(data: data) else {
            return
        }
        PosterMemoryCache.shared.setObject(uiImage, forKey: url as NSURL, cost: data.count)
        loadedImage = uiImage
    }
}

private enum PosterMemoryCache {
    static let shared: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 80
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
}
