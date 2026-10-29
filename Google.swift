// Sign in with Google (OAuth in the browser), then read Calendar events.
// Uses your own OAuth client (a "Desktop app" client from Google Cloud); the refresh token lives in Pocket Pet's encrypted connections file.

import Cocoa
import CryptoKit
import IOKit
import Security

struct CalEvent {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    var location: String? = nil
}

/// Your connections (sign-in tokens, the calendar link), kept in a file only your account can read and encrypted with a
/// key unique to this Mac, so a copy of the file is useless anywhere else. Unlike the Keychain, the file doesn't mind that
/// an update is a new build: connections survive updates without asking. Read once in the background at launch.
enum Secrets {
    private static let q = DispatchQueue(label: "pocketpet.secrets")
    private static var cache: [String: String] = [:]
    static var fileOverride: URL?            // for the self-test

    private static var file: URL {
        fileOverride ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Pocket Pet/connections.dat")
    }

    /// Call off the main thread (moving old Keychain items over can wait on macOS's prompt), then `get` on the main thread.
    static func load() {
        var all = readFile()
        if all == nil {
            // first run with the file: bring over what earlier versions kept in the Keychain (macOS may ask one last time)
            all = Legacy.readAll()
            if !(all ?? [:]).isEmpty { writeFile(all ?? [:]); Legacy.deleteAll() }
        }
        let found = all ?? [:]
        if Thread.isMainThread { cache = found } else { DispatchQueue.main.sync { cache = found } }
    }

    static func get(_ key: String) -> String? { cache[key] }

    /// Waits for pending writes (the self-test).
    static func flush() { q.sync {} }

    static func set(_ value: String?, _ key: String) {
        cache[key] = value
        let snapshot = cache
        q.async { writeFile(snapshot) }
    }

    private static var key: SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data("pocket-pet|\(platformUUID() ?? NSUserName())".utf8)))
    }

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }

    private static func readFile() -> [String: String]? {
        guard let data = try? Data(contentsOf: file), let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return (try? JSONSerialization.jsonObject(with: plain)) as? [String: String]
    }

    private static func writeFile(_ all: [String: String]) {
        let fm = FileManager.default
        let dir = file.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let plain = try? JSONSerialization.data(withJSONObject: all),
              let sealed = try? AES.GCM.seal(plain, using: key).combined else { return }
        try? sealed.write(to: file, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// Where earlier versions kept connections: one Keychain item (or, before that, one per secret).
    private enum Legacy {
        static let service = "local.honk.google"
        static let keys = ["secrets", "clientSecret", "refreshToken", "icsURL", "spotifyRefresh"]

        static func readAll() -> [String: String] {
            var all: [String: String] = [:]
            if let blob = read("secrets"), let j = (try? JSONSerialization.jsonObject(with: Data(blob.utf8))) as? [String: String] { all = j }
            for k in keys.dropFirst() where all[k] == nil { if let v = read(k) { all[k] = v } }
            return all
        }

        static func deleteAll() {
            for k in keys {
                SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                               kSecAttrAccount as String: k] as CFDictionary)
            }
        }

        private static func read(_ key: String) -> String? {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecReturnData as String: true]
            var out: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
            return String(data: d, encoding: .utf8)
        }
    }
}

final class Google {
    private(set) var clientID = ""
    private var clientSecret = ""
    private(set) var email = ""
    private var refreshToken: String?
    private var accessToken: String?
    private var expiry = Date.distantPast
    private var signingIn = false
    var events: [CalEvent] = []
    var lastFetch = Date.distantPast
    var status = ""

    var hasClient: Bool { !clientID.isEmpty && !clientSecret.isEmpty }
    var signedIn: Bool { refreshToken != nil }

    static let scopes = "openid email https://www.googleapis.com/auth/calendar.readonly"

    init() {
        let d = UserDefaults.standard
        clientID = d.string(forKey: "googleClientID") ?? ""
        email = d.string(forKey: "googleEmail") ?? ""
    }

    /// After `Secrets.load()`.
    func loadSecrets() {
        clientSecret = Secrets.get("clientSecret") ?? ""
        refreshToken = Secrets.get("refreshToken")
    }

