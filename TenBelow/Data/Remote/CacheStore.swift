import Foundation

enum CacheStore {

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static func save<T: Encodable>(_ object: T, to fileName: String) {
        let url = cacheDirectory.appendingPathComponent(fileName)
        do {
            let data = try JSONEncoder().encode(object)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("[CacheStore] Failed to write \(fileName): \(error)")
            #endif
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        let url = cacheDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static func loadFromBundle<T: Decodable>(_ type: T.Type, resource: String) -> T? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }
}
