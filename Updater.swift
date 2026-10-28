// Updates for everyone you shared Pocket Pet with. It checks your GitHub releases every few hours; when there's a newer
// version it offers it, and one click downloads it, checks it was signed with your key (kept only on your Mac, so
// nobody else can push an update), swaps the app in place and restarts. Publishing is ./release.sh.

import Cocoa
import CryptoKit

final class Updater {
    struct Release {
        let version: String
        let zip: URL, sig: URL
        let notes: String
        let page: URL?
    }

    static let repo = Bundle.main.object(forInfoDictionaryKey: "PocketPetUpdateRepo") as? String ?? ""
    static let publicKey = Bundle.main.object(forInfoDictionaryKey: "PocketPetUpdateKey") as? String ?? ""
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    private(set) var available: Release?
    private(set) var status = ""
    private(set) var busy = false
    var onChange: (() -> Void)?
    var enabled: Bool { !Self.repo.isEmpty && !Self.publicKey.isEmpty }

    func check(_ done: (() -> Void)? = nil) {
        guard enabled, !busy, let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                defer { self.onChange?(); done?() }
                guard let json, let tag = json["tag_name"] as? String else { self.status = "Couldn't check for updates"; return }
                let v = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let assets = json["assets"] as? [[String: Any]] ?? []
                func asset(_ suffix: String) -> URL? {
                    assets.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }
                        .flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:))
                }
                guard Self.newer(v, than: Self.current), let zip = asset(".zip"), let sig = asset(".zip.sig") else {
                    self.available = nil
                    self.status = "Up to date"
                    return
                }
                self.available = Release(version: v, zip: zip, sig: sig, notes: json["body"] as? String ?? "",
                                         page: (json["html_url"] as? String).flatMap(URL.init(string:)))
                self.status = ""
            }
        }.resume()
    }

    /// "3.10" is newer than "3.9".
    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Downloads the new version, checks its signature, puts it in place of this one and restarts.
    func install() {
        guard let r = available, !busy else { return }
        busy = true
        status = "Updating to \(r.version)…"
        onChange?()
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<URL, Error> = Result {
                let zip = try Data(contentsOf: r.zip)
                let sig = try String(contentsOf: r.sig, encoding: .utf8)
                return try Self.install(zip: zip, signature: sig)
            }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let app): Self.relaunch(app)
                case .failure(let e):
                    self.status = e.localizedDescription
                    self.onChange?()
                }
            }
        }
    }

    /// The part that matters for safety, kept separate so it can be tried without the internet (`--apply-update`).
    static func install(zip: Data, signature: String, into here: URL = Bundle.main.bundleURL) throws -> URL {
        guard let keyData = Data(base64Encoded: publicKey), let sig = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData), key.isValidSignature(sig, for: zip) else {
            throw fail("This update isn't signed with the right key, so it wasn't installed.")
        }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pocketpet-update-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("update.zip")
        try zip.write(to: file)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", file.path, dir.path]
        try unzip.run()
        unzip.waitUntilExit()
        let fresh = dir.appendingPathComponent("Pocket Pet.app")
        guard unzip.terminationStatus == 0, Bundle(url: fresh)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw fail("The download didn't contain Pocket Pet.")
        }
        guard fm.isWritableFile(atPath: here.deletingLastPathComponent().path) else {
            throw fail("Pocket Pet's folder can't be changed from here. Get the new version from the release page instead.")
        }
        // swap: old aside, new in, old gone (and put back if anything fails)
        let old = here.deletingLastPathComponent().appendingPathComponent(".Pocket Pet (previous).app")
        try? fm.removeItem(at: old)
        try fm.moveItem(at: here, to: old)
        do { try fm.copyItem(at: fresh, to: here) } catch { try? fm.moveItem(at: old, to: here); throw error }
        try? fm.removeItem(at: old)
        return here
    }

    private static func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    private static func fail(_ msg: String) -> NSError { NSError(domain: "PocketPet", code: 1, userInfo: [NSLocalizedDescriptionKey: msg]) }

    // MARK: Your side: the signing key and signatures (used by release.sh)

    /// Makes your signing key pair: the private half stays in `dir` (only you can read it), the public half goes in the app.
    static func makeKey(in dir: String) throws -> String {
        let key = Curve25519.Signing.PrivateKey()
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let priv = (dir as NSString).appendingPathComponent("update-key")
        guard !fm.fileExists(atPath: priv) else { throw fail("A key already exists at \(priv); keep using it.") }
        fm.createFile(atPath: priv, contents: Data(key.rawRepresentation.base64EncodedString().utf8), attributes: [.posixPermissions: 0o600])
        return key.publicKey.rawRepresentation.base64EncodedString()
    }

    static func sign(_ file: String, keyFile: String) throws -> String {
        let raw = try String(contentsOfFile: keyFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let d = Data(base64Encoded: raw) else { throw fail("Unreadable key at \(keyFile)") }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: d)
        return try key.signature(for: Data(contentsOf: URL(fileURLWithPath: file))).base64EncodedString()
    }
}