    /// Reads the client JSON you download from Google Cloud ("Desktop app" OAuth client).
    func importClientFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = (json["installed"] ?? json["web"]) as? [String: Any],
              let id = inner["client_id"] as? String, let secret = inner["client_secret"] as? String else {
            status = "That file doesn't look like a Google OAuth client"
            return false
        }
        clientID = id
        clientSecret = secret
        UserDefaults.standard.set(id, forKey: "googleClientID")
        Secrets.set(secret, "clientSecret")
        status = "Client added. Now sign in!"
        return true
    }

    func signOut() {
        refreshToken = nil
        accessToken = nil
        email = ""
        events = []
        Secrets.set(nil, "refreshToken")
        UserDefaults.standard.removeObject(forKey: "googleEmail")
        status = ""
    }

    func forgetClient() {
        signOut()
        clientID = ""; clientSecret = ""
        UserDefaults.standard.removeObject(forKey: "googleClientID")
        Secrets.set(nil, "clientSecret")
    }

    // MARK: Sign in

    func signIn(_ done: @escaping (Bool) -> Void) {
        guard hasClient, !signingIn else { done(false); return }
        guard let server = LoopbackServer() else { status = "Couldn't start sign-in"; done(false); return }
        signingIn = true
        status = "Finish signing in in your browser…"
        let verifier = Self.randomString(64)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomString(24)
        let redirect = "http://127.0.0.1:\(server.port)"
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        server.waitForCode(timeout: 300) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let (code, st)) where st == state:
                    self.exchange(code: code, verifier: verifier, redirect: redirect) { ok in
                        self.signingIn = false
                        self.status = ok ? "" : "Sign-in didn't work, try again"
                        if ok { self.refreshEvents(nil) }
                        done(ok)
                    }
                default:
                    self.signingIn = false
                    self.status = "Sign-in was cancelled"
                    done(false)
                }
            }
        }
        NSWorkspace.shared.open(c.url!)
    }

    private func exchange(code: String, verifier: String, redirect: String, _ done: @escaping (Bool) -> Void) {
        post(["code": code, "client_id": clientID, "client_secret": clientSecret, "redirect_uri": redirect,
              "grant_type": "authorization_code", "code_verifier": verifier]) { [weak self] json in
            guard let self, let json, let access = json["access_token"] as? String else { done(false); return }
            self.accessToken = access
            self.expiry = Date().addingTimeInterval((json["expires_in"] as? Double ?? 3600) - 60)
            if let r = json["refresh_token"] as? String {
                self.refreshToken = r
                Secrets.set(r, "refreshToken")
            }
            if let idt = json["id_token"] as? String, let mail = Self.email(fromIDToken: idt) {
                self.email = mail
                UserDefaults.standard.set(mail, forKey: "googleEmail")
            }
            done(self.refreshToken != nil)
        }
    }

    /// Hands back a fresh access token (on the main thread), refreshing it when needed.
    func token(_ done: @escaping (String?) -> Void) {
        guard let rt = refreshToken, hasClient else { done(nil); return }
        if let a = accessToken, Date() < expiry { done(a); return }
        post(["refresh_token": rt, "client_id": clientID, "client_secret": clientSecret, "grant_type": "refresh_token"]) { [weak self] json in
            guard let self else { return }
            if let json, let access = json["access_token"] as? String {
                self.accessToken = access
                self.expiry = Date().addingTimeInterval((json["expires_in"] as? Double ?? 3600) - 60)
                done(access)
            } else {
                switch json?["error"] as? String {
                case "invalid_grant":       // expired or revoked; Google expires sign-ins weekly for apps left in testing
                    self.signOut(); self.status = "Google ended this sign-in. Sign in again, or paste a calendar link (it never expires)."
                case "invalid_client":      // the Google Cloud client's secret was reset or the client deleted
                    self.status = "Google no longer accepts your Cloud client. Choose its file again, or paste a calendar link instead."
                default: break
                }
                done(nil)
            }
        }
    }

    /// What Google says when refreshing the sign-in (only its error code and message, never a token): `--agenda`.
    func diagnose(_ done: @escaping (String) -> Void) {
        guard let rt = refreshToken else { done("no refresh token"); return }
        post(["refresh_token": rt, "client_id": clientID, "client_secret": clientSecret, "grant_type": "refresh_token"]) { json in
            guard let json else { done("no answer from Google"); return }
            if json["access_token"] != nil { done("ok"); return }
            done("\(json["error"] ?? "?"): \(json["error_description"] ?? "")")
        }
    }

    private func post(_ form: [String: String], _ done: @escaping ([String: Any]?) -> Void) {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { done(json) }
        }.resume()
    }

    // MARK: Calendar

    func refreshEvents(_ done: (() -> Void)?) {
        token { [weak self] token in
            guard let self, let token else { done?(); return }
            DispatchQueue.global(qos: .utility).async {
                let evs = Self.fetchEvents(token: token)
                DispatchQueue.main.async {
                    if let evs {
                        self.events = evs
                        self.lastFetch = Date()
                        self.status = ""
                    } else {
                        self.status = "Couldn't read your calendar (is the Calendar API enabled?)"
                    }
                    done?()
                }
            }
        }
    }

    private static func fetchEvents(token: String) -> [CalEvent]? {
        guard let list = getJSON("https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader", token: token),
              let cals = list["items"] as? [[String: Any]] else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let end = start.addingTimeInterval(2 * 86400)
        let iso = ISO8601DateFormatter()
        var out: [CalEvent] = []
        for cal in cals where (cal["selected"] as? Bool ?? false) || (cal["primary"] as? Bool ?? false) {
            guard let id = cal["id"] as? String,
                  let enc = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { continue }
            let url = "https://www.googleapis.com/calendar/v3/calendars/\(enc)/events?singleEvents=true&orderBy=startTime&maxResults=25"
                + "&timeMin=\(iso.string(from: start))&timeMax=\(iso.string(from: end))"
            guard let res = getJSON(url, token: token), let items = res["items"] as? [[String: Any]] else { continue }
            for e in items {
                if (e["status"] as? String) == "cancelled" { continue }
                if let att = e["attendees"] as? [[String: Any]],
                   att.contains(where: { ($0["self"] as? Bool ?? false) && ($0["responseStatus"] as? String) == "declined" }) { continue }
                guard let s = e["start"] as? [String: Any], let en = e["end"] as? [String: Any],
                      let (sd, allDay) = parseTime(s), let (ed, _) = parseTime(en) else { continue }
                out.append(CalEvent(id: e["id"] as? String ?? UUID().uuidString, title: e["summary"] as? String ?? "Event",
                                    start: sd, end: ed, allDay: allDay, location: e["location"] as? String))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    private static func parseTime(_ d: [String: Any]) -> (Date, Bool)? {
        if let s = d["dateTime"] as? String {
            let f = ISO8601DateFormatter()
            if let date = f.date(from: s) { return (date, false) }
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s).map { ($0, false) }
        }
        if let s = d["date"] as? String {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = .current
            return f.date(from: s).map { ($0, true) }
        }
        return nil
    }

    // MARK: Requests

    /// A synchronous GET (call off the main thread).
    private static func getJSON(_ url: String, token: String) -> [String: Any]? { getJSONStatus(url, token: token).0 }

    private static func getJSONStatus(_ url: String, token: String) -> ([String: Any]?, Int) {
        guard let u = URL(string: url) else { return (nil, 0) }
        var req = URLRequest(url: u)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any]?, status = 0
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200, let data {
                out = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return (out, status)
    }

    // MARK: Helpers

    static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var g = SystemRandomNumberGenerator()
        return String((0..<n).map { _ in chars.randomElement(using: &g)! })
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func email(fromIDToken t: String) -> String? {
        let parts = t.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var b = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b), let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return json["email"] as? String
    }
}

