// The notification bell. When something new arrives the pet rings a bell; click it to go straight there.
//
// Two ways to notice, because macOS doesn't let one app see another's notifications directly:
// - Browser tabs: web apps put an unread count in their title ("(2) Discord"), read every few seconds
//   through the browser's scripting (Safari and every Chrome-based browser: Chrome, Brave, Edge, Arc, Dia, Comet, Vivaldi,
//   Opera...). Clicking opens that tab.
//   Firefox can't be scripted, so it's covered by the banners below.
// - Notification banners from any app, through Accessibility (only if you allow it). Clicking the bell
//   clicks the banner for you, or opens the app if the banner is gone.
// Only who sent it and where are kept, never the message itself.

import Cocoa

struct Notice {
    var title: String            // "Discord", "Messages"
    var detail: String           // "2 new in Vivaldi", "discord.com"
    var browser: String?         // bundle id, for tab notices
    var tabID: String?
    var appBundle: String?       // for banner notices
    var site: String?
    var banner: AXUIElement?
}

// MARK: - Browser tabs

final class TabWatcher {
    var onNotice: ((Notice) -> Void)?
    /// Counts dropped back to zero (read in the browser): the bell for that tab can go.
    var onRead: ((String) -> Void)?
    private let q = DispatchQueue(label: "pocketpet.tabs", qos: .utility)
    private var counts: [String: Int] = [:]      // "bundle|tab id" -> unread count
    private var primed = Set<String>()           // browsers scanned once (the first look only sets the baseline)
    private var busy = false
    private var asked = Set<String>()            // browsers macOS has been asked about this launch
    private var sites: [String: (at: Date, hosts: [String])] = [:]   // each browser's open sites, from the last look
    private var ringing = true

