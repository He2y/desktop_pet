import AppKit
import Foundation

enum SpriteStoreError: LocalizedError {
    case spriteRootNotFound([String])
    case actionMissing(String)
    case noFrames(action: String)
    case imageLoadFailed(URL)

    var errorDescription: String? {
        switch self {
        case .spriteRootNotFound(let candidates):
            "Could not find sprite assets. Checked: \(candidates.joined(separator: ", "))"
        case .actionMissing(let action):
            "Missing sprite action folder: \(action)"
        case .noFrames(let action):
            "No PNG frames found for \(action)."
        case .imageLoadFailed(let url):
            "Could not load image: \(url.path)"
        }
    }
}

final class SpriteStore {
    private let root: URL
    private let frameURLs: [PetAction: [URL]]
    private let cache = NSCache<NSString, NSImage>()

    init(root: URL? = nil) throws {
        self.root = try root ?? Self.locateSpriteRoot()
        var loadedURLs: [PetAction: [URL]] = [:]
        for action in PetAction.allCases {
            loadedURLs[action] = try Self.loadFrameURLs(for: action, root: self.root)
        }
        self.frameURLs = loadedURLs
        cache.countLimit = 160
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func frameCount(for action: PetAction) -> Int {
        frameURLs[action, default: []].count
    }

    func image(for action: PetAction, index: Int) -> NSImage? {
        let urls = frameURLs[action, default: []]
        guard !urls.isEmpty else { return nil }

        let normalizedIndex = index % urls.count
        let cacheKey = "\(action.rawValue):\(normalizedIndex)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let url = urls[normalizedIndex]
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = false
        cache.setObject(image, forKey: cacheKey, cost: Self.estimatedCost(for: image))
        return image
    }

    static func locateSpriteRoot() throws -> URL {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let envPath = ProcessInfo.processInfo.environment["DESKTOP_PET_SPRITE_ROOT"], !envPath.isEmpty {
            candidates.append(URL(fileURLWithPath: envPath, isDirectory: true))
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("assets/sprites", isDirectory: true))
        }

        if let moduleResourceURL = Bundle.module.resourceURL {
            candidates.append(moduleResourceURL.appendingPathComponent("assets/sprites", isDirectory: true))
        }

        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        candidates.append(cwd.appendingPathComponent("assets/sprites", isDirectory: true))
        candidates.append(cwd.deletingLastPathComponent().appendingPathComponent("assets/sprites", isDirectory: true))

        for candidate in candidates {
            let probe = candidate.appendingPathComponent("walk/frame_000.png")
            if fileManager.fileExists(atPath: probe.path) {
                return candidate
            }
        }

        throw SpriteStoreError.spriteRootNotFound(candidates.map(\.path))
    }

    private static func loadFrameURLs(for action: PetAction, root: URL) throws -> [URL] {
        let actionURL = root.appendingPathComponent(action.rawValue, isDirectory: true)
        guard FileManager.default.fileExists(atPath: actionURL.path) else {
            throw SpriteStoreError.actionMissing(action.rawValue)
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: actionURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "png" && $0.lastPathComponent.hasPrefix("frame_") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !urls.isEmpty else {
            throw SpriteStoreError.noFrames(action: action.rawValue)
        }

        return urls
    }

    private static func estimatedCost(for image: NSImage) -> Int {
        let representation = image.representations.first
        let width = representation?.pixelsWide ?? Int(image.size.width)
        let height = representation?.pixelsHigh ?? Int(image.size.height)
        return max(1, width * height * 4)
    }
}
