import Combine
import Foundation
import UIKit

enum YoutarrAssetRoute {
    case authenticated(URLRequest)
    case publicURL(URL)
    case unavailable
}

enum YoutarrAssetRequestPolicy {
    static func route(
        rawURL: String?,
        configuration: YoutarrConfiguration
    ) -> YoutarrAssetRoute {
        guard let rawURL = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty,
              let url = resolvedURL(rawURL, configuration: configuration),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              components.fragment == nil else {
            return .unavailable
        }

        if sameOrigin(url, configuration.baseURL),
           isExternalAPIAsset(url, configuration: configuration) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
            if let additionalHeader = configuration.additionalHeader {
                request.setValue(
                    additionalHeader.value,
                    forHTTPHeaderField: additionalHeader.name
                )
            }
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            return .authenticated(request)
        }

        // Public imagery never receives the Youtarr API key and is limited to
        // the explicit YouTube image hosts emitted by the server contract.
        if components.scheme?.lowercased() == "https",
           isAllowedPublicImageHost(components.host) {
            return .publicURL(url)
        }
        return .unavailable
    }

    private static func resolvedURL(
        _ rawURL: String,
        configuration: YoutarrConfiguration
    ) -> URL? {
        let externalAPIPrefix = "/external-api/v1/"
        if rawURL.hasPrefix(externalAPIPrefix) {
            return configuration.endpointURL(
                path: String(rawURL.dropFirst(externalAPIPrefix.count))
            )
        }
        if let absolute = URL(string: rawURL), absolute.scheme != nil {
            return absolute
        }
        return URL(
            string: rawURL,
            relativeTo: configuration.endpointURL(path: "")
        )?.absoluteURL
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = URLComponents(url: lhs, resolvingAgainstBaseURL: false),
              let right = URLComponents(url: rhs, resolvingAgainstBaseURL: false) else {
            return false
        }
        return left.scheme?.lowercased() == right.scheme?.lowercased()
            && left.host?.lowercased() == right.host?.lowercased()
            && effectivePort(left) == effectivePort(right)
    }

    private static func effectivePort(_ components: URLComponents) -> Int? {
        if let port = components.port { return port }
        switch components.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    private static func isExternalAPIAsset(
        _ url: URL,
        configuration: YoutarrConfiguration
    ) -> Bool {
        var apiRoot = configuration.endpointURL(path: "").path
        while apiRoot.hasSuffix("/") { apiRoot.removeLast() }
        return url.path.hasPrefix(apiRoot + "/assets/")
    }

    private static func isAllowedPublicImageHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return [
            "i.ytimg.com",
            "img.youtube.com",
            "yt3.ggpht.com",
            "yt3.googleusercontent.com",
        ].contains(host)
    }
}

@MainActor
final class YoutarrImageMemoryCache {
    static let shared = YoutarrImageMemoryCache()

    private let cache = NSCache<NSURL, UIImage>()

    init(countLimit: Int = 100, totalCostLimit: Int = 32 * 1_024 * 1_024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL, cost: Int) {
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

@MainActor
final class YoutarrAuthenticatedImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var didFail = false

    private let session: any YoutarrHTTPSession
    private let cache: YoutarrImageMemoryCache

    init(
        session: any YoutarrHTTPSession = YoutarrHTTPSessions.noRedirects,
        cache: YoutarrImageMemoryCache? = nil
    ) {
        self.session = session
        self.cache = cache ?? .shared
    }

    func load(_ request: URLRequest) async {
        guard let url = request.url else {
            didFail = true
            return
        }
        if let cached = cache.image(for: url) {
            image = cached
            didFail = false
            return
        }

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode),
                  let image = UIImage(data: data) else {
                didFail = true
                return
            }
            cache.insert(image, for: url, cost: data.count)
            self.image = image
            didFail = false
        } catch is CancellationError {
            // Scrolling a thumbnail off screen is intentionally silent.
        } catch {
            didFail = true
        }
    }
}
