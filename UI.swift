// The control panel: black and white, glassy, minimal. Pet, snacks, a few actions, then Pets / Closet / Settings.

import SwiftUI
import UniformTypeIdentifiers

final class UIModel: ObservableObject {
    weak var world: World?
    @Published var tick = 0
    @Published var tab = 0
    @Published var editing = false
    @Published var draft = ""
    @Published var calWay = 0          // which way to connect Google Calendar is open: 1 link, 2 Mac, 3 sign in
    @Published var link = ""
    @Published var songQuery = ""
    @Published var closetPart = 0
    @Published var spotifyID = ""

    func refresh() { tick &+= 1 }
}

/// Offscreen debug renders can't draw Liquid Glass, so they use the plain fallback.
var plainGlass = false

extension View {
    /// Liquid Glass on macOS 26, frosted material before that.
    @ViewBuilder func glass(_ radius: CGFloat = 10, interactive: Bool = true) -> some View {
        if #available(macOS 26.0, *), !plainGlass {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: radius))
        } else {
            self.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
    }
}

struct Pixel: View {
    let img: NSImage
    var body: some View { Image(nsImage: img).interpolation(.none).resizable().aspectRatio(contentMode: .fit) }
}

/// A small glass button showing a pixel picture or a symbol, with a tooltip.
struct Tile: View {
    var img: NSImage? = nil
    var symbol: String? = nil
    let help: String
    /// nil for action buttons; true/false for a choice (pet, outfit), which gets a fixed outline and no hover glow,
    /// so the glow under the cursor can't be mistaken for the current choice.
    var selected: Bool? = nil
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        let on = selected == true
        Button(action: action) {
            Group {
                if let img { Pixel(img: img).padding(size * 0.16) }
                else { Image(systemName: symbol ?? "circle").font(.system(size: size * 0.4, weight: .regular)) }
            }
            .frame(width: size, height: size)
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
            .background(shape.fill(Color.primary.opacity(on ? 0.16 : 0)))
            .glass(size * 0.3, interactive: selected == nil)
            .overlay(shape.strokeBorder(Color.primary.opacity(on ? 0.85 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// A need as a pixel icon and six blocks, like a health bar in a game. Hover for the exact value.
struct Meter: View {
    let icon: NSImage
    let value: Double
    let name: String
    var body: some View {
        let lit = Int((value / 100 * 6).rounded(.up))
        HStack(spacing: 5) {
            Pixel(img: icon).frame(width: 17, height: 17)
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(i < lit ? (lit <= 1 ? 0.5 : 0.85) : 0.14))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .help("\(name): \(Int(value.rounded()))%")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

struct Pill: ButtonStyle {
    var strong = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(strong ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(strong ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.08))))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct RootView: View {
    @ObservedObject var m: UIModel

    var body: some View {
        if let world = m.world, let pet = world.pet {
            VStack(alignment: .leading, spacing: 14) {
                header(world, pet)
                actions(world, pet)
                nowPlaying(world)
                tabs
                Group {
                    switch m.tab {
                    case 0: petsTab(world, pet)
                    case 1: closetTab(world, pet)
                    case 2: musicTab(world)
                    default: settingsTab(world)
                    }
                }
                footer(world)
            }
            .padding(16)
            .frame(width: 318)
            .font(.system(size: 12))
        }
    }

    // MARK: Header

    /// What the pet is up to, and its three needs as little game-style meters.
    func header(_ world: World, _ pet: Pet) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(world.hidden ? "Hidden" : mood(world, pet).capitalizedFirst).font(.system(size: 14, weight: .semibold))
                Spacer()
                if world.hidden { Button("Show pet") { world.toggleHidden(); m.refresh() }.buttonStyle(Pill(strong: true)) }
            }
            HStack(spacing: 12) {
                Meter(icon: world.itemImage(.fish), value: pet.fullness, name: "Food")
                Meter(icon: world.iconImage(.heart), value: pet.happiness, name: "Happiness")
                Meter(icon: world.iconImage(.bolt), value: pet.energy, name: "Energy")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func mood(_ world: World, _ pet: Pet) -> String {
        switch pet.mode {
        case .sleeping, .yawning, .catnap: return "sleeping"
        case .typing: return "typing with you"
        case .watching: return "watching with you"
        case .listening: return "listening to \(world.musicApp.isEmpty ? "music" : world.musicApp)"
        case .eating: return "munching"
        case .ball, .butterfly, .zoomies, .hunt: return "playing"
        case .held: return "being held"
        case .glide: return "floating down"
        case .fly: return "flying"
        default:
            if pet.fullness < 25 { return "hungry" }
            if pet.energy < 25 { return "sleepy" }
            if pet.happiness > 70 { return "happy" }
            return "chilling"
        }
    }

    // MARK: Actions

    func actions(_ world: World, _ pet: Pet) -> some View {
        // Petting, the calendar and gravity live on the pet itself (click, double-click) and in Settings.
        // These buttons close the menu so you see the pet act on them right away.
        let foods: [(ItemKind, String)] = [(.fish, "Fish"), (.bone, "Bone"), (.cookie, "Cookie")]
        return HStack(spacing: 7) {
            ForEach(foods, id: \.1) { f in Tile(img: world.itemImage(f.0), help: "Feed: \(f.1)") { world.fromMenu { world.feed(f.0) } } }
            Tile(img: world.itemImage(pet.family == .cat ? .yarn : .ball), help: "Throw a toy") { world.fromMenu { world.throwBall() } }
            Tile(img: world.itemImage(.butterfly), help: "Let a butterfly out") { world.fromMenu { world.releaseButterfly() } }
            Tile(img: world.iconImage(pet.isAsleep ? .sun : .moon), help: pet.isAsleep ? "Wake up" : "Nap") { world.fromMenu { pet.toggleNap() } }
            Tile(img: world.iconImage(.pin), help: "Come here: follows your cursor for a minute") { world.fromMenu { pet.comeHere() } }
        }
    }

    // MARK: Music

    /// What's playing in Spotify, with the three buttons everyone needs.
    @ViewBuilder
    func nowPlaying(_ world: World) -> some View {
        let sp = world.spotify
        if sp.running && sp.permission == AE.notAllowed {
            HStack {
                hint("Let Pocket Pet control Spotify to show what's playing")
                Spacer()
                Button("Allow") { openAutomation() }.buttonStyle(Pill(strong: true))
            }
        } else if sp.running, let s = sp.song {
            HStack(spacing: 10) {
                Art(url: s.art, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(s.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.12))
                            Capsule().fill(Color.primary.opacity(0.7))
                                .frame(width: s.duration > 0 ? g.size.width * min(1, sp.elapsed / s.duration) : 0)
                        }
                    }
                    .frame(height: 3)
                }
                HStack(spacing: 0) {
                    control("backward.fill", 12) { sp.previous() }
                    control(sp.playing ? "pause.fill" : "play.fill", 16) { sp.playPause(); m.refresh() }
                    control("forward.fill", 12) { sp.next() }
                }
            }
            .padding(8)
            .glass(14)
        }
    }

    func control(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func openAutomation() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    @ViewBuilder
    func musicTab(_ world: World) -> some View {
        let sp = world.spotify
        VStack(alignment: .leading, spacing: 10) {
            if !sp.running {
                row("Spotify isn't open") {
                    Button("Open Spotify") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Spotify.bid) {
                            NSWorkspace.shared.openApplication(at: url, configuration: .init())
                        }
                    }
                    .buttonStyle(Pill())
                }
            } else {
                HStack(spacing: 6) {
                    Button { sp.setShuffle(!sp.shuffle); m.refresh() } label: { Label("Shuffle", systemImage: "shuffle") }
                        .buttonStyle(Pill(strong: sp.shuffle))
                    Button { sp.setRepeat(!sp.repeating); m.refresh() } label: { Label("Repeat", systemImage: "repeat") }
                        .buttonStyle(Pill(strong: sp.repeating))
                }
            }
            if sp.connected { queue(world) } else { spotifySteps(world) }
        }
    }

    @ViewBuilder
    func queue(_ world: World) -> some View {
        let sp = world.spotify
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find a song to add", text: $m.songQuery, onCommit: { sp.search(m.songQuery) })
                .textFieldStyle(.plain)
            if !m.songQuery.isEmpty {
                Button { m.songQuery = ""; sp.search("") } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glass(10)
        if !sp.status.isEmpty { hint(sp.status) }
        if !sp.results.isEmpty {
            ForEach(sp.results) { s in
                songRow(s) {
                    control("play.fill", 11) { sp.play(s) }.help("Play now")
                    control("plus", 13) { sp.addToQueue(s) }.help("Add to queue")
                }
            }
        } else {
            Text("Up next").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            if sp.upNext.isEmpty {
                hint(sp.running ? "Nothing queued" : "Play something in Spotify to see what's next")
            }
            ForEach(Array(sp.upNext.prefix(6).enumerated()), id: \.offset) { _, s in songRow(s) { EmptyView() } }
        }
        Button("Disconnect Spotify account") { sp.disconnect(); m.refresh() }
            .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.secondary)
    }

    func songRow<B: View>(_ s: Song, @ViewBuilder buttons: () -> B) -> some View {
        HStack(spacing: 8) {
            Art(url: s.art, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.system(size: 12)).lineLimit(1)
                Text(s.artist).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            buttons()
        }
    }

    /// Connecting a Spotify account: a free developer app and its client ID (no secret).
    func spotifySteps(_ world: World) -> some View {
        let sp = world.spotify
        return VStack(alignment: .leading, spacing: 6) {
            Text("See what's up next and add songs to your queue. Connect your Spotify account once, about 2 minutes:")
            HStack(alignment: .firstTextBaseline) {
                Text("1. Create an app (any name and description)")
                Spacer()
                Button("Open") { NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard/create")!) }.buttonStyle(Pill())
            }
            Text("2. Add this Redirect URI, tick Web API, save:")
            HStack {
                Text(Spotify.redirect).font(.system(size: 10.5).monospaced()).foregroundStyle(.primary).textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Spotify.redirect, forType: .string)
                }
                .buttonStyle(Pill())
            }
            Text("3. Copy the Client ID from the app's page:")
            HStack(spacing: 6) {
                TextField("Client ID", text: $m.spotifyID).textFieldStyle(.roundedBorder).foregroundStyle(.primary)
                Button(m.spotifyID.isEmpty ? "Paste" : "Connect") {
                    let id = m.spotifyID.isEmpty ? (NSPasteboard.general.string(forType: .string) ?? "") : m.spotifyID
                    sp.connect(clientID: id) { ok in if ok { m.spotifyID = "" }; m.refresh() }
                    m.refresh()
                }
                .buttonStyle(Pill(strong: true))
            }
            if !sp.status.isEmpty { Text(sp.status) }
            Text("Adding songs to the queue needs Spotify Premium.")
        }
        .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    var tabs: some View {
        HStack(spacing: 16) {
            ForEach(Array(["Pets", "Closet", "Music", "Settings"].enumerated()), id: \.offset) { i, title in
                Button { m.tab = i } label: {
                    VStack(spacing: 3) {
                        Text(title).font(.system(size: 12, weight: m.tab == i ? .semibold : .regular))
                            .foregroundStyle(m.tab == i ? .primary : .secondary)
                        Capsule().fill(m.tab == i ? Color.primary : .clear).frame(height: 1.5)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Tabs

    func petsTab(_ world: World, _ pet: Pet) -> some View {
        HStack(spacing: 5) {
            ForEach(Species.allCases) { sp in
                Tile(img: world.faceImage(sp), help: sp.title, selected: pet.species == sp, size: 36) { world.changeSpecies(to: sp); m.refresh() }
            }
        }
    }

    /// Dress-up: your pet big on the left in its outfit, one kind of item at a time on the right.
    func closetTab(_ world: World, _ pet: Pet) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Pixel(img: world.bodyImage(pet.species, pet.outfit))
                .padding(10)
                .frame(width: 78, height: 104)
                .glass(16)
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 5) {
                    ForEach(Array(["Hats", "Glasses", "Neck"].enumerated()), id: \.offset) { i, name in
                        Button(name) { m.closetPart = i }.buttonStyle(Pill(strong: m.closetPart == i))
                    }
                }
                .fixedSize()
                switch m.closetPart {
                case 0: closetGrid(world, pet, Hat.allCases, \.hat, title, roomForHat: true)
                case 1: closetGrid(world, pet, Glasses.allCases, \.glasses, title)
                default: closetGrid(world, pet, Neckwear.allCases, \.neck, title)
                }
                HStack(spacing: 5) {
                    Button("Surprise me") {
                        world.setOutfit(Outfit(hat: Hat.allCases.randomElement()!, glasses: Glasses.allCases.randomElement()!, neck: Neckwear.allCases.randomElement()!))
                        m.refresh()
                    }
                    .buttonStyle(Pill())
                    Button("Undress") { world.setOutfit(Outfit()); m.refresh() }.buttonStyle(Pill())
                }
                .fixedSize()
            }
        }
    }

    func closetGrid<T: Hashable>(_ world: World, _ pet: Pet, _ all: [T], _ path: WritableKeyPath<Outfit, T>, _ name: @escaping (T) -> String, roomForHat: Bool = false) -> some View {
        let grid = Array(repeating: GridItem(.fixed(40), spacing: 6), count: 4)
        return LazyVGrid(columns: grid, alignment: .leading, spacing: 6) {
            ForEach(all, id: \.self) { item in
                let o: Outfit = { var o = pet.outfit; o[keyPath: path] = item; return o }()
                let alone: Outfit = { var a = Outfit(); a[keyPath: path] = item; return a }()
                let picked = pet.outfit[keyPath: path] == item
                // just the accessory itself; the big picture on the left shows it on your pet
                if let img = world.accessoryImage(alone) {
                    Tile(img: img, help: name(item), selected: picked, size: 40) { world.setOutfit(o); m.refresh() }
                } else {
                    Tile(symbol: "circle.slash", help: name(item), selected: picked, size: 40) { world.setOutfit(o); m.refresh() }
                }
            }
        }
    }

    func title(_ h: Hat) -> String {
        ["none": "No hat", "bow": "Bow", "flower": "Flower", "crown": "Crown", "topHat": "Top hat", "party": "Party hat",
         "beanie": "Beanie", "witch": "Witch hat", "cowboy": "Cowboy hat"][h.rawValue] ?? h.rawValue
    }
    func title(_ g: Glasses) -> String {
        ["none": "No glasses", "shades": "Shades", "hearts": "Heart glasses", "round": "Round glasses"][g.rawValue] ?? g.rawValue
    }
    func title(_ n: Neckwear) -> String {
        ["none": "Nothing", "scarf": "Scarf", "bowtie": "Bow tie", "bell": "Bell collar", "bandana": "Bandana"][n.rawValue] ?? n.rawValue
    }

    func settingsTab(_ world: World) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            row("Gravity") { toggle(Binding(get: { world.gravity }, set: { world.setGravity($0) })) }
            row("Size") {
                Picker("", selection: Binding(get: { world.sizeSetting }, set: { world.setSize($0); m.refresh() })) {
                    Text("S").tag(3); Text("M").tag(4); Text("L").tag(5)
                }
                .pickerStyle(.segmented).frame(width: 108)
            }
            row("Naps after") {
                Picker("", selection: Binding(get: { Int(world.sleepAfter) }, set: { world.sleepAfter = Double($0); world.save(); m.refresh() })) {
                    Text("1 min").tag(60); Text("2 min").tag(120); Text("5 min").tag(300); Text("10 min").tag(600)
                }
                .frame(width: 108)
            }
            row("Name") {
                TextField("Name", text: Binding(get: { m.editing ? m.draft : world.pet.name }, set: { m.draft = $0; m.editing = true }),
                          onCommit: { world.rename(m.draft); m.editing = false })
                    .textFieldStyle(.roundedBorder).frame(width: 130)
            }
            row("Notification bell") { toggle(Binding(get: { world.bellOn }, set: { world.setBell($0); m.refresh() })) }
            if world.bellOn && !AXIsProcessTrusted() {
                HStack(alignment: .firstTextBaseline) {
                    hint("Rings for new messages in browser tabs. To ring for any app's notifications, allow Accessibility.")
                    Spacer()
                    Button("Allow") { world.requestAccessibility() }.buttonStyle(Pill())
                }
            }
            row("Sounds") { toggle(Binding(get: { world.soundOn }, set: { world.setSound($0); m.refresh() })) }
            if #available(macOS 13.0, *) {
                row("Open at login") { toggle(Binding(get: { world.openAtLogin }, set: { world.openAtLogin = $0; m.refresh() })) }
            }
            Divider()
            calendar(world)
            Divider()
            if world.updater.enabled { updatesRow(world) }
            HStack {
                Button(world.hidden ? "Show pet" : "Hide pet") { world.toggleHidden(); m.refresh() }.buttonStyle(Pill())
                    .help("⌃⌥P brings your pet back (or opens this menu)")
                Spacer()
                Button("Quit") { world.quit() }.buttonStyle(Pill())
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    func updatesRow(_ world: World) -> some View {
        let u = world.updater
        row("Version \(Updater.current)") {
            if let r = u.available {
                Button(u.busy ? "Updating…" : "Update to \(r.version)") { u.install(); m.refresh() }
                    .buttonStyle(Pill(strong: true)).disabled(u.busy)
            } else {
                Button("Check for updates") { u.check { m.refresh() }; m.refresh() }.buttonStyle(Pill())
            }
        }
        if !u.status.isEmpty { hint(u.status) }
    }

    func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    func toggle(_ b: Binding<Bool>) -> some View {
        Toggle("", isOn: b).toggleStyle(.switch).controlSize(.small).tint(.primary)
    }

    @ViewBuilder
    func calendar(_ world: World) -> some View {
        let mac = world.macCal, g = world.google, ics = world.ics
        let linked = g.signedIn || ics.connected || !mac.googleAccounts.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Google Calendar").font(.system(size: 12, weight: .semibold))
                    Text(calendarStatus(world)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if g.signedIn { Button("Sign out") { g.signOut(); m.refresh() }.buttonStyle(Pill()) }
                else if ics.connected { Button("Disconnect") { ics.disconnect(); m.refresh() }.buttonStyle(Pill()) }
            }
            if !linked {
                // three ways in, easiest first
                HStack(spacing: 6) { way("Paste link", 1); way("Mac Calendar", 2); way("Sign in", 3) }
                switch m.calWay {
                case 1: linkSteps(world)
                case 2: macSteps(world)
                case 3: advancedGoogle(world)
                default: EmptyView()
                }
            }
            if !g.status.isEmpty { Text(g.status).font(.system(size: 10.5)).foregroundStyle(.secondary) }
        }
    }

    func way(_ title: String, _ n: Int) -> some View {
        Button(title) { m.calWay = m.calWay == n ? 0 : n }.buttonStyle(Pill(strong: m.calWay == n))
    }

    func calendarStatus(_ world: World) -> String {
        let g = world.google, mac = world.macCal, ics = world.ics
        if g.signedIn { return g.email.isEmpty ? "Signed in" : g.email }
        if ics.connected { return "Connected with your private link" }
        if !mac.googleAccounts.isEmpty { return mac.googleAccounts.joined(separator: ", ") }
        return "Ask me what's coming up, get reminders"
    }

    /// No sign-in: Google Calendar's private iCal link.
    func linkSteps(_ world: World) -> some View {
        let ics = world.ics
        return VStack(alignment: .leading, spacing: 5) {
            Text("No sign-in needed. In Google Calendar settings, click your calendar on the left, scroll to Integrate calendar and copy the Secret address in iCal format.")
            HStack(spacing: 6) {
                Button("Open settings") { NSWorkspace.shared.open(URL(string: "https://calendar.google.com/calendar/r/settings")!) }
                    .buttonStyle(Pill())
                TextField("Paste the link", text: $m.link).textFieldStyle(.roundedBorder).foregroundStyle(.primary)
                Button(m.link.isEmpty ? "Paste" : "Connect") {
                    let link = m.link.isEmpty ? (NSPasteboard.general.string(forType: .string) ?? "") : m.link
                    ics.setLink(link) { ok in
                        if ok { m.link = ""; m.calWay = 0; world.showAgenda() }
                        m.refresh()
                    }
                    m.refresh()
                }
                .buttonStyle(Pill(strong: true))
            }
            if !ics.status.isEmpty { Text(ics.status) }
        }
        .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    /// Through macOS: add the Google account once in System Settings, read it with EventKit.
    func macSteps(_ world: World) -> some View {
        let mac = world.macCal
        return VStack(alignment: .leading, spacing: 5) {
            Text("Add your Google account to this Mac once (System Settings › Internet Accounts › Google, keep Calendars on). Your pet reads it from there.")
            Button(mac.authorized ? "Open Internet Accounts" : "Allow & open settings") {
                if mac.authorized { MacCalendar.openInternetAccounts() }
                else { mac.connect { ok in if ok && mac.googleAccounts.isEmpty { MacCalendar.openInternetAccounts() }; m.refresh() } }
            }
            .buttonStyle(Pill(strong: true))
        }
        .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    func advancedGoogle(_ world: World) -> some View {
        let g = world.google
        return VStack(alignment: .leading, spacing: 4) {
            Text("Your own Google Cloud app. Takes a few minutes.")
            Text("1. In Google Cloud, create a project and enable the Calendar API")
            Text("2. OAuth consent screen → External → add yourself as a test user")
            Text("3. Credentials → OAuth client ID → Desktop app → download the JSON")
            HStack {
                Button("Open Google Cloud") { NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!) }
                    .buttonStyle(Pill())
                Button(g.hasClient ? "Change file…" : "Choose file…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.json]
                    panel.message = "Choose the client JSON you downloaded from Google Cloud"
                    if panel.runModal() == .OK, let url = panel.url { _ = g.importClientFile(url); m.refresh() }
                }
                .buttonStyle(Pill())
                if g.hasClient { Button("Sign in") { g.signIn { _ in m.refresh() }; m.refresh() }.buttonStyle(Pill(strong: true)) }
            }
            .padding(.top, 2)
        }
        .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    func row<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack {
            Text(label)
            Spacer()
            c().labelsHidden()
        }
    }

    // MARK: Footer

    func footer(_ world: World) -> some View {
        HStack(spacing: 10) {
            if let next = world.calendarEvents.first(where: { $0.end > Date() && !$0.allDay }) {
                Label("\(next.start.formatted(date: .omitted, time: .shortened))  \(next.title)", systemImage: "calendar").lineLimit(1)
            }
            Spacer()
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }
}

/// Album art, in black and white like the rest of the menu.
struct Art: View {
    let url: String?
    let size: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
        AsyncImage(url: url.flatMap(URL.init(string:))) { img in
            img.resizable().aspectRatio(contentMode: .fill).grayscale(1)
        } placeholder: {
            ZStack { shape.fill(Color.primary.opacity(0.08)); Image(systemName: "music.note").foregroundStyle(.secondary) }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }
}
