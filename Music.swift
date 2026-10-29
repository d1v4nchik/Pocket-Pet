// Music in the menu and on the pet. Spotify and Apple Music give the song, artwork and full controls straight from the
// app (no setup); any other player (YouTube Music in a browser, Tidal, Deezer, VLC...) gets play/pause and skip through
// the keyboard's media keys, which needs Accessibility. Up next and adding songs are Spotify-only and need your Spotify
// account (Spotify's Web API, a free developer app, client ID only).

import Cocoa
import CryptoKit

struct Song: Identifiable, Equatable {
    let id: String          // spotify:track:…, or Apple Music's persistent id
    let name: String
    let artist: String
    var art: String?
    var duration = 0.0      // seconds
}

enum PlayerApp { case spotify, music, other }

/// The keyboard's play/pause and skip keys: they control whatever is playing (posting them needs Accessibility).
enum MediaKey {
    static let playPause: Int32 = 16, next: Int32 = 17, previous: Int32 = 18

    static func press(_ key: Int32) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                               context: nil, subtype: 8, data1: data1, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

final class MusicPlayer {
    static let spotifyID = "com.spotify.client", musicID = "com.apple.Music"
    static let port: UInt16 = 43117
    static let redirect = "http://127.0.0.1:43117/callback"
    static let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing"

    // MARK: What's playing

    private(set) var app: PlayerApp = .spotify
    private(set) var song: Song?
    private(set) var playing = false, shuffle = false, repeating = false
    private(set) var permission: OSStatus = noErr
    private var position = 0.0, positionAt = Date()
    private var asked = Set<String>(), pending = false
    private var artCache: [String: String] = [:]
    private let q = DispatchQueue(label: "pocketpet.music", qos: .userInitiated)
    var onChange: (() -> Void)?

    /// Set by World from what's actually making sound, for players that can't be asked directly.
    var otherName = "", otherPlaying = false

    var appName: String { app == .spotify ? "Spotify" : app == .music ? "Music" : (otherName.isEmpty ? "your player" : otherName) }
    /// Song info, shuffle and repeat (Spotify and Apple Music); other players only get the three buttons.
    var full: Bool { app != .other }
    var bid: String { app == .music ? Self.musicID : Self.spotifyID }

    var running: Bool { previewing || isRunning(Self.spotifyID) || isRunning(Self.musicID) || otherPlaying }
    /// Asked once: a Launch Services lookup is too slow for every redraw.
    lazy var spotifyInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyID) != nil

    /// Looked up at most once a second per app (the menu asks on every redraw).
    private func isRunning(_ id: String) -> Bool {
        if let c = runningCache[id], Date().timeIntervalSince(c.at) < 1 { return c.on }
        let on = !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
        runningCache[id] = (on, Date())
        return on
    }
    private var runningCache: [String: (on: Bool, at: Date)] = [:]
    private var previewing = false, previewConnected = false

    /// Sample data for the offscreen menu render (`PocketPet --panel out.png 2|20`).
    func preview(connected: Bool) {
        previewing = true; previewConnected = connected
        app = .spotify
        song = Song(id: "spotify:track:x", name: "Espresso", artist: "Sabrina Carpenter", duration: 175)
        playing = true; shuffle = true; position = 70; positionAt = Date()
        upNext = [Song(id: "a", name: "Birds of a Feather", artist: "Billie Eilish"), Song(id: "b", name: "Good Luck, Babe!", artist: "Chappell Roan"),
                  Song(id: "c", name: "Apple", artist: "Charli xcx")]
    }
    var elapsed: Double { min(song?.duration ?? 0, playing ? position + Date().timeIntervalSince(positionAt) : position) }

    private struct Reading {
        var app: PlayerApp, permission: OSStatus, song: Song?, playing: Bool, position: Double, shuffle: Bool, repeating: Bool
    }

