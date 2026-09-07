import Foundation

protocol DiskStoring {
    func write<T: Encodable>(_ value: T, name: String)
    func writeChecked<T: Codable & Equatable>(_ value: T, name: String) throws
    func read<T: Decodable>(_ type: T.Type, name: String) -> T?
    func readIfPresent<T: Decodable>(_ type: T.Type, name: String) throws -> T?
    func exists(name: String) -> Bool
    func delete(name: String)
}

struct DiskStore: DiskStoring {
    private let directory: URL
    private let decoder = HTTPClient.makeDecoder()
    private let encoder = HTTPClient.makeEncoder()

    init(folder: String = "Moneyknows") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write<T: Encodable>(_ value: T, name: String) {
        let url = directory.appendingPathComponent(name)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func writeChecked<T: Codable & Equatable>(_ value: T, name: String) throws {
        let url = directory.appendingPathComponent(name)
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw AppError.decoding
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw AppError.decoding
        }
        let loaded: T
        do {
            guard let verified = try readIfPresent(T.self, name: name) else {
                throw AppError.decoding
            }
            loaded = verified
        } catch {
            throw AppError.decoding
        }
        guard loaded == value else {
            throw AppError.decoding
        }
    }

    func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        try? readIfPresent(type, name: name)
    }

    func readIfPresent<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
        let url = directory.appendingPathComponent(name)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if Self.isMissingFile(error) {
                return nil
            }
            throw AppError.decoding
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding
        }
    }

    private static func isMissingFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(ENOENT)
        }
        return false
    }

    func exists(name: String) -> Bool {
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func delete(name: String) {
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }
}