/// A one-shot web server on 127.0.0.1 that catches Google's redirect after you sign in.
final class LoopbackServer {
    private let fd: Int32
    let port: UInt16

    /// Port 0 picks any free port (Google); Spotify needs the exact port registered for the app.
    init?(port fixed: UInt16 = 0) {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = fixed.bigEndian
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(sock, 4) == 0 else { Darwin.close(sock); return nil }
        var got = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &got) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) }
        }
        fd = sock
        port = UInt16(bigEndian: got.sin_port)
    }

    func waitForCode(timeout: TimeInterval, _ done: @escaping (Result<(String, String), Error>) -> Void) {
        let fd = self.fd
        DispatchQueue.global(qos: .userInitiated).async {
            defer { Darwin.close(fd) }
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                guard poll(&pfd, 1, 1000) > 0 else { continue }
                let client = accept(fd, nil, nil)
                guard client >= 0 else { continue }
                var buf = [UInt8](repeating: 0, count: 8192)
                let n = recv(client, &buf, buf.count, 0)
                let request = n > 0 ? String(decoding: buf[0..<n], as: UTF8.self) : ""
                let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let items = URLComponents(string: "http://x" + path)?.queryItems ?? []
                let code = items.first { $0.name == "code" }?.value
                let state = items.first { $0.name == "state" }?.value ?? ""
                let failed = items.contains { $0.name == "error" }
                let body = code != nil
                    ? "<html><body style='font-family:-apple-system;text-align:center;padding-top:80px;background:#fff7ee;color:#4a3f55'><h1>You're signed in! 🐾</h1><p>You can close this tab and go back to your pet.</p></body></html>"
                    : "<html><body style='font-family:-apple-system;text-align:center;padding-top:80px'><h1>Sign-in didn't finish</h1></body></html>"
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                _ = resp.withCString { send(client, $0, strlen($0), 0) }
                Darwin.close(client)
                if let code { done(.success((code, state))); return }
                if failed { done(.failure(NSError(domain: "honk", code: 1))); return }
            }
            done(.failure(NSError(domain: "honk", code: 2)))
        }
    }
}