    /// Asks Spotify and Apple Music (whichever are open) what's playing; the one that's playing wins.
    /// The first time per app, macOS asks you once whether Pocket Pet may control it.
    func refresh() {
        guard !previewing else { return }
        let s = isRunning(Self.spotifyID), m = isRunning(Self.musicID)
        guard s || m else {
            if song != nil || app != .other || playing != otherPlaying { song = nil; app = .other; playing = otherPlaying; changed() }
            return
        }
        guard !pending else { return }
        pending = true
        let askS = s && !asked.contains(Self.spotifyID), askM = m && !asked.contains(Self.musicID)
        if s { asked.insert(Self.spotifyID) }
        if m { asked.insert(Self.musicID) }
        q.async { [self] in
            let rs = s ? Self.read(.spotify, ask: askS) : nil
            let rm = m ? Self.read(.music, ask: askM) : nil
            let pick = [rs, rm].compactMap { $0 }.first { $0.playing } ?? rs ?? rm
            DispatchQueue.main.async {
                self.pending = false
                guard let r = pick else { return }
                if !r.playing && self.otherPlaying {          // something else is the one actually playing
                    self.app = .other; self.song = nil; self.playing = true; self.changed(); return
                }
                self.app = r.app
                self.permission = r.permission
                var song = r.song
                if let id = song?.id, song?.art == nil { song?.art = self.artCache[id] }
                self.song = song
                ArtCache.prefetch([song?.art])
                self.playing = r.playing
                self.position = r.position
                self.positionAt = Date()
                self.shuffle = r.shuffle
                self.repeating = r.repeating
                self.changed()
                if r.app == .music, let s = song, s.art == nil { self.findArtwork(s) }
            }
        }
    }

    private static func read(_ app: PlayerApp, ask: Bool) -> Reading {
        let bid = app == .music ? musicID : spotifyID
        var r = Reading(app: app, permission: AE.permission(bid, ask: ask), song: nil, playing: false, position: 0, shuffle: false, repeating: false)
        guard r.permission == noErr else { return r }
        let trk = AE.prop("pTrk")
        func get(_ c: String, track: Bool = true) -> NSAppleEventDescriptor? { AE.get(bid, AE.prop(c, of: track ? trk : .null())).0 }
        r.playing = get("pPlS", track: false)?.enumCodeValue == AE.code("kPSP")
        r.position = get("pPos", track: false)?.doubleValue ?? 0
        if app == .spotify {
            r.shuffle = get("pShu", track: false)?.booleanValue ?? false
            r.repeating = get("pRep", track: false)?.booleanValue ?? false
            let id = get("ID  ")?.stringValue ?? ""
            if !id.isEmpty {
                r.song = Song(id: id, name: get("pnam")?.stringValue ?? "", artist: get("pArt")?.stringValue ?? "",
                              art: get("aUrl")?.stringValue, duration: Double(get("pDur")?.int32Value ?? 0) / 1000)
            }
        } else {
            r.shuffle = get("pShE", track: false)?.booleanValue ?? false
            r.repeating = (get("pRpt", track: false)?.enumCodeValue).map { $0 != AE.code("kRpO") } ?? false
            let id = get("pPIS")?.stringValue ?? ""
            if !id.isEmpty {
                r.song = Song(id: id, name: get("pnam")?.stringValue ?? "", artist: get("pArt")?.stringValue ?? "",
                              duration: get("pDur")?.doubleValue ?? 0)
            }
        }
        return r
    }

