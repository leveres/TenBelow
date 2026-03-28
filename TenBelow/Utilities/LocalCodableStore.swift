import Foundation

enum LocalCodableStore {
    static func load<Value: Codable>(
        key: String,
        default defaultValue: @autoclosure () -> Value,
        userDefaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> Value {
        guard let data = userDefaults.data(forKey: key),
              let value = try? decoder.decode(Value.self, from: data) else {
            return defaultValue()
        }
        return value
    }

    static func save<Value: Codable>(
        _ value: Value,
        key: String,
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        guard let data = try? encoder.encode(value) else { return }
        userDefaults.set(data, forKey: key)
    }

    static func remove(
        key: String,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.removeObject(forKey: key)
    }
}
