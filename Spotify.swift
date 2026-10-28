// Spotify in the menu. What's playing and the controls come straight from the Spotify app (no setup).
// Up next and adding songs need your Spotify account, through Spotify's Web API (a free developer app, client ID only).

import Cocoa
import CryptoKit

struct Song: Identifiable, Equatable {
    let id: String          // spotify:track:…
    let name: String
    let artist: String
    var art: String?
    var duration = 0.0      // seconds
}

final class Spotify {
    static let bid = "com.spotify.client"
    static let port: UInt16 = 43117
    static let redirect = "http://127.0.0.1:43117/callback"
    static let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing"

    // MARK: From the app

    private(set) var song: Song?
    private(set) var playing = false, shuffle = false, repeating = false
    private(set) var permission: OSStatus = noErr
    private var position = 0.0, positionAt = Date()
    private var asked = false, pending = false
    private let q = DispatchQueue(label: "honk.spotify", qos: .userInitiated)
    var onChange: (() -> Void)?

    /// Is Spotify open? Looked up at most once a second (the menu asks on every redraw).
    var running: Bool {
        if previewing { return true }
        if Date().timeIntervalSince(runningAt) > 1 {
            runningCache = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bid).isEmpty
            runningAt = Date()
        }
        return runningCache
    }
    private var runningCache = false, runningAt = Date.distantPast
    private var previewing = false, previewConnected = false

    /// Sample data for the offscreen menu render (`PocketPet --panel out.png 2|20`).
    func preview(connected: Bool) {
        previewing = true; previewConnected = connected
        song = Song(id: "spotify:track:x", name: "Espresso", artist: "Sabrina Carpenter", duration: 175)
        playing = true; shuffle = true; position = 70; positionAt = Date()
        upNext = [Song(id: "a", name: "Birds of a Feather", artist: "Billie Eilish"), Song(id: "b", name: "Good Luck, Babe!", artist: "Chappell Roan"),
                  Song(id: "c", name: "Apple", artist: "Charli xcx")]
    }
    var elapsed: Double { min(song?.duration ?? 0, playing ? position + Date().timeIntervalSince(positionAt) : position) }

    /// Reads the player (track, state, position, shuffle, repeat). The first call asks macOS for permission.
    func refresh() {
        guard running else {
            if song != nil { song = nil; playing = false; changed() }
            return
        }
        guard !pending else { return }
        pending = true
        let ask = !asked
        asked = true
        q.async { [self] in
            let perm = AE.permission(Self.bid, ask: ask)
            guard perm == noErr else {
                DispatchQueue.main.async { self.pending = false; self.permission = perm; self.changed() }
                return
            }
            let bid = Self.bid, trk = AE.prop("pTrk")
            func get(_ c: String, track: Bool = true) -> NSAppleEventDescriptor? { AE.get(bid, AE.prop(c, of: track ? trk : .null())).0 }
            let state = get("pPlS", track: false)?.enumCodeValue
            let pos = get("pPos", track: false)?.doubleValue ?? 0
            let shu = get("pShu", track: false)?.booleanValue ?? false
            let rep = get("pRep", track: false)?.booleanValue ?? false
            let id = get("ID  ")?.stringValue ?? ""
            let s = id.isEmpty ? nil : Song(id: id, name: get("pnam")?.stringValue ?? "", artist: get("pArt")?.stringValue ?? "",
                                           art: get("aUrl")?.stringValue, duration: Double(get("pDur")?.int32Value ?? 0) / 1000)
            DispatchQueue.main.async {
                self.pending = false
                self.permission = noErr
                self.song = s
                self.playing = state == AE.code("kPSP")
                self.position = pos
                self.positionAt = Date()
                self.shuffle = shu
                self.repeating = rep
                self.changed()
            }
        }
    }

    func playPause() {
        playing.toggle()
        position = elapsed; positionAt = Date()
        changed()
        command("PlPs")
    }
    func next() { command("Next") }
    func previous() { command("Prev") }

    func setShuffle(_ on: Bool) {
        shuffle = on; changed()
        q.async { AE.set(Self.bid, AE.prop("pShu"), NSAppleEventDescriptor(boolean: on)) }
    }

    func setRepeat(_ on: Bool) {
        repeating = on; changed()
        q.async { AE.set(Self.bid, AE.prop("pRep"), NSAppleEventDescriptor(boolean: on)) }
    }

    /// Plays a song right away (Spotify's own "play track").
    func play(_ s: Song) {
        q.async { AE.send(Self.bid, "spfy", "PCtx", direct: NSAppleEventDescriptor(string: s.id)) }
        later(0.6) { self.refresh(); self.refreshUpNext() }
    }

    private func command(_ id: String) {
        q.async { AE.send(Self.bid, "spfy", id) }
        later(0.4) { self.refresh(); self.refreshUpNext() }
    }

    private func later(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }
    private func changed() { onChange?() }

    // MARK: Your account (Web API): up next, search, add to queue

    private(set) var clientID = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""
    private var refreshToken: String?
    private var accessToken: String?, expiry = Date.distantPast
    private(set) var upNext: [Song] = []
    private(set) var results: [Song] = []
    private(set) var signingIn = false
    var status = ""

    var connected: Bool { previewConnected || (refreshToken != nil && !clientID.isEmpty) }

    /// After `Keychain.load()`.
    func loadSecrets() { refreshToken = Keychain.get("spotifyRefresh") }

    func connect(clientID raw: String, _ done: @escaping (Bool) -> Void) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.count >= 20, id.allSatisfy({ $0.isHexDigit }) else {
            status = "That doesn't look like a Client ID (32 letters and numbers)"
            done(false)
            return
        }
        guard !signingIn else { return }
        guard let server = LoopbackServer(port: Self.port) else { status = "Couldn't start sign-in, try again"; done(false); return }
        signingIn = true
        status = "Finish in your browser…"
        let verifier = Google.randomString(64)
        let challenge = Google.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Google.randomString(24)
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirect),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        server.waitForCode(timeout: 300) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success(let (code, st)) = result, st == state else {
                    self.signingIn = false
                    self.status = "Didn't connect. Check the Redirect URI in your Spotify app matches exactly."
                    done(false)
                    return
                }
                self.tokenRequest(["grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirect,
                                   "client_id": id, "code_verifier": verifier]) { ok in
                    self.signingIn = false
                    if ok {
                        self.clientID = id
                        UserDefaults.standard.set(id, forKey: "spotifyClientID")
                        self.status = ""
                        self.refreshUpNext()
                    } else {
                        self.status = "Spotify didn't accept the sign-in, try again"
                    }
                    done(ok)
                }
            }
        }
        NSWorkspace.shared.open(c.url!)
    }

    func disconnect() {
        refreshToken = nil; accessToken = nil
        upNext = []; results = []
        Keychain.set(nil, "spotifyRefresh")
        changed()
    }

    func refreshUpNext() {
        guard connected else { return }
        api("GET", "/v1/me/player/queue") { [weak self] json, _ in
            guard let self, let json else { return }
            self.upNext = (json["queue"] as? [[String: Any]] ?? []).prefix(8).compactMap(Self.song)
            self.changed()
        }
    }

    func search(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard connected, !t.isEmpty else { results = []; changed(); return }
        api("GET", "/v1/search", ["q": t, "type": "track", "limit": "6"]) { [weak self] json, _ in
            guard let self else { return }
            self.results = ((json?["tracks"] as? [String: Any])?["items"] as? [[String: Any]] ?? []).compactMap(Self.song)
            self.changed()
        }
    }

    func addToQueue(_ s: Song) {
        api("POST", "/v1/me/player/queue", ["uri": s.id]) { [weak self] _, code in
            guard let self else { return }
            switch code {
            case 200, 204: self.status = "Added “\(s.name)”"
            case 403: self.status = "Adding to the queue needs Spotify Premium"
            case 404: self.status = "Start playing something in Spotify first"
            default: self.status = "Couldn't add it (error \(code))"
            }
            self.changed()
            self.later(0.6) { self.refreshUpNext() }
            self.later(4) { if self.status.hasPrefix("Added") { self.status = ""; self.changed() } }
        }
    }

    private static func song(_ d: [String: Any]) -> Song? {
        guard let uri = d["uri"] as? String, let name = d["name"] as? String else { return nil }
        let artists = (d["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let show = (d["show"] as? [String: Any])?["name"] as? String
        let images = ((d["album"] as? [String: Any])?["images"] ?? d["images"]) as? [[String: Any]] ?? []
        return Song(id: uri, name: name, artist: artists.isEmpty ? (show ?? "") : artists.joined(separator: ", "),
                    art: images.last?["url"] as? String, duration: Double(d["duration_ms"] as? Int ?? 0) / 1000)
    }

    private func token(_ done: @escaping (String?) -> Void) {
        if let a = accessToken, Date() < expiry { done(a); return }
        guard let rt = refreshToken, !clientID.isEmpty else { done(nil); return }
        tokenRequest(["grant_type": "refresh_token", "refresh_token": rt, "client_id": clientID]) { [weak self] ok in
            done(ok ? self?.accessToken : nil)
        }
    }

    private func tokenRequest(_ form: [String: String], _ done: @escaping (Bool) -> Void) {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard let self, let json, let access = json["access_token"] as? String else { done(false); return }
                self.accessToken = access
                self.expiry = Date().addingTimeInterval(Double(json["expires_in"] as? Int ?? 3600) - 60)
                if let rt = json["refresh_token"] as? String {      // Spotify may hand out a new one
                    self.refreshToken = rt
                    Keychain.set(rt, "spotifyRefresh")
                }
                done(true)
            }
        }.resume()
    }

    private func api(_ method: String, _ path: String, _ query: [String: String] = [:], _ done: @escaping ([String: Any]?, Int) -> Void) {
        token { token in
            guard let token else { done(nil, 401); return }
            var c = URLComponents(string: "https://api.spotify.com" + path)!
            if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
            var req = URLRequest(url: c.url!)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 8
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                DispatchQueue.main.async { done(json, code) }
            }.resume()
        }
    }
}
