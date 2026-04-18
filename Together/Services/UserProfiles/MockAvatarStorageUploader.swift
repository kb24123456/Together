import Foundation

final class MockAvatarStorageUploader: AvatarStorageUploaderProtocol, @unchecked Sendable {
    struct UploadRecord {
        let bytes: Data
        let spaceID: UUID
        let userID: UUID
        let version: Int
    }

    private let lock = NSLock()
    private var _uploads: [UploadRecord] = []
    private var _stubbedURL: URL = URL(string: "https://example.test/avatars/stub.jpg?sig=1")!
    private var _stubbedDownloadBytes: Data = Data([0xFF, 0xD8, 0xFF])

    var uploads: [UploadRecord] {
        lock.lock(); defer { lock.unlock() }
        return _uploads
    }

    var stubbedURL: URL {
        get { lock.lock(); defer { lock.unlock() }; return _stubbedURL }
        set { lock.lock(); defer { lock.unlock() }; _stubbedURL = newValue }
    }

    var stubbedDownloadBytes: Data {
        get { lock.lock(); defer { lock.unlock() }; return _stubbedDownloadBytes }
        set { lock.lock(); defer { lock.unlock() }; _stubbedDownloadBytes = newValue }
    }

    func uploadAvatar(bytes: Data, spaceID: UUID, userID: UUID, version: Int) async throws -> URL {
        lock.lock()
        _uploads.append(UploadRecord(bytes: bytes, spaceID: spaceID, userID: userID, version: version))
        let url = _stubbedURL
        lock.unlock()
        return url
    }

    func downloadAvatar(from url: URL) async throws -> Data {
        lock.lock(); defer { lock.unlock() }
        return _stubbedDownloadBytes
    }
}
