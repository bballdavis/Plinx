import Foundation

enum DemoYoutarrCatalog {
    private static let lock = NSLock()
    private static var requests: [[String: Any]] = []
    private static let fixture: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "youtarr", withExtension: "json", subdirectory: "DemoMedia"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }()

    static func reset() {
        lock.lock()
        requests.removeAll()
        lock.unlock()
    }

    static func response(for request: URLRequest) -> DemoFixtureResponse {
        guard let url = request.url else { return json([:], status: 400) }
        let path = String(url.path.dropFirst("/external-api/v1/".count))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        lock.lock()
        defer { lock.unlock() }
        let channels = (fixture["channels"] as? [String: Any])?["data"] as? [[String: Any]] ?? []
        var videos = (fixture["videos"] as? [String: Any])?["data"] as? [[String: Any]] ?? []
        for index in videos.indices {
            if let existing = requests.first(where: { ($0["target"] as? [String: Any])?["youtubeId"] as? String == videos[index]["youtubeId"] as? String }) {
                videos[index]["isRequested"] = true
                videos[index]["requestStatus"] = existing["status"]
            }
        }
        if path == "capabilities" { return json(fixture["capabilities"] as? [String: Any] ?? [:]) }
        if path.hasPrefix("assets/") {
            return DemoFixtureResponse(statusCode: 200, mimeType: "image/png", data: DemoFixtureCatalog.artworkPNG(path: "backdrop"))
        }
        if path == "channels" { return page(filterSearch(channels, query: query)) }
        if path == "videos" || (path.hasPrefix("channels/") && path.hasSuffix("/videos")) {
            if path.hasPrefix("channels/"), let channelID = Int(path.split(separator: "/")[1]) {
                videos = videos.filter { $0["channelDatabaseId"] as? Int == channelID }
            }
            let status = query.first(where: { $0.name == "status" })?.value ?? "requestable"
            let tab = query.first(where: { $0.name == "tab" })?.value
            if let tab, tab != "videos" { videos = [] }
            if status == "downloaded" || status == "available" { videos = videos.filter { $0["isDownloaded"] as? Bool == true } }
            if status == "requested" { videos = videos.filter { $0["isRequested"] as? Bool == true } }
            if status == "requestable" { videos = videos.filter { $0["isRequested"] as? Bool != true && $0["isDownloaded"] as? Bool != true } }
            let sort = query.first(where: { $0.name == "sortBy" })?.value ?? "date"
            let ascending = query.first(where: { $0.name == "sortOrder" })?.value == "asc"
            videos.sort { first, second in
                let key = sort == "title" ? "title" : "publishedAt"
                let left = first[key] as? String ?? ""
                let right = second[key] as? String ?? ""
                return ascending ? left < right : left > right
            }
            return page(filterSearch(videos, query: query))
        }
        if path.hasPrefix("videos/"), let id = path.split(separator: "/").last,
           var video = videos.first(where: { $0["youtubeId"] as? String == String(id) }) {
            video["channelDescription"] = "Original fictional sample channel."
            video["tags"] = ["family", "sample"]
            return json(video)
        }
        if path == "requests/videos", request.httpMethod == "POST",
           let body = request.httpBody,
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let id = object["youtubeId"] as? String,
           let video = videos.first(where: { $0["youtubeId"] as? String == id }),
           let channel = object["channelId"] as? Int,
           video["channelDatabaseId"] as? Int == channel {
            if let existing = requests.first(where: { ($0["target"] as? [String: Any])?["youtubeId"] as? String == id }) {
                return json(["outcome": "duplicate", "request": existing])
            }
            let date = ISO8601DateFormatter().string(from: Date())
            let item: [String: Any] = ["id": UUID().uuidString, "type": "video", "status": "pending",
                                       "target": ["youtubeId": id, "channelId": channel],
                                       "createdAt": date, "updatedAt": date,
                                       "message": "Sample request only; no external download is scheduled."]
            requests.append(item)
            return json(["outcome": "created", "request": item])
        }
        if path == "requests" {
            let status = query.first(where: { $0.name == "status" })?.value
            return page(requests.filter { status == nil || $0["status"] as? String == status })
        }
        if path.hasPrefix("requests/"), let item = requests.first(where: { $0["id"] as? String == String(path.dropFirst("requests/".count)) }) {
            return json(item)
        }
        return json(["error": "unknown sample endpoint"], status: 404)
    }

    private static func filterSearch(_ values: [[String: Any]], query: [URLQueryItem]) -> [[String: Any]] {
        guard let search = query.first(where: { $0.name == "search" })?.value, !search.isEmpty else { return values }
        return values.filter { ($0["title"] as? String ?? "").localizedCaseInsensitiveContains(search) }
    }

    private static func page(_ values: [[String: Any]]) -> DemoFixtureResponse {
        json(["data": values, "pagination": ["page": 1, "pageSize": max(1, values.count), "total": values.count, "totalPages": 1],
              "dataSource": "sample", "isFullyIndexed": true])
    }

    private static func json(_ value: [String: Any], status: Int = 200) -> DemoFixtureResponse {
        DemoFixtureResponse(statusCode: status, mimeType: "application/json", data: (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8))
    }
}