    /// `ring: false` just looks (for the music check): no bell, and no permission question.
    func poll(ring: Bool = true) {
        guard !busy else { return }
        let browsers = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }.filter { DocBrowsers.all.contains($0) }
        guard !browsers.isEmpty else { return }
        busy = true
        ringing = ring
        let ask = ring ? browsers.filter { !asked.contains($0) } : []
        if ring { asked.formUnion(browsers) }
        q.async { [self] in
            var found: [(bid: String, name: String, tabs: [(id: String, title: String, url: String)])] = []
            // the first time per browser, macOS asks you once whether Pocket Pet may look at its tabs
            for bid in browsers where AE.permission(bid, ask: ask.contains(bid)) == noErr {
                let name = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first?.localizedName ?? "your browser"
                found.append((bid, name, Self.tabs(bid)))
            }
            DispatchQueue.main.async {
                self.busy = false
                for b in found { self.update(b.bid, b.name, b.tabs) }
            }
        }
    }

    /// Music sites, for telling a song from the other sounds browsers make (calls, Discord's pings, ads).
    static let musicSites = [("music.youtube.com", "YouTube Music"), ("open.spotify.com", "Spotify Web Player"),
                             ("soundcloud.com", "SoundCloud"), ("music.apple.com", "Apple Music"), ("deezer.com", "Deezer"),
                             ("tidal.com", "Tidal"), ("bandcamp.com", "Bandcamp"), ("pandora.com", "Pandora"),
                             ("music.amazon.", "Amazon Music"), ("radio.garden", "Radio Garden"), ("lofi", "Lofi")]

    /// The music site open in that browser, if any (nil also when its tabs haven't been looked at lately).
    func musicSite(in bid: String) -> String? {
        guard let s = sites[bid], Date().timeIntervalSince(s.at) < 30 else { return nil }
        return Self.musicSites.first { m in s.hosts.contains { $0.contains(m.0) } }?.1
    }
    func sitesStale(_ bid: String) -> Bool { Date().timeIntervalSince(sites[bid]?.at ?? .distantPast) > 12 }

    private func update(_ bid: String, _ name: String, _ tabs: [(id: String, title: String, url: String)]) {
        sites[bid] = (Date(), tabs.compactMap { URL(string: $0.url)?.host?.lowercased() })
        let first = !primed.contains(bid)
        primed.insert(bid)
        var seen = Set<String>()
        for t in tabs {
            let key = bid + "|" + t.id
            seen.insert(key)
            let n = Self.unread(t.title)
            let before = counts[key]
            counts[key] = n
            if n == 0, (before ?? 0) > 0 { onRead?(t.id) }
            guard ringing, !first, n > (before ?? 0) else { continue }
            let site = URL(string: t.url)?.host?.replacingOccurrences(of: "www.", with: "")
            onNotice?(Notice(title: Self.appName(t.title, site: site), detail: "\(n) new in \(name)",
                             browser: bid, tabID: t.id, site: site))
        }
        counts = counts.filter { !$0.key.hasPrefix(bid + "|") || seen.contains($0.key) }
    }

    /// "(3) Discord | #general" -> 3, "Inbox (12) - Gmail" -> 12.
    static func unread(_ title: String) -> Int {
        guard let r = title.range(of: #"\((\d{1,4})\+?\)"#, options: .regularExpression) else { return 0 }
        return Int(title[r].filter(\.isNumber)) ?? 0
    }

    /// A short name for the tab: the title without the count, up to the first separator.
    static func appName(_ title: String, site: String?) -> String {
        var t = title.replacingOccurrences(of: #"\(\d{1,4}\+?\)"#, with: "", options: .regularExpression)
        for sep in [" | ", " - ", " — ", " · "] { if let r = t.range(of: sep) { t = String(t[..<r.lowerBound]) } }
        t = t.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.count > 24 { return site ?? "New message" }
        return t
    }

    private static let sep = "\u{1F}", end = "\u{1E}"

    /// Safari tabs have no id, so their address stands in for one.
    private static func tabs(_ bid: String) -> [(id: String, title: String, url: String)] {
        let safari = DocBrowsers.safari.contains(bid)
        let src = """
            tell application id "\(bid)"
                set out to ""
                repeat with w in windows
                    try
                        set ids to \(safari ? "URL" : "id") of every tab of w
                        set ts to \(safari ? "name" : "title") of every tab of w
                        set us to URL of every tab of w
                        repeat with i from 1 to count of ids
                            set out to out & (item i of ids) & (character id 31) & (item i of ts) & (character id 31) & (item i of us) & (character id 30)
                        end repeat
                    end try
                end repeat
                return out
            end tell
            """
        guard let s = run(src, keep: true) else { return [] }
        return s.components(separatedBy: end).compactMap { row in
            let f = row.components(separatedBy: sep)
            return f.count == 3 ? (f[0], f[1], f[2]) : nil
        }
    }

    /// Brings the browser forward on that tab.
    func open(_ bid: String, tabID: String) {
        let safari = DocBrowsers.safari.contains(bid)
        reveal(bid, list: safari ? "URL" : "id", test: "((item i of xs) as text) is \"\(Self.esc(tabID))\"", safari: safari)
    }

    /// Brings the browser forward on the first tab of a site (for banners that came from a website).
    func open(_ bid: String, site: String) {
        reveal(bid, list: "URL", test: "(item i of xs) contains \"\(Self.esc(site))\"", safari: DocBrowsers.safari.contains(bid))
    }

    private func reveal(_ bid: String, list: String, test: String, safari: Bool) {
        let select = safari ? "set current tab of w to tab i of w" : "set active tab index of w to i"
        q.async {
            _ = Self.run("""
                tell application id "\(bid)"
                    repeat with w in windows
                        try
                            set xs to \(list) of every tab of w
                            repeat with i from 1 to count of xs
                                if \(test) then
                                    \(select)
                                    set index of w to 1
                                    activate
                                    return "ok"
                                end if
                            end repeat
                        end try
                    end repeat
                    activate
                end tell
                """)
        }
    }

    /// Text from web pages goes into a script: escape it so it can only ever be text.
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Compiled scripts kept for the regular tab check: macOS scans every newly compiled script, which isn't free.
    /// Only touched on the watcher's own queue.
    private static var compiled: [String: NSAppleScript] = [:]

    private static func run(_ src: String, keep: Bool = false) -> String? {
        var err: NSDictionary?
        let script: NSAppleScript?
        if keep, let s = compiled[src] { script = s }
        else {
            script = NSAppleScript(source: src)
            if keep, let s = script, s.compileAndReturnError(&err) { compiled[src] = s }
        }
        let r = script?.executeAndReturnError(&err)
        return err == nil ? r?.stringValue : nil
    }
}

enum DocBrowsers {
    /// Browsers built on Chrome all share Chrome's scripting. Firefox and Zen have none: their notifications come in as banners.
    static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
        "com.vivaldi.Vivaldi", "com.vivaldi.Vivaldi.snapshot", "com.operasoftware.Opera", "com.operasoftware.OperaGX",
        "company.thebrowser.Browser", "company.thebrowser.dia", "ai.perplexity.comet", "ru.yandex.desktop.yandex-browser",
        "com.pushplaylabs.sidekick", "org.chromium.Thorium"]
    static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static var all: Set<String> { chromium.union(safari) }
}

// MARK: - Banners (Accessibility)

final class BannerWatcher {
    var onNotice: ((Notice) -> Void)?
    var log: ((String) -> Void)?             // `PocketPet --bellprobe out.txt` shows what it sees
    private var observer: AXObserver?
    private var pid: pid_t = 0
    private var seen: [String: Date] = [:]
    private var pending = false

    var running: Bool { observer != nil }
    static let centerID = "com.apple.notificationcenterui"

    /// Starts (or restarts, if Notification Center was relaunched) once Accessibility is allowed.
    func start() {
        guard AXIsProcessTrusted(), let nc = NSRunningApplication.runningApplications(withBundleIdentifier: Self.centerID).first else { return }
        if observer != nil && nc.processIdentifier == pid { return }
        stop()
        pid = nc.processIdentifier
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<BannerWatcher>.fromOpaque(refcon).takeUnretainedValue().changed()
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let app = AXUIElementCreateApplication(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(obs, app, n as CFString, me)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        for b in banners() { seen[b.text] = Date() }       // whatever is already showing doesn't ring
        // Some macOS versions reuse one window for every banner and send no Accessibility events, so the window
        // server is asked too: a cheap list of Notification Center's on-screen windows, scanned only when it changes.
        poll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.checkWindows() }
        poll?.tolerance = 0.5
    }

