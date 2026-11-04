// The control panel: glassy and minimal, following your Mac's appearance and accent color. Pet, snacks, a few actions, then Pets / Closet / Settings.

import Charts
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
    @Published var habitText = ""
    @Published var habitEvery = 0              // 0 = daily at habitTime
    @Published var habitTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @Published var waterDays = 7               // the Water chart: a week or a month
    @Published var searching = false           // the Music tab's queue box is searching Spotify
    @Published var spotifySetup = false        // the steps to connect a Spotify account are open

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

/// Tiles in one shared glass layer (a GlassEffectContainer): far cheaper to draw than a separate glass per tile,
/// which made the menu lag.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder let content: () -> Content
    var body: some View {
        if #available(macOS 26.0, *), !plainGlass { GlassEffectContainer(spacing: spacing) { content() } }
        else { content() }
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

/// The Advanced Settings window: a standard Mac settings window, with a sidebar of panes and grouped forms.
struct AdvancedSettingsView: View {
    @ObservedObject var m: UIModel
    @State private var pane: String?
    init(m: UIModel, start: String = "General") { self.m = m; _pane = State(initialValue: start) }
    static let panes = [("General", "gearshape"), ("Behaviour", "pawprint"), ("Water", "drop"), ("Reminders", "checklist"),
                        ("Sounds", "speaker.wave.2"), ("Connections", "link")]

    var body: some View {
        if let world = m.world {
            NavigationSplitView {
                List(Self.panes, id: \.0, selection: $pane) { p in Label(p.0, systemImage: p.1).tag(p.0) }
                    .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
            } detail: {
                Form { RootView(m: m).pane(pane ?? "General", world) }
                    .formStyle(.grouped)
                    .navigationTitle(pane ?? "General")
            }
            .frame(minWidth: 640, minHeight: 460)
        }
    }
}

struct RootView: View {
    @ObservedObject var m: UIModel

    var body: some View {
        if let world = m.world, let pet = world.pet {
            VStack(alignment: .leading, spacing: 14) {
                // the same order on every tab; the Music tab just leaves out the snacks and toys
                header(world, pet)
                nowPlaying(world)
                if m.tab != 2 { actions(world, pet) }
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
            // an update waiting: one click installs it
            if let r = world.updater.available {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                    Text("Pocket Pet \(r.version) is ready").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button(world.updater.busy ? "Updating…" : "Update") { world.updater.install() }
                        .buttonStyle(Pill(strong: true)).disabled(world.updater.busy)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .glass(12)
            }
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
        // eight buttons, sized to fit the menu's width
        return GlassGroup { HStack(spacing: 5) {
            ForEach(foods, id: \.1) { f in Tile(img: world.itemImage(f.0), help: "Feed: \(f.1)", size: 31) { world.fromMenu { world.feed(f.0) } } }
            Tile(img: world.itemImage(pet.family == .cat ? .yarn : .ball), help: "Throw a toy", size: 31) { world.fromMenu { world.throwBall() } }
            Tile(img: world.itemImage(.butterfly), help: "Let a butterfly out", size: 31) { world.fromMenu { world.releaseButterfly() } }
            Tile(img: world.iconImage(pet.isAsleep ? .sun : .moon), help: pet.isAsleep ? "Wake up" : "Nap", size: 31) { world.fromMenu { pet.toggleNap() } }
            Tile(img: world.iconImage(.pin), help: pet.following ? "Stop following" : "Come here: follows your cursor (press again to stop)",
                 selected: pet.following ? true : nil, size: 31) { world.fromMenu { pet.comeHere() } }
            // stay in place, in three steps: roams, stays put (still grooms), completely still
            Tile(img: world.iconImage([Icon.roam, .anchor, .still][world.stillness]),
                 help: ["Roams around. Click: stay put", "Stays put but still grooms. Click: hold completely still",
                        "Holds completely still. Click: roam again"][world.stillness],
                 selected: world.stillness > 0 ? true : nil, size: 31) { world.cycleStillness(); m.refresh() }
        } }
    }

    // MARK: Music

    /// What's playing (Spotify, Apple Music, or any other player). In the same spot on every tab; on the Music tab it
    /// opens up in place with the timeline, shuffle and repeat.
    @ViewBuilder
    func nowPlaying(_ world: World) -> some View {
        let sp = world.player
        let expanded = m.tab == 2
        if sp.running && sp.full && sp.permission == AE.notAllowed {
            HStack {
                hint("Let Pocket Pet control \(sp.appName) to show what's playing")
                Spacer()
                Button("Allow") { openAutomation() }.buttonStyle(Pill(strong: true))
            }
        } else if sp.running && (sp.song != nil || sp.app == .other) {
            VStack(spacing: expanded ? 8 : 0) {
                HStack(spacing: 10) {
                    Art(url: sp.song?.art, size: expanded ? 48 : 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sp.song?.name ?? "Playing in \(sp.appName)").font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Text(sp.song?.artist ?? (world.trusted ? "Controlled with your media keys" : "Allow Accessibility to control it"))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        if !expanded, let s = sp.song { progress(sp, s, times: false) }
                    }
                    Spacer(minLength: 4)
                    if !expanded { transport(sp, size: 12) }
                }
                if expanded {
                    if let s = sp.song { progress(sp, s, times: true) }
                    HStack(spacing: 0) {
                        if sp.full { toggleIcon("shuffle", on: sp.shuffle) { sp.setShuffle(!sp.shuffle); m.refresh() }.help("Shuffle") }
                        Spacer()
                        transport(sp, size: 14)
                        Spacer()
                        if sp.full { toggleIcon("repeat", on: sp.repeating) { sp.setRepeat(!sp.repeating); m.refresh() }.help("Repeat") }
                    }
                }
            }
            .padding(expanded ? 12 : 8)
            .glass(14)
        }
    }

    func transport(_ sp: MusicPlayer, size: CGFloat) -> some View {
        HStack(spacing: 0) {
            control("backward.fill", size) { sp.previous() }
            control(sp.playing ? "pause.fill" : "play.fill", size + 4) { sp.playPause(); m.refresh() }
            control("forward.fill", size) { sp.next() }
        }
    }

    func toggleIcon(_ symbol: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The song's timeline; ticks by itself, so the rest of the menu isn't redrawn every second.
    func progress(_ sp: MusicPlayer, _ s: Song, times: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: sp.playing ? 1 : 3600)) { _ in
            VStack(spacing: 3) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule().fill(Color.accentColor).frame(width: s.duration > 0 ? g.size.width * min(1, sp.elapsed / s.duration) : 0)
                    }
                }
                .frame(height: 3)
                if times {
                    HStack {
                        Text(clock(sp.elapsed)); Spacer(); Text(clock(s.duration))
                    }
                    .font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: times ? 18 : 3)
    }

    func clock(_ s: Double) -> String { let n = Int(max(0, s)); return "\(n / 60):" + String(format: "%02d", n % 60) }

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
                // nothing playing: open a player
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing's playing").font(.system(size: 12.5, weight: .semibold))
                    HStack(spacing: 6) {
                        ForEach([("Spotify", MusicPlayer.spotifyID), ("Music", MusicPlayer.musicID)], id: \.1) { name, id in
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                                Button("Open \(name)") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }.buttonStyle(Pill())
                            }
                        }
                    }
                    hint("Works with Spotify, Apple Music and any other player (through your media keys).")
                }
            } else if !sp.full && !world.trusted {
                HStack(alignment: .firstTextBaseline) {
                    hint("To control \(sp.appName), allow Accessibility (it presses your media keys for you).")
                    Spacer()
                    Button("Allow") { world.requestAccessibility() }.buttonStyle(Pill())
                }
            }
            if sp.spotifyInstalled {
                if sp.connected { queue(world) }
                else if m.spotifySetup { spotifySteps(world) }
                else {
                    HStack {
                        hint("See what's up next and search Spotify")
                        Spacer()
                        Button("Connect") { m.spotifySetup = true }.buttonStyle(Pill())
                    }
                }
            }
        }
    }

    /// Up next, or search results while you're searching: one box, one kind of row.
    @ViewBuilder
    func queue(_ world: World) -> some View {
        let sp = world.player
        let searching = m.searching
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if searching {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search Spotify", text: $m.songQuery, onCommit: { sp.search(m.songQuery) }).textFieldStyle(.plain)
                    Button { m.searching = false; m.songQuery = ""; sp.search("") } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("Back to Up next")
                } else {
                    Text("Up next").font(.system(size: 12, weight: .semibold))
                    if !sp.upNext.isEmpty { Text("\(sp.upNext.count)").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Spacer()
                    Button { m.searching = true } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.plain).help("Search Spotify to play or queue a song")
                }
            }
            .frame(height: 20)
            if !sp.status.isEmpty { Text(sp.status).font(.system(size: 10.5)).foregroundStyle(.secondary) }
            let rows: [Song] = searching ? sp.results : sp.upNext
            if rows.isEmpty {
                Text(searching ? (m.songQuery.isEmpty ? "Type a song or artist, then press Return" : "Nothing found yet")
                     : (sp.running ? "Nothing queued" : "Play something in Spotify to see what's next"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                // a box that scrolls, so the menu keeps its size however long the list is
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, s in
                            songRow(s) {
                                if searching {
                                    control("play.fill", 11) { sp.play(s); m.searching = false; m.songQuery = ""; sp.clearResults() }.help("Play this song next, now")
                                    control("plus", 13) { sp.addToQueue(s) }.help("Add to the end of your queue")
                                } else {
                                    control("play.fill", 11) { sp.skip(to: i); m.refresh() }.help("Skip ahead to this song")
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(10)
        .glass(14)
    }

    func songRow<B: View>(_ s: Song, @ViewBuilder buttons: () -> B) -> some View {
        HStack(spacing: 8) {
            Art(url: s.art, size: 30)
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
        // rows of five, so every pet fits inside the menu however many there are
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
        return GlassGroup {
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Species.allCases) { sp in
                    Tile(img: world.faceImage(sp), help: sp.title, selected: pet.species == sp, size: 48) { world.changeSpecies(to: sp); m.refresh() }
                }
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
        return GlassGroup { LazyVGrid(columns: grid, alignment: .leading, spacing: 6) {
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
        } }
    }

    func title(_ h: Hat) -> String {
        ["none": "No hat", "bow": "Bow", "flower": "Flower", "crown": "Crown", "topHat": "Top hat", "party": "Party hat",
         "witch": "Witch hat", "cowboy": "Cowboy hat", "santa": "Santa hat"][h.rawValue] ?? h.rawValue
    }
    func title(_ g: Glasses) -> String {
        ["none": "No glasses", "shades": "Shades", "hearts": "Heart glasses", "round": "Round glasses"][g.rawValue] ?? g.rawValue
    }
    func title(_ n: Neckwear) -> String {
        ["none": "Nothing", "scarf": "Scarf", "bowtie": "Bow tie", "bell": "Bell collar", "bandana": "Bandana"][n.rawValue] ?? n.rawValue
    }

    /// Three groups that fold away: the pet itself, what it connects to (each with a status and one control), the app.
    /// The menu's Settings: only the basics. Everything else is in the Advanced Settings window.
    func settingsTab(_ world: World) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Name") {
                TextField("Name", text: Binding(get: { m.editing ? m.draft : world.pet.name }, set: { m.draft = $0; m.editing = true }),
                          onCommit: { world.rename(m.draft); m.editing = false })
                    .textFieldStyle(.roundedBorder).frame(width: 130)
            }
            row("Size") {
                Picker("", selection: Binding(get: { world.sizeSetting }, set: { world.setSize($0); m.refresh() })) {
                    Text("S").tag(3); Text("M").tag(4); Text("L").tag(5)
                }
                .pickerStyle(.segmented).frame(width: 108)
            }
            row("Sounds") { toggle(Binding(get: { world.soundOn }, set: { world.setSound($0); m.refresh() })) }
            row("Gravity") { toggle(Binding(get: { world.gravity }, set: { world.setGravity($0); m.refresh() })) }
                .help("Off: your pet walks on every edge of the screen, and birds fly about")
            row("Water") {
                HStack(spacing: 2) {
                    Text("\(world.waterText(world.waterToday, unit: false)) / \(world.waterText(world.waterGoalML))")
                        .monospacedDigit().foregroundStyle(.secondary)
                    control("minus", 11) { world.undoWater(); m.refresh() }.disabled(world.waterToday == 0).help("Take one off")
                    control("plus", 11) { world.drankWater(); m.refresh() }.help("Add \(world.waterText(world.servingML))")
                }
            }
            .help("Goal, units and reminders are in Advanced Settings › Water")
            Button { world.openAdvanced() } label: { Label("Advanced Settings…", systemImage: "gearshape") }
                .buttonStyle(Pill()).fixedSize().padding(.top, 4)
                .help("Water, reminders, sleep, staying in place, following, sounds, calendar, music and the bell")
            HStack {
                Button(world.hidden ? "Show pet" : "Hide pet") { world.toggleHidden(); m.refresh() }.buttonStyle(Pill())
                    .help("⌃⌥P brings your pet back (or opens this menu)")
                Spacer()
                Button("Quit") { world.quit() }.buttonStyle(Pill())
            }
        }
    }

    // MARK: Advanced Settings panes (a standard settings window: a sidebar, and grouped forms)

    @ViewBuilder
    func pane(_ name: String, _ world: World) -> some View {
        switch name {
        case "Water": waterPane(world)
        case "Reminders": remindersPane(world)
        case "Sounds": soundsPane(world)
        case "Connections": connectionsPane(world)
        case "Behaviour": behaviourPane(world)
        default: generalPane(world)
        }
    }

    func caption(_ s: String) -> some View { Text(s).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }

    func save(_ world: World) { world.save(); m.refresh() }

    @ViewBuilder
    func behaviourPane(_ world: World) -> some View {
        Section("Sleep") {
            Picker("Naps by itself after", selection: Binding(get: { Int(world.sleepAfter) }, set: { world.sleepAfter = Double($0); save(world) })) {
                Text("1 minute").tag(60); Text("2 minutes").tag(120); Text("5 minutes").tag(300); Text("10 minutes").tag(600); Text("Never").tag(0)
            }
            Picker("Nap button sleeps", selection: Binding(get: { Int(world.napLength) }, set: { world.napLength = Double($0); save(world) })) {
                Text("Until I wake it").tag(0); Text("5 minutes").tag(300); Text("15 minutes").tag(900); Text("30 minutes").tag(1800); Text("1 hour").tag(3600)
            }
            Toggle("Music startles it awake", isOn: Binding(get: { world.startleOnMusic }, set: { world.startleOnMusic = $0; save(world) }))
            caption("Until I wake it: it sleeps through your typing until you press the nap button again. A timed nap ends by itself. Either way, music starting gives it a fright if the switch above is on.")
        }
        Section("Moving around") {
            Toggle("Gravity", isOn: Binding(get: { world.gravity }, set: { world.setGravity($0); m.refresh() }))
            Picker("In fullscreen apps", selection: Binding(get: { world.fullscreenClimb }, set: { world.fullscreenClimb = $0; save(world) })) {
                Text("Goes up to the top edge").tag(true); Text("Stays at the bottom").tag(false)
            }
            .help("Up: cats and dogs climb and hang upside down, birds fly up. Fullscreen videos always keep it in the black bar at the bottom.")
            Picker("Stay in place", selection: Binding(get: { world.stillness }, set: { world.stillness = $0; save(world) })) {
                Text("Off").tag(0); Text("Stays put, still grooms").tag(1); Text("Completely still").tag(2)
            }
            if world.stillness > 0 {
                Toggle("Types along with you", isOn: Binding(get: { world.stillTyping }, set: { world.stillTyping = $0; save(world) }))
                Toggle("Watches videos with you", isOn: Binding(get: { world.stillWatching }, set: { world.stillWatching = $0; save(world) }))
                Toggle("Listens to music", isOn: Binding(get: { world.stillMusic }, set: { world.stillMusic = $0; save(world) }))
            }
        }
        Section("Come here (the map pin)") {
            Picker("Speed", selection: Binding(get: { world.followSpeed }, set: { world.followSpeed = $0; save(world) })) {
                Text("Slow").tag(0); Text("Normal").tag(1); Text("Fast").tag(2)
            }
            .pickerStyle(.segmented)
            Picker("Follows for", selection: Binding(get: { Int(world.followFor) }, set: { world.followFor = Double($0); save(world) })) {
                Text("30 seconds").tag(30); Text("1 minute").tag(60); Text("5 minutes").tag(300); Text("Until I stop it").tag(0)
            }
            caption("Press the map pin again to stop it any time.")
        }
        Section("Extras") {
            Toggle("Name tag above the pet", isOn: Binding(get: { world.showName }, set: { world.showName = $0; save(world) }))
            Toggle("Double-click a snack or toy to put it away", isOn: Binding(get: { Item.doubleClickRemoves }, set: { Item.doubleClickRemoves = $0; save(world) }))
        }
    }

    /// Today's glass, how much, how you're doing against your day, and − / +.
    func waterToday(_ world: World) -> some View {
        let today = world.waterToday, goal = world.waterGoalML
        return HStack(spacing: 10) {
            Image(nsImage: waterGlassImage(Double(today) / Double(max(1, goal)))).interpolation(.none).resizable()
                .aspectRatio(contentMode: .fit).frame(height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(world.waterLine).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
                Text(world.paceText).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            // + adds a glass (or a sip); − takes one back if you pressed + by mistake
            control("minus", 12) { world.undoWater(); m.refresh() }.disabled(today == 0).help("Take one off")
            control("plus", 12) { world.drankWater(); m.refresh() }.help("Add \(world.waterText(world.servingML))")
        }
    }

    func minutesBinding(_ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(get()) * 60) },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); set((c.hour ?? 0) * 60 + (c.minute ?? 0)) })
    }

    @ViewBuilder
    func waterPane(_ world: World) -> some View {
        Section("Today") { waterToday(world) }
        waterHistorySection(world)
        Section("Your goal") {
            Picker("Daily goal", selection: Binding(get: { world.waterGoalMode }, set: { world.waterGoalMode = $0; save(world) })) {
                Text("One I set").tag(0); Text("Tailored to me").tag(1)
            }
            .pickerStyle(.segmented)
            if world.waterGoalMode == 0 {
                let step = world.waterUnit == .ml ? 100 : world.waterUnit == .oz ? 118 : world.servingML
                Stepper("\(world.waterText(world.fixedGoalML)) a day",
                        value: Binding(get: { world.fixedGoalML }, set: { world.fixedGoalML = max(500, min(6000, $0)); save(world) }), step: step)
            } else {
                let lb = world.weightInLB
                Stepper("Weight: \(lb ? Int((world.weightKG * 2.2046).rounded()) : Int(world.weightKG.rounded())) \(lb ? "lb" : "kg")",
                        value: Binding(get: { world.weightKG }, set: { world.weightKG = max(25, min(250, $0)); save(world) }), step: lb ? 0.4536 : 1)
                Picker("Weight in", selection: Binding(get: { world.weightInLB }, set: { world.weightInLB = $0; save(world) })) {
                    Text("kg").tag(false); Text("lb").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("How active you are", selection: Binding(get: { world.activity }, set: { world.activity = $0; save(world) })) {
                    Text("Light").tag(0); Text("Moderate").tag(1); Text("Very active").tag(2)
                }
                Toggle("Hot weather", isOn: Binding(get: { world.hotWeather }, set: { world.hotWeather = $0; save(world) }))
                LabeledContent("Your goal") {
                    Text(world.waterUnit == .ml ? world.waterText(world.tailoredGoalML)
                         : "\(world.waterText(world.tailoredGoalML)) (\(NumberFormatter.localizedString(from: NSNumber(value: world.tailoredGoalML), number: .decimal)) ml)")
                        .fontWeight(.semibold)
                }
                caption("About 33 ml per kg of body weight, plus more when you're active or it's hot. A rough guide, not medical advice.")
            }
        }
        Section("Counting") {
            Picker("Count in", selection: Binding(get: { world.waterUnit }, set: { world.waterUnit = $0; save(world) })) {
                Text("Glasses").tag(WaterUnit.glasses); Text("Sips").tag(WaterUnit.sips)
                Text("Millilitres").tag(WaterUnit.ml); Text("Ounces").tag(WaterUnit.oz)
            }
            Picker(world.waterUnit == .glasses ? "A glass is" : "Each + adds", selection: Binding(get: { world.glassML }, set: { world.glassML = $0; save(world) })) {
                ForEach([150, 200, 250, 300, 350, 400, 500], id: \.self) { ml in Text("\(ml) ml").tag(ml) }
            }
            .disabled(world.waterUnit == .sips)
            if world.waterUnit == .sips {
                Picker("A sip is", selection: Binding(get: { world.sipML }, set: { world.sipML = $0; save(world) })) {
                    ForEach([15, 20, 25, 30, 40], id: \.self) { ml in Text("\(ml) ml").tag(ml) }
                }
            }
        }
        Section {
            Picker("Remind me", selection: Binding(get: { Int(world.waterEvery) }, set: { world.setWater(Double($0)); m.refresh() })) {
                Text("Off").tag(0)
                Text("Adapts to my pace").tag(-1)
                Divider()
                Text("Every 15 minutes").tag(900); Text("Every 20 minutes").tag(1200); Text("Every 30 minutes").tag(1800)
                Text("Every 45 minutes").tag(2700); Text("Every hour").tag(3600); Text("Every 1½ hours").tag(5400)
                Text("Every 2 hours").tag(7200); Text("Every 3 hours").tag(10800)
            }
            Toggle("Only while I'm awake", isOn: Binding(get: { world.quietAtNight }, set: { world.quietAtNight = $0; save(world) }))
            DatePicker("I wake up at", selection: minutesBinding({ world.wakeMinutes }, { world.wakeMinutes = $0; save(world) }), displayedComponents: .hourAndMinute)
            DatePicker("I go to bed at", selection: minutesBinding({ world.bedMinutes }, { world.bedMinutes = $0; save(world) }), displayedComponents: .hourAndMinute)
        } header: {
            Text("Reminders")
        } footer: {
            caption("Adapts to my pace spreads your goal over your waking hours: it reminds you more often when you fall behind and stays quiet while you're ahead. Reminders count only the time you're at your computer and stop once you reach your goal.\n\nYour water day runs from 4 AM to 4 AM, so a drink after midnight still counts for the day you're in. The chart keeps every day.")
        }
    }

    /// Water per day over the last week or month, the goal as a line, and a few numbers (in your unit).
    @ViewBuilder
    func waterHistorySection(_ world: World) -> some View {
        let goalML = world.waterGoalML, h = world.waterHistory, cal = Calendar.current
        let days = (0..<m.waterDays).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: World.waterNow)) }
        let mls = days.map { h[World.isoDay($0)] ?? 0 }
        let values = mls.map { world.waterValue($0) }, goal = world.waterValue(goalML)
        let blue = Color(red: 0.24, green: 0.61, blue: 0.94)
        // days in a row at the goal, up to today (today doesn't break it while it's still going)
        let streak: Int = {
            var n = 0
            for (i, v) in mls.enumerated().reversed() {
                if v >= goalML { n += 1 } else if i == mls.count - 1 { continue } else { break }
            }
            return n
        }()
        let logged = mls.filter { $0 > 0 }
        Section("History") {
            Picker("", selection: $m.waterDays) { Text("Week").tag(7); Text("Month").tag(30) }
                .pickerStyle(.segmented).labelsHidden()
            Chart {
                ForEach(Array(zip(days, values)), id: \.0) { d, v in
                    BarMark(x: .value("Day", d, unit: .day), y: .value("Water", v))
                        .foregroundStyle(v >= goal ? blue : blue.opacity(0.45))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) { Text("Goal").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            .chartXAxis {
                if m.waterDays == 7 {
                    AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) }
                } else {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
                }
            }
            .chartYScale(domain: 0...max(goal * 1.15, (values.max() ?? 0) * 1.1, 1))
            .frame(height: 150)
            HStack {
                stat(logged.isEmpty ? "–" : world.waterText(logged.reduce(0, +) / logged.count), "a day on average")
                Spacer()
                stat("\(mls.filter { $0 >= goalML }.count) of \(m.waterDays)", "days at your goal")
                Spacer()
                stat("\(streak)", "day streak")
            }
        }
    }

    func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func remindersPane(_ world: World) -> some View {
        Section("Your reminders") {
            if world.habits.isEmpty { caption("Add your own, like stretching, vitamins or a walk. Your pet tells you when it's time.") }
            ForEach(world.habits) { h in
                HStack(spacing: 8) {
                    Image(systemName: "checklist").foregroundStyle(Color.accentColor).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.text).lineLimit(1)
                        Text(h.label).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { world.removeHabit(h.id); m.refresh() } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("Delete this reminder")
                }
            }
        }
        Section("New reminder") {
            TextField("What", text: $m.habitText, prompt: Text("Stretch, drink tea, take vitamins..."))
            Picker("When", selection: $m.habitEvery) {
                Text("Every day at a time").tag(0); Text("Every 30 minutes").tag(1800); Text("Every hour").tag(3600); Text("Every 2 hours").tag(7200)
            }
            if m.habitEvery == 0 { DatePicker("Time", selection: $m.habitTime, displayedComponents: .hourAndMinute) }
            HStack {
                Spacer()
                Button("Add Reminder") {
                    let text = m.habitText.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    let c = Calendar.current.dateComponents([.hour, .minute], from: m.habitTime)
                    world.addHabit(Habit(text: text, every: Double(m.habitEvery), hour: c.hour ?? 9, minute: c.minute ?? 0))
                    m.habitText = ""
                    m.refresh()
                }
                .disabled(m.habitText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    func soundsPane(_ world: World) -> some View {
        Section {
            Toggle("Sounds", isOn: Binding(get: { world.soundOn }, set: { world.setSound($0); m.refresh() }))
        }
        Section("Volume") {
            volumeRow(world, "all", "All sounds", sample: "pop")
            ForEach(Synth.categories, id: \.key) { c in
                volumeRow(world, c.key, c.name, sample: ["voice": world.pet.species.vocal.sound, "purr": "purr", "chime": "chime",
                                                          "eating": "chomp", "toys": "boing"][c.key] ?? "pop")
            }
        }
        .disabled(!world.soundOn)
    }

    /// A volume slider that plays its sound when you let go, so you hear the new level.
    func volumeRow(_ world: World, _ key: String, _ name: String, sample: String) -> some View {
        LabeledContent(name) {
            Slider(value: Binding(get: { world.volumes[key] ?? 1 }, set: { world.setVolume($0, for: key) }), in: 0...1,
                   onEditingChanged: { editing in if !editing { world.synth.play(sample) } })
                .frame(width: 180)
        }
    }

    @ViewBuilder
    func connectionsPane(_ world: World) -> some View {
        Section {
                calendar(world)
                connection("music.note", "Music",
                           world.player.running ? "Playing in \(world.player.appName)" : "Works with every player, nothing to sign in to") {
                    EmptyView()
                }
                // what each kind of player needs (only Spotify's queue and search need an account)
                if world.player.spotifyInstalled {
                    source("dot.radiowaves.left.and.right", "Spotify") {
                        if world.player.connected {
                            status("Queue and search on")
                            Button("Disconnect") { world.player.disconnect(); m.refresh() }.buttonStyle(Pill())
                        }
                        else { Button("Add queue") { m.tab = 2; m.spotifySetup = true; world.closeAdvanced() }.buttonStyle(Pill()).help("Optional: connect your Spotify account to see and add to your queue") }
                    }
                }
                source("music.note.list", "Apple Music") { status("Ready") }
                source("speaker.wave.2", "Any other player") {
                    if world.trusted { status("Media keys") }
                    else { Button("Allow") { world.requestAccessibility() }.buttonStyle(Pill()).help("Play and skip in any player need Accessibility") }
                }
                .help("YouTube Music, Tidal, VLC, a music site in your browser...")
                connection("bell", "Notification bell",
                           !world.bellOn ? "Off" : world.trusted ? "Every app" + (world.bellTabs ? " and browser tabs" : "") : (world.bellTabs ? "Browser tabs only for now" : "Waiting for Accessibility")) {
                    toggle(Binding(get: { world.bellOn }, set: { world.setBell($0); m.refresh() }))
                }
                if world.bellOn {
                    row("   Browser tabs") { toggle(Binding(get: { world.bellTabs }, set: { world.setBellTabs($0); m.refresh() })) }
                        .help("Rings when a tab's title shows new messages, like \"(2) Discord\"")
                }
                if !world.trusted {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        hint("Every app's notifications, and play/pause for any music player, need Accessibility: switch on Pocket Pet in Privacy & Security › Accessibility (it asks for an admin password on a Mac you're not an admin of). Already on? That switch belongs to an older copy: select Pocket Pet, click −, then add it again with +.")
                        Button("Open") { world.requestAccessibility() }.buttonStyle(Pill(strong: true)).fixedSize()
                    }
                }
            
        }
    }

    @ViewBuilder
    func generalPane(_ world: World) -> some View {
        // the same basics as the menu's Settings
        Section("Your pet") {
            TextField("Name", text: Binding(get: { m.editing ? m.draft : world.pet.name }, set: { m.draft = $0; m.editing = true }))
                .onSubmit { world.rename(m.draft); m.editing = false; m.refresh() }       // saved on Return, so it doesn't announce every letter
            Picker("Size", selection: Binding(get: { world.sizeSetting }, set: { world.setSize($0); m.refresh() })) {
                Text("Small").tag(3); Text("Medium").tag(4); Text("Large").tag(5)
            }
            .pickerStyle(.segmented)
            Toggle("Sounds", isOn: Binding(get: { world.soundOn }, set: { world.setSound($0); m.refresh() }))
            Toggle("Gravity", isOn: Binding(get: { world.gravity }, set: { world.setGravity($0); m.refresh() }))
        }
        Section("App") {
            Toggle("Open at login", isOn: Binding(get: { world.openAtLogin }, set: { world.openAtLogin = $0; m.refresh() }))
            if world.updater.enabled { updatesRow(world) }
        }
        Section {
            HStack {
                Button(world.hidden ? "Show Pet" : "Hide Pet") { world.toggleHidden(); m.refresh() }
                Spacer()
                Button("Quit Pocket Pet") { world.quit() }
            }
        } footer: {
            caption("⌃⌥P brings your pet back, or opens its menu.")
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
        let hasMac = mac.authorized && !mac.accounts.isEmpty
        let allIn = g.signedIn && ics.connected && hasMac
        VStack(alignment: .leading, spacing: 6) {
            connection("calendar", "Calendar", calendarStatus(world)) {
                if !allIn {
                    let label = m.calWay != 0 ? "Close" : world.calendarConnected ? "Add" : "Set up"
                    Button(label) { m.calWay = m.calWay != 0 ? 0 : !ics.connected ? 1 : !hasMac ? 2 : 3 }
                        .buttonStyle(Pill(strong: m.calWay == 0 && !world.calendarConnected))
                }
            }
            // every connected source, shown together and removable one by one
            if ics.connected { source("link", "Private calendar link") { Button("Remove") { ics.disconnect(); m.refresh() }.buttonStyle(Pill()) } }
            if g.signedIn { source("person.crop.circle", g.email.isEmpty ? "Google" : g.email) { Button("Sign out") { g.signOut(); m.refresh() }.buttonStyle(Pill()) } }
            if hasMac {
                source("desktopcomputer", "This Mac: " + mac.accounts.joined(separator: ", ")) {
                    toggle(Binding(get: { world.useMacCalendar }, set: { world.useMacCalendar = $0; world.save(); m.refresh() }))
                }
            }
            if m.calWay != 0 && !allIn {
                // the ways not used yet, easiest first
                HStack(spacing: 6) {
                    if !ics.connected { way("Paste a link", 1) }
                    if !hasMac { way("This Mac", 2) }
                    if !g.signedIn { way("Google sign-in", 3) }
                }
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
        let n = [world.ics.connected, world.google.signedIn, world.macCalendarOn].filter { $0 }.count
        return n == 0 ? "Google, Outlook, iCloud or Mac" : n == 1 ? "1 calendar source" : "\(n) sources, shown together"
    }

    func status(_ s: String) -> some View { Text(s).foregroundStyle(.secondary).font(.system(size: 10.5)) }

    /// One connected source (a calendar, a kind of music player), indented under its row.
    func source<C: View>(_ icon: String, _ title: String, @ViewBuilder _ trailing: () -> C) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 14)
            Text(title).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.leading, 22)
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
                else { mac.connect { ok in if ok && mac.accounts.isEmpty { MacCalendar.openInternetAccounts() } else if ok { m.calWay = 0 }; m.refresh() } }
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
                if g.hasClient { Button("Sign in") { g.signIn { ok in if ok { m.calWay = 0 }; m.refresh() }; m.refresh() }.buttonStyle(Pill(strong: true)) }
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

    /// A picture under a made-up address (the README's sample cover).
    static func put(_ url: String, _ img: NSImage) { cache.setObject(img, forKey: url as NSString) }

    static func prefetch(_ urls: [String?]) { for u in urls.compactMap({ $0 }) where cached(u) == nil { load(u) { _ in } } }
}

struct Art: View {
    let url: String?
    let size: CGFloat
    @State private var loaded: (url: String, image: NSImage)?
    @State private var retried: String?          // a cover that failed to download gets one more go

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
        // only ever this song's own cover: a picture loaded for another address isn't shown
        let img = url.flatMap { u in loaded?.url == u ? loaded?.image : ArtCache.cached(u) }
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
        guard let url, ArtCache.cached(url) == nil, loaded?.url != url else { return }
        ArtCache.load(url) { img in
            guard let img else {
                if retried != url { retried = url; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { load() } }
                return
            }
            guard url == self.url else { return }
            withAnimation(.easeOut(duration: 0.2)) { loaded = (url, img) }
        }
    }
}