    /// Apple Music doesn't hand out artwork links, so ask Apple's public song search for the cover.
    private func findArtwork(_ s: Song) {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: "\(s.artist) \(s.name)"), URLQueryItem(name: "entity", value: "song"),
                        URLQueryItem(name: "limit", value: "1")]
        guard let url = c.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard let art = ((json?["results"] as? [[String: Any]])?.first?["artworkUrl100"] as? String)?
                .replacingOccurrences(of: "100x100", with: "300x300") else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.artCache[s.id] = art
                if self.song?.id == s.id { self.song?.art = art; self.changed() }
            }
        }.resume()
    }

    func playPause() {
        playing.toggle()
        position = elapsed; positionAt = Date()
        changed()
        command("PlPs", MediaKey.playPause)
    }
    func next() { command("Next", MediaKey.next) }
    func previous() { command("Prev", MediaKey.previous) }

    func setShuffle(_ on: Bool) {
        guard full else { return }
        shuffle = on; changed()
        let bid = self.bid, music = app == .music
        q.async { AE.set(bid, AE.prop(music ? "pShE" : "pShu"), NSAppleEventDescriptor(boolean: on)) }
    }

    func setRepeat(_ on: Bool) {
        guard full else { return }
        repeating = on; changed()
        let bid = self.bid, music = app == .music
        q.async {
            AE.set(bid, AE.prop(music ? "pRpt" : "pRep"),
                   music ? NSAppleEventDescriptor(enumCode: AE.code(on ? "kAll" : "kRpO")) : NSAppleEventDescriptor(boolean: on))
        }
    }

    /// Plays just this song, now. Through your Spotify account that's the song on its own (Spotify's "play track"
    /// would carry on through its whole album); a song from your Apple Music library plays from your library.
    func play(_ s: Song) {
        if s.id.hasPrefix("music:") {
            let id = String(s.id.dropFirst(6)).filter { $0.isHexDigit }        // persistent ids are hex, nothing else gets in
            q.async { Self.runScript("tell application id \"\(Self.musicID)\" to play (some track of library playlist 1 whose persistent ID is \"\(id)\")") }
        } else if connected {
            api("PUT", "/v1/me/player/play", body: ["uris": [s.id]]) { [weak self] _, code in
                guard let self else { return }
                if code != 200 && code != 204 { self.playTrack(s) }         // no Premium: Spotify's own way
                self.later(0.6) { self.refresh(); self.refreshUpNext() }
            }
            return
        } else {
            playTrack(s)
        }
        later(0.6) { self.refresh(); self.refreshUpNext() }
    }

    private func playTrack(_ s: Song) {
        q.async { AE.send(Self.spotifyID, "spfy", "PCtx", direct: NSAppleEventDescriptor(string: s.id)) }
    }

    /// Jumps ahead to a song in Up next, keeping the rest of the queue (skips there, like pressing next a few times).
    func skip(to index: Int) {
        guard index >= 0, index < upNext.count else { return }
        let target = upNext[index]
        upNext.removeFirst(index + 1)
        song = target; playing = true; position = 0; positionAt = Date()
        changed()
        q.async {
            for _ in 0...index { AE.send(Self.spotifyID, "spfy", "Next"); usleep(120_000) }
        }
        later(0.8) { self.refresh(); self.refreshUpNext() }
    }

    /// The music card's search: your Spotify account if it's connected, otherwise your Apple Music library.
    func quickSearch(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { clearResults(); return }
        if connected { search(t); return }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.musicID) != nil else {
            status = "Connect Spotify in the Music tab to search"; changed(); return
        }
        q.async {
            let found = Self.searchMusic(t)
            DispatchQueue.main.async {
                self.results = found
                self.status = found.isEmpty ? "Nothing found in your Music library" : ""
                self.changed()
            }
        }
    }

    func clearResults() { results = []; status = ""; changed() }

    private static func searchMusic(_ text: String) -> [Song] {
        let q = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let out = runScript("""
            tell application id "\(musicID)"
                set out to ""
                set found to search library playlist 1 for "\(q)"
                repeat with i from 1 to (count of found)
                    if i > 8 then exit repeat
                    set t to item i of found
                    set out to out & (persistent ID of t) & (character id 31) & (name of t) & (character id 31) & (artist of t) & (character id 30)
                end repeat
                return out
            end tell
            """) ?? ""
        return out.components(separatedBy: "\u{1E}").compactMap { row in
            let f = row.components(separatedBy: "\u{1F}")
            return f.count == 3 ? Song(id: "music:" + f[0], name: f[1], artist: f[2]) : nil
        }
    }

    @discardableResult
    private static func runScript(_ src: String) -> String? {
        var err: NSDictionary?
        let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
        return err == nil ? r?.stringValue : nil
    }

    private func command(_ id: String, _ key: Int32) {
        switch app {
        case .spotify: q.async { AE.send(Self.spotifyID, "spfy", id) }
        case .music: q.async { AE.send(Self.musicID, "hook", id) }
        case .other: MediaKey.press(key)
        }
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

    /// After `Secrets.load()`.
    func loadSecrets() { refreshToken = Secrets.get("spotifyRefresh") }

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
        Secrets.set(nil, "spotifyRefresh")
        changed()
    }

    func refreshUpNext() {
        guard connected else { return }
        api("GET", "/v1/me/player/queue") { [weak self] json, _ in
            guard let self, let json else { return }
            self.upNext = (json["queue"] as? [[String: Any]] ?? []).prefix(20).compactMap(Self.song)
            ArtCache.prefetch(self.upNext.map(\.art))
            self.changed()
        }
    }

    func search(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard connected, !t.isEmpty else { results = []; changed(); return }
        api("GET", "/v1/search", ["q": t, "type": "track", "limit": "6"]) { [weak self] json, _ in
            guard let self else { return }
            self.results = ((json?["tracks"] as? [String: Any])?["items"] as? [[String: Any]] ?? []).compactMap(Self.song)
            ArtCache.prefetch(self.results.map(\.art))
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
                    Secrets.set(rt, "spotifyRefresh")
                }
                done(true)
            }
        }.resume()
    }

    private func api(_ method: String, _ path: String, _ query: [String: String] = [:], body: [String: Any]? = nil,
                     _ done: @escaping ([String: Any]?, Int) -> Void) {
        token { token in
            guard let token else { done(nil, 401); return }
            var c = URLComponents(string: "https://api.spotify.com" + path)!
            if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
            var req = URLRequest(url: c.url!)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }
            req.timeoutInterval = 8
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                DispatchQueue.main.async { done(json, code) }
            }.resume()
        }
    }
}
