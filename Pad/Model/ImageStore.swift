import CryptoKit
import DashUpKit
import Observation
import UIKit

/// App icons, favicons and artwork fetched from the Mac, cached in memory and on disk.
@Observable
final class ImageStore {
    enum Key: Hashable {
        case app(String)
        case favicon(String)
        case artwork(String)

        var id: String {
            switch self {
            case .app(let id): "app:\(id)"
            case .favicon(let url): "fav:\(URL(string: url)?.host() ?? url)"
            case .artwork(let id): "art:\(id)"
            }
        }

        var request: Request {
            switch self {
            case .app(let id): .appIcon(bundleID: id)
            case .favicon(let url): .favicon(url: url)
            case .artwork(let id): .artwork(trackID: id)
            }
        }
    }

    @ObservationIgnored var fetch: ((Request) async -> Response)?
    private(set) var images: [String: UIImage] = [:]
    @ObservationIgnored private var attempted: Set<String> = []
    @ObservationIgnored private let directory: URL
    private let demo: Bool

    init(demo: Bool) {
        self.demo = demo
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "images")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns the cached image, starting a fetch the first time a key is seen.
    func image(_ key: Key) -> UIImage? {
        if let image = images[key.id] { return image }
        if !attempted.contains(key.id) {
            attempted.insert(key.id)
            Task { await load(key) }
        }
        return nil
    }

    private func load(_ key: Key) async {
        let file = directory.appending(path: Self.filename(key.id))
        if case .artwork = key {} else if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            images[key.id] = image
            // Refresh in the background so icons pick up changes.
            if demo { return }
        }
        if demo {
            if case .app(let id) = key, let image = UIImage(named: "Demo/\(id)") { images[key.id] = image }
            return
        }
        guard let fetch else { return }
        let response = await fetch(key.request)
        switch response {
        case .image(let data?):
            if let image = UIImage(data: data) {
                images[key.id] = image
                if case .artwork = key {} else { try? data.write(to: file) }
            }
        case .failed:
            // Not connected yet; allow another attempt later.
            attempted.remove(key.id)
        default:
            break
        }
    }

    private static func filename(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