    func stop() {
        if let o = observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode) }
        observer = nil
        poll?.invalidate(); poll = nil
    }

    private var poll: Timer?
    private var lastWindows = ""

    private func checkWindows() {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }
        let shape = mine.map { w -> String in
            let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return "\(w[kCGWindowNumber as String] ?? 0):\(Int(b["Height"] ?? 0))"
        }.joined(separator: ",")
        if shape != lastWindows { log?("windows: \(shape)"); lastWindows = shape; if !mine.isEmpty { changed() } }
    }

    private func changed() {
        log?("changed")
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.pending = false
            let now = Date()
            self.seen = self.seen.filter { now.timeIntervalSince($0.value) < 180 }
            let found = self.banners()
            self.log?("scan: \(found.map(\.text))")
            for b in found where self.seen[b.text] == nil {
                self.seen[b.text] = now
                self.onNotice?(self.notice(b.text, b.element))
            }
        }
    }

    /// Who sent it. macOS labels a banner "App, Title, Message", so the app is the first part (matched to a running app
    /// when there is one, to open it later); a website mentioned in a browser's banner wins as the name.
    private func notice(_ text: String, _ el: AXUIElement) -> Notice {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.localizedName != nil }
        let sender = text.components(separatedBy: ", ").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let app = apps.first { $0.localizedName!.caseInsensitiveCompare(sender) == .orderedSame }
            ?? apps.filter { text.localizedCaseInsensitiveContains($0.localizedName!) }.max { $0.localizedName!.count < $1.localizedName!.count }
        var site: String?
        if let r = text.range(of: #"[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|org|net|io|app|gg|co|me|tv|ai|dev|cy|uk|edu)\b"#, options: [.regularExpression, .caseInsensitive]) {
            site = String(text[r]).lowercased()
        }
        let fallback = !sender.isEmpty && sender.count <= 24 ? sender : "Notification"
        let name = site.flatMap { s in s.split(separator: ".").dropLast().last.map { $0.prefix(1).uppercased() + $0.dropFirst() } } ?? app?.localizedName ?? fallback
        return Notice(title: name, detail: site != nil ? "via \(app?.localizedName ?? "your browser")" : "New notification",
                      appBundle: app?.bundleIdentifier, site: site, banner: el)
    }

    /// Banner-shaped things on screen: pressable, banner-sized, with some text.
    private func banners() -> [(text: String, element: AXUIElement)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var out: [(String, AXUIElement)] = []
        var visited = 0
        func walk(_ e: AXUIElement, _ depth: Int) {
            guard depth < 14, visited < 500 else { return }
            visited += 1
            if Self.bannerLike(e), let size = Self.size(e), size.width > 200, size.width < 600, size.height > 36, size.height < 260 {
                let text = Self.text(e)
                if text.count > 2 { out.append((text, e)); return }
            }
            for c in Self.children(e) { walk(c, depth + 1) }
        }
        walk(app, 0)
        return out
    }

    /// Clicks the banner (which opens what it's about); falls back to its first action on versions without AXPress.
    func press(_ el: AXUIElement) -> Bool {
        if AXUIElementPerformAction(el, kAXPressAction as CFString) == .success { return true }
        guard let first = Self.actions(el).first(where: { !$0.localizedCaseInsensitiveContains("close") }) else { return false }
        return AXUIElementPerformAction(el, first as CFString) == .success
    }

    private static func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
    }
    private static func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private static func actions(_ e: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(e, &names) == .success else { return [] }
        return names as? [String] ?? []
    }
    /// A banner is clickable, or says it's a notification (macOS names them AXNotificationCenterBanner/Alert).
    private static func bannerLike(_ e: AXUIElement) -> Bool {
        if (attr(e, kAXSubroleAttribute) as? String)?.contains("Notification") == true { return true }
        return actions(e).contains(kAXPressAction)
    }
    private static func size(_ e: AXUIElement) -> CGSize? {
        guard let v = attr(e, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
    /// The element's own description plus the static texts inside it.
    private static func text(_ e: AXUIElement) -> String {
        var parts: [String] = []
        if let d = attr(e, kAXDescriptionAttribute) as? String, !d.isEmpty { parts.append(d) }
        var budget = 40
        func collect(_ x: AXUIElement, _ depth: Int) {
            guard depth < 6, budget > 0 else { return }
            budget -= 1
            if (attr(x, kAXRoleAttribute) as? String) == kAXStaticTextRole, let v = attr(x, kAXValueAttribute) as? String, !v.isEmpty { parts.append(v) }
            for c in children(x) { collect(c, depth + 1) }
        }
        for c in children(e) { collect(c, 1) }
        return parts.joined(separator: ", ")
    }
}
