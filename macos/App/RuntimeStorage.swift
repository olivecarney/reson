import Foundation

// Resolve all default writable locations together. XCTest and development builds
// cannot fall back to personal storage, even when a caller omits injection.
struct RuntimeStorage {
    let root: URL?
    let database: URL
    let artwork: URL
    let preferences: UserDefaults
    var isolated: Bool { root != nil }
    static let current: RuntimeStorage = {
        do {
            let testing = ProcessInfo.processInfo.arguments.first?.contains(".xctest") == true
                || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                || NSClassFromString("XCTestCase") != nil
            return try resolve(environment: ProcessInfo.processInfo.environment, testing: testing)
        } catch { fatalError("reson storage isolation failed: \(error.localizedDescription)") }
    }()
    static func resolve(environment: [String: String], testing: Bool) throws -> RuntimeStorage {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let personal = home.appendingPathComponent("Library/Application Support/Reson")
        let cache = home.appendingPathComponent("Library/Caches/Reson")
        if environment["RESON_LIBRARY_PATH"] != nil {
            throw LibraryError(message:"Use RESON_DATA_ROOT to isolate database, artwork and preferences together.")
        }
        let root: URL?
        if let raw = environment["RESON_DATA_ROOT"] {
            guard raw.hasPrefix("/"), !raw.contains("\0"), !raw.isEmpty else {
                throw LibraryError(message:"RESON_DATA_ROOT must be an absolute, separate directory.")
            }
            root = URL(fileURLWithPath:raw).standardizedFileURL.resolvingSymlinksInPath()
        } else if testing {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("reson-tests-" + UUID().uuidString).resolvingSymlinksInPath()
        } else if environment["RESON_ISOLATED"] == "1" || Bundle.main.bundleIdentifier == "dev.reson.player.smoke" {
            throw LibraryError(message:"RESON_ISOLATED requires an explicit RESON_DATA_ROOT.")
        } else if _isDebugAssertConfiguration() || Bundle.main.bundleIdentifier == nil || Bundle.main.bundleIdentifier == "dev.reson.player.development" {
            root = home.appendingPathComponent("Library/Application Support/Reson Development")
        } else { root = nil }
        guard let root else {
            return RuntimeStorage(root:nil,database:personal.appendingPathComponent("library.db"),artwork:cache.appendingPathComponent("Artwork"),preferences:.standard)
        }
        func inside(_ a: URL, _ b: URL) -> Bool { a.path == b.path || a.path.hasPrefix(b.path + "/") }
        for protected in [personal,cache] {
            let protected = protected.resolvingSymlinksInPath()
            guard !inside(root,protected), !inside(protected,root) else {
                throw LibraryError(message:"Isolated storage must be separate from personal reson data.")
            }
        }
        for name in ["library.db", "library.db-wal", "library.db-shm", "Artwork", "Preferences.plist"] {
            let child=root.appendingPathComponent(name)
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath:child.path)) == nil else {
                throw LibraryError(message:"Isolated storage contains a symbolic link.")
            }
            let target=child.resolvingSymlinksInPath()
            guard inside(target,root) else {throw LibraryError(message:"Isolated storage contains a link outside its root.")}
        }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        return RuntimeStorage(root:root,database:root.appendingPathComponent("library.db"),artwork:root.appendingPathComponent("Artwork"),preferences:try FilePreferences(url:root.appendingPathComponent("Preferences.plist")))
    }
}

// UserDefaults-compatible preferences whose entire persistent domain lives inside
// the isolated root. No test/development values are written to standard defaults.
private final class FilePreferences: UserDefaults {
    private let url: URL
    private let lock = NSLock()
    private var values: [String: Any]
    init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath:url.path) {
            values = try PropertyListSerialization.propertyList(from:Data(contentsOf:url),format:nil) as? [String:Any] ?? [:]
        } else { values = [:] }
        super.init(suiteName:"dev.reson.isolated." + UUID().uuidString)!
    }
    override func object(forKey key: String) -> Any? { lock.lock(); defer {lock.unlock()}; return values[key] }
    override func bool(forKey key: String) -> Bool { (object(forKey:key) as? NSNumber)?.boolValue ?? false }
    override func double(forKey key: String) -> Double { (object(forKey:key) as? NSNumber)?.doubleValue ?? 0 }
    override func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer {lock.unlock()}
        values[key] = value
        do { try PropertyListSerialization.data(fromPropertyList:values,format:.binary,options:0).write(to:url,options:.atomic) }
        catch { fatalError("Could not save isolated preferences: \(error.localizedDescription)") }
    }
}
