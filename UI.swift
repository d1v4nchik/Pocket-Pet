// The control panel: glassy and minimal, following your Mac's appearance and accent color. Pet, snacks, a few actions, then Pets / Closet / Settings.

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
    /// Which Settings groups are unfolded.
    @Published var open: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "openSections") ?? ["Connections"]) {
        didSet { UserDefaults.standard.set(Array(open), forKey: "openSections") }
    }
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
            .background(shape.fill(Color.accentColor.opacity(on ? 0.22 : 0)))
            .glass(size * 0.3, interactive: selected == nil)
            .overlay(shape.strokeBorder(Color.accentColor.opacity(on ? 0.9 : 0), lineWidth: 1.5))
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
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i < lit ? AnyShapeStyle(Color.accentColor.opacity(lit <= 1 ? 0.55 : 1)) : AnyShapeStyle(Color.primary.opacity(0.14)))
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
            .foregroundStyle(strong ? Color.white : Color.primary)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(strong ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.08))))
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

    /// What's playing (Spotify, Apple Music, or any other player), with the three buttons everyone needs.
    @ViewBuilder
    func nowPlaying(_ world: World) -> some View {
        let sp = world.player
        if sp.running && sp.full && sp.permission == AE.notAllowed {
            HStack {
                hint("Let Pocket Pet control \(sp.appName) to show what's playing")
                Spacer()
                Button("Allow") { openAutomation() }.buttonStyle(Pill(strong: true))
            }
        } else if sp.running && (sp.song != nil || sp.app == .other) {
            HStack(spacing: 10) {
                Art(url: sp.song?.art, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(sp.song?.name ?? "Playing in \(sp.appName)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(sp.song?.artist ?? (AXIsProcessTrusted() ? "Controlled with your media keys" : "Allow Accessibility in Settings to control it"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    if let s = sp.song {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.12))
                                Capsule().fill(Color.accentColor)
                                    .frame(width: s.duration > 0 ? g.size.width * min(1, sp.elapsed / s.duration) : 0)
                            }
                        }
                        .frame(height: 3)
                    }
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
        let sp = world.player
        VStack(alignment: .leading, spacing: 10) {
            if !sp.running {
                row("Nothing's playing") {
                    HStack(spacing: 5) {
                        ForEach([("Spotify", MusicPlayer.spotifyID), ("Music", MusicPlayer.musicID)], id: \.1) { name, id in
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                                Button("Open \(name)") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }.buttonStyle(Pill())
                            }
                        }
                    }
                }
                hint("Works with Spotify and Apple Music, and with any other player (YouTube Music, Tidal, VLC...) through your media keys.")
            } else if sp.full {
                HStack(spacing: 6) {
                    Button { sp.setShuffle(!sp.shuffle); m.refresh() } label: { Label("Shuffle", systemImage: "shuffle") }
                        .buttonStyle(Pill(strong: sp.shuffle))
                    Button { sp.setRepeat(!sp.repeating); m.refresh() } label: { Label("Repeat", systemImage: "repeat") }
                        .buttonStyle(Pill(strong: sp.repeating))
                }
            }
            if sp.running && !sp.full && !AXIsProcessTrusted() {
                HStack(alignment: .firstTextBaseline) {
                    hint("To control \(sp.appName), allow Accessibility (it presses your media keys for you).")
                    Spacer()
                    Button("Allow") { world.requestAccessibility() }.buttonStyle(Pill())
                }
            }
            if sp.spotifyInstalled {
                Divider().opacity(0.5)
                Text("Spotify queue").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                if sp.connected { queue(world) } else { spotifySteps(world) }
            }
        }
    }

    @ViewBuilder
    func queue(_ world: World) -> some View {
        let sp = world.player
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
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(sp.results) { s in
                        songRow(s) {
                            control("play.fill", 11) { sp.play(s) }.help("Play now")
                            control("plus", 13) { sp.addToQueue(s) }.help("Add to queue")
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
        } else {
            Text("Up next").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            if sp.upNext.isEmpty {
                hint(sp.running ? "Nothing queued" : "Play something in Spotify to see what's next")
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(sp.upNext.enumerated()), id: \.offset) { _, s in
                        songRow(s) { control("play.fill", 11) { sp.play(s) }.help("Play now") }
                    }
                }
            }
            .frame(maxHeight: 220)
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
        let sp = world.player
        return VStack(alignment: .leading, spacing: 6) {
            Text("See what's up next and add songs to your queue. Connect your Spotify account once, about 2 minutes:")
            HStack(alignment: .firstTextBaseline) {
                Text("1. Create an app (any name and description)")
                Spacer()
                Button("Open") { NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard/create")!) }.buttonStyle(Pill())
            }
            Text("2. Add this Redirect URI, tick Web API, save:")
            HStack {
                Text(MusicPlayer.redirect).font(.system(size: 10.5).monospaced()).foregroundStyle(.primary).textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(MusicPlayer.redirect, forType: .string)
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
                        Capsule().fill(m.tab == i ? Color.accentColor : .clear).frame(height: 2)
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
         "beanie": "Beanie", "witch": "Witch hat", "cowboy": "Cowboy hat", "santa": "Santa hat"][h.rawValue] ?? h.rawValue
    }
    func title(_ g: Glasses) -> String {
        ["none": "No glasses", "shades": "Shades", "hearts": "Heart glasses", "round": "Round glasses"][g.rawValue] ?? g.rawValue
    }
    func title(_ n: Neckwear) -> String {
        ["none": "Nothing", "scarf": "Scarf", "bowtie": "Bow tie", "bell": "Bell collar", "bandana": "Bandana"][n.rawValue] ?? n.rawValue
    }

    /// Three groups that fold away: the pet itself, what it connects to (each with a status and one control), the app.
    func settingsTab(_ world: World) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            section("Pet")
            if m.open.contains("Pet") {
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
                row("Water reminders") {
                    Picker("", selection: Binding(get: { Int(world.waterEvery) }, set: { world.setWater(Double($0)); m.refresh() })) {
                        Text("Off").tag(0); Text("30 min").tag(1800); Text("1 hour").tag(3600); Text("2 hours").tag(7200)
                    }
                    .frame(width: 108)
                }
                row("Name") {
                    TextField("Name", text: Binding(get: { m.editing ? m.draft : world.pet.name }, set: { m.draft = $0; m.editing = true }),
                              onCommit: { world.rename(m.draft); m.editing = false })
                        .textFieldStyle(.roundedBorder).frame(width: 130)
                }
                row("Sounds") { toggle(Binding(get: { world.soundOn }, set: { world.setSound($0); m.refresh() })) }
            }

            section("Connections")
            if m.open.contains("Connections") {
                calendar(world)
                connection("music.note", "Music",
                           world.player.running ? "Playing in \(world.player.appName)" : "Spotify, Apple Music or any player") {
                    Text(AXIsProcessTrusted() ? "Ready" : "Spotify and Music ready").foregroundStyle(.secondary).font(.system(size: 10.5))
                }
                connection("bell", "Notification bell",
                           !world.bellOn ? "Off" : AXIsProcessTrusted() ? "Every app" + (world.bellTabs ? " and browser tabs" : "") : (world.bellTabs ? "Browser tabs only for now" : "Waiting for Accessibility")) {
                    toggle(Binding(get: { world.bellOn }, set: { world.setBell($0); m.refresh() }))
                }
                if world.bellOn {
                    row("   Browser tabs") { toggle(Binding(get: { world.bellTabs }, set: { world.setBellTabs($0); m.refresh() })) }
                        .help("Rings when a tab's title shows new messages, like \"(2) Discord\"")
                }
                if !AXIsProcessTrusted() {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        hint("Every app's notifications, and play/pause for any music player, need Accessibility: switch on Pocket Pet in Privacy & Security › Accessibility. On a Mac you're not an admin of, that switch asks for an admin password.")
                        Button("Open") { world.requestAccessibility() }.buttonStyle(Pill(strong: true)).fixedSize()
                    }
                }
            }

            section("App")
            if m.open.contains("App") {
                if #available(macOS 13.0, *) {
                    row("Open at login") { toggle(Binding(get: { world.openAtLogin }, set: { world.openAtLogin = $0; m.refresh() })) }
                }
                if world.updater.enabled { updatesRow(world) }
            }
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

    /// A group heading that folds its rows away (remembered between launches).
    func section(_ title: String) -> some View {
        let isOpen = m.open.contains(title)
        return Button {
            if isOpen { m.open.remove(title) } else { m.open.insert(title) }
        } label: {
            HStack(spacing: 4) {
                Text(title.uppercased()).font(.system(size: 10, weight: .semibold))
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).rotationEffect(.degrees(isOpen ? 90 : 0))
                Spacer()
            }
            .foregroundStyle(.secondary).contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.top, 4)
    }

    /// One connection: an icon, its name, where it stands, and one control.
    func connection<C: View>(_ symbol: String, _ title: String, _ status: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 18).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(status).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            control()
        }
    }

    func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    func toggle(_ b: Binding<Bool>) -> some View {
        Toggle("", isOn: b).toggleStyle(.switch).controlSize(.small)        // the system's own accent color
    }

    @ViewBuilder
    func calendar(_ world: World) -> some View {
        let mac = world.macCal, g = world.google, ics = world.ics
        let linked = g.signedIn || ics.connected || !mac.accounts.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            connection("calendar", "Calendar", calendarStatus(world)) {
                if g.signedIn { Button("Sign out") { g.signOut(); m.refresh() }.buttonStyle(Pill()) }
                else if ics.connected { Button("Disconnect") { ics.disconnect(); m.refresh() }.buttonStyle(Pill()) }
                else if !linked { Button(m.calWay == 0 ? "Set up" : "Close") { m.calWay = m.calWay == 0 ? 1 : 0 }.buttonStyle(Pill(strong: m.calWay == 0)) }
            }
            if !linked && m.calWay != 0 {
                // three ways in, easiest first
                HStack(spacing: 6) { way("Paste a link", 1); way("This Mac", 2); way("Google sign-in", 3) }
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
        if !mac.accounts.isEmpty { return "This Mac: " + mac.accounts.joined(separator: ", ") }
        return "Google, Outlook, iCloud or Mac"
    }

    /// No sign-in: any calendar's private iCal link (Google, Outlook, iCloud...).
    func linkSteps(_ world: World) -> some View {
        let ics = world.ics
        return VStack(alignment: .leading, spacing: 5) {
            Text("No sign-in needed: paste your calendar's private iCal link. Google: Settings › your calendar › Secret address in iCal format. Outlook: Settings › Shared calendars › Publish › ICS. iCloud: Calendar app › Share Calendar › Public Calendar.")
            HStack(spacing: 6) {
                Menu("Where?") {
                    Button("Google Calendar settings") { NSWorkspace.shared.open(URL(string: "https://calendar.google.com/calendar/r/settings")!) }
                    Button("Outlook calendar settings") { NSWorkspace.shared.open(URL(string: "https://outlook.live.com/calendar/0/options/calendar/SharedCalendars")!) }
                }
                .menuStyle(.borderlessButton).fixedSize()
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

    /// Through macOS: every calendar the Mac already has, read with EventKit.
    func macSteps(_ world: World) -> some View {
        let mac = world.macCal
        return VStack(alignment: .leading, spacing: 5) {
            Text("Uses the calendars already on this Mac: iCloud, Outlook, Google and any account in System Settings › Internet Accounts.")
            Button(mac.authorized ? "Add an account" : "Allow") {
                if mac.authorized { MacCalendar.openInternetAccounts() }
                else { mac.connect { ok in if ok && mac.accounts.isEmpty { MacCalendar.openInternetAccounts() }; m.refresh() } }
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

/// Album art, kept in memory once loaded (and fetched ahead of time) so it's there instantly; it fades in otherwise.
final class ArtCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func cached(_ url: String) -> NSImage? { cache.object(forKey: url as NSString) }

    static func load(_ url: String, _ done: @escaping (NSImage?) -> Void) {
        if let img = cached(url) { done(img); return }
        guard let u = URL(string: url) else { done(nil); return }
        URLSession.shared.dataTask(with: u) { data, _, _ in
            let img = data.flatMap(NSImage.init(data:))
            if let img { cache.setObject(img, forKey: url as NSString) }
            DispatchQueue.main.async { done(img) }
        }.resume()
    }

    static func prefetch(_ urls: [String?]) { for u in urls.compactMap({ $0 }) where cached(u) == nil { load(u) { _ in } } }
}

struct Art: View {
    let url: String?
    let size: CGFloat
    @State private var image: NSImage?
    @State private var shown: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
        let img = image ?? url.flatMap(ArtCache.cached)
        ZStack {
            shape.fill(Color.primary.opacity(0.08))
            Image(systemName: "music.note").foregroundStyle(.secondary)
            if let img {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .onAppear(perform: load)
        .onChange(of: url) { _ in load() }
    }

    private func load() {
        guard let url, shown != url else { return }
        shown = url
        if let c = ArtCache.cached(url) { image = c; return }
        image = nil
        ArtCache.load(url) { img in withAnimation(.easeOut(duration: 0.2)) { image = img } }
    }
}
