import Foundation

/// JSON files in Application Support/<namespace>/. Live and demo data use separate namespaces.
final class LocalStore {
    let directory: URL

    init(namespace: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent(namespace, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        let url = directory.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, _ name: String) {
        let url = directory.appendingPathComponent("\(name).json")
        guard let data = try? Self.encoder.encode(value) else { return }
        // Readable after first unlock so notification actions (energy taps) can save while locked.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func wipe() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
