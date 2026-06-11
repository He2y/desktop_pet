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
    private var activeAction: PetAction?
    private var activeFrames: [NSImage] = []

    init(root: URL? = nil) throws {
        self.root = try root ?? Self.locateSpriteRoot()
        var loadedURLs: [PetAction: [URL]] = [:]
        for action in PetAction.allCases {
            loadedURLs[action] = try Self.loadFrameURLs(for: action, root: self.root)
        }
        self.frameURLs = loadedURLs
    }

    func frameCount(for action: PetAction) -> Int {
        frameURLs[action, default: []].count
    }

    func image(for action: PetAction, index: Int) -> NSImage? {
        guard frameCount(for: action) > 0 else { return nil }
        do {
            try prepare(action: action)
        } catch {
            return nil
        }
        return activeFrames[index % activeFrames.count]
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

    private func prepare(action: PetAction) throws {
        guard activeAction != action else { return }
        let urls = frameURLs[action, default: []]
        guard !urls.isEmpty else {
            throw SpriteStoreError.noFrames(action: action.rawValue)
        }

        activeFrames = try urls.map { url in
            guard let image = NSImage(contentsOf: url) else {
                throw SpriteStoreError.imageLoadFailed(url)
            }
            image.isTemplate = false
            return image
        }
        activeAction = action
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
}
