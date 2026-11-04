// Glass cards that pop up by the pet: the agenda (double-click) and the music controls (click while music plays).
// The pixel speech bubble is too small for a whole school day or a song title, so these use plain readable text.

import SwiftUI

struct AgendaRow: Identifiable {
    let id: String
    let time: String
    let title: String
    var until: String?          // set while it's happening
    var place: String?          // where: the room, or "Online"
}

struct Agenda {
    var date = ""
    var rows: [AgendaRow] = []
    var more = 0
    var allDay: [String] = []
    var empty: String?          // "Nothing else today"
    var tomorrow: [AgendaRow] = []

    var lineCount: Int { rows.count + tomorrow.count + (allDay.isEmpty ? 0 : 1) }

    static func build(_ events: [CalEvent], now: Date = Date()) -> Agenda {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now), tomorrow = today.addingTimeInterval(86400), after = tomorrow.addingTimeInterval(86400)
        func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
        func clean(_ s: String) -> String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? "Event" : t }
        func place(_ e: CalEvent) -> String? { Agenda.place(e.location) }
        var a = Agenda()
        a.date = now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let left = events.filter { !$0.allDay && $0.end > now && $0.start < tomorrow }
        a.rows = left.prefix(7).map { e in
            AgendaRow(id: e.id, time: e.start <= now ? "Now" : time(e.start), title: clean(e.title),
                      until: e.start <= now ? "till " + time(e.end) : nil, place: place(e))
        }
        a.more = max(0, left.count - 7)
        a.allDay = events.filter { $0.allDay && $0.start < tomorrow && $0.end > today }.map { clean($0.title) }
        if a.rows.isEmpty {
            a.empty = events.contains { !$0.allDay && $0.start >= today && $0.start < tomorrow } ? "Nothing else today" : "Nothing on today"
        }
        // a peek at tomorrow when today is nearly done
        if a.rows.count < 3 {
            a.tomorrow = events.filter { !$0.allDay && $0.start >= tomorrow && $0.start < after }.prefix(3 - a.rows.count)
                .map { AgendaRow(id: $0.id, time: time($0.start), title: clean($0.title), place: place($0)) }
        }
        return a
    }

    /// A tidy location: links become "Online", long addresses keep their first part.
    static func place(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("http") || s.contains("zoom.us") || s.contains("meet.google") || s.contains("teams.microsoft") { return "Online" }
        if s.count > 28, let comma = s.firstIndex(of: ",") { s = String(s[..<comma]) }
        return s
    }
}

struct AgendaView: View {
    let agenda: Agenda
    var close: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(agenda.date).font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "calendar").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !agenda.allDay.isEmpty {
                Text(agenda.allDay.joined(separator: "  ·  "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            if let empty = agenda.empty {
                Text(empty).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(agenda.rows) { row($0) }
            if agenda.more > 0 {
                Text("+\(agenda.more) more").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !agenda.tomorrow.isEmpty {
                Divider().opacity(0.5)
                Text("Tomorrow").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                ForEach(agenda.tomorrow) { row($0) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: 270, alignment: .leading)
        .card()
        .contentShape(Rectangle())
        .onTapGesture { close() }
    }

    func row(_ r: AgendaRow) -> some View {
        let now = r.until != nil
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(r.time)
                .font(.system(size: 11.5, weight: now ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(now ? .primary : .secondary)
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title).font(.system(size: 12.5, weight: now ? .semibold : .regular)).lineLimit(1).truncationMode(.tail)
                if let p = r.place {
                    Label(p, systemImage: p == "Online" ? "video" : "mappin").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                        .labelStyle(TightLabel())
                }
            }
            Spacer(minLength: 0)
            if let until = r.until { Text(until).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize() }
        }
    }
}

/// Icon and text close together, for the small location line.
struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.font(.system(size: 9)); configuration.title }
    }
}

extension View {
    /// A floating glass card: Liquid Glass on macOS 26, frosted material before.
    /// The cards' look: the same material as the menu's popover, kept in its bright "active" look (a card's window is
    /// never the focused one, so glass on it was drawn dimmed and grey), with a faint edge and a soft shadow in the
    /// card's own rounded shape (the window has no shadow of its own, which macOS drew square).
    @ViewBuilder func card() -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if plainGlass {
            self.background(shape.fill(Color(nsColor: .windowBackgroundColor)))
        } else {
            self.background(PopoverMaterial(cornerRadius: 16))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 5)
        }
    }
}

/// The menu's popover material behind a card, always drawn active, with rounded corners.
struct PopoverMaterial: NSViewRepresentable {
    var cornerRadius: CGFloat
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.layer?.cornerRadius = cornerRadius }
}

/// Can take typing (for the search box) without activating the app.
private final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Clicks land straight away instead of only focusing the card.
private final class ClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Mini player shown when you click the pet while music plays.
final class MusicCardModel: ObservableObject {
    @Published var tick = 0
}

struct MusicCardView: View {
    let player: MusicPlayer
    @ObservedObject var model: MusicCardModel
    @State private var query = ""
    @State private var searching = false      // the search opens from the magnifying glass, and closes again
    @FocusState private var typing: Bool

    var body: some View {
        let sp = player
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Art(url: sp.song?.art, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sp.song?.name ?? "Playing in \(sp.appName)").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(sp.song?.artist ?? "").font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    searching.toggle()
                    if searching { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { typing = true } }
                    else { query = ""; sp.clearResults() }
                    model.tick &+= 1
                } label: {
                    Image(systemName: searching ? "xmark" : "magnifyingglass").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(searching ? "Close search" : "Search and play")
            }
            // only ticks while playing, and only while the card is up
            TimelineView(.periodic(from: .now, by: sp.playing ? 1 : 3600)) { _ in
                let dur = sp.song?.duration ?? 0, at = sp.elapsed
                VStack(spacing: 3) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.12))
                            Capsule().fill(Color.accentColor).frame(width: dur > 0 ? g.size.width * min(1, at / dur) : 0)
                        }
                    }
                    .frame(height: 3)
                    HStack {
                        Text(clock(at)); Spacer(); Text(clock(dur))
                    }
                    .font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 0) {
                if sp.full { button("shuffle", 12, on: sp.shuffle) { sp.setShuffle(!sp.shuffle) } }
                Spacer()
                button("backward.fill", 14) { sp.previous() }
                button(sp.playing ? "pause.fill" : "play.fill", 20) { sp.playPause() }
                button("forward.fill", 14) { sp.next() }
                Spacer()
                if sp.full { button("repeat", 12, on: sp.repeating) { sp.setRepeat(!sp.repeating) } }
            }
            // search and play, right here (when you open it)
            if searching || plainGlass {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                if plainGlass {         // pictures for the README: a text field can't be drawn offscreen
                    Text("Search and play").font(.system(size: 12)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Search and play", text: $query, onCommit: { sp.quickSearch(query) }).textFieldStyle(.plain).font(.system(size: 12))
                        .focused($typing)
                }
                if !query.isEmpty {
                    Button { query = ""; sp.clearResults() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.07)))
            if !sp.results.isEmpty {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(sp.results) { s in
                            HStack(spacing: 4) {
                                // the song itself plays this song now; + puts it in the queue instead
                                Button { sp.play(s); query = ""; sp.clearResults() } label: {
                                    HStack(spacing: 8) {
                                        Art(url: s.art, size: 26)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(s.name).font(.system(size: 11.5)).lineLimit(1)
                                            Text(s.artist).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Play this song now")
                                if sp.connected && !s.id.hasPrefix("music:") {
                                    Button { sp.addToQueue(s); model.tick &+= 1 } label: {
                                        Image(systemName: "plus").font(.system(size: 12)).frame(width: 24, height: 24).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Add to queue")
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
            } else if !sp.status.isEmpty {
                Text(sp.status).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            }
        }
        .padding(14)
        .frame(width: 262)
        .card()
    }

    func clock(_ s: Double) -> String { let n = Int(max(0, s)); return "\(n / 60):" + String(format: "%02d", n % 60) }

    func button(_ symbol: String, _ size: CGFloat, on: Bool? = nil, _ action: @escaping () -> Void) -> some View {
        Button { action(); model.tick &+= 1 } label: {
            Image(systemName: symbol).font(.system(size: size))
                .foregroundStyle(on == false ? .secondary : .primary)
                .frame(width: 34, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The bell: who wants you, ringing for a moment. Tap it to go there.
struct BellView: View {
    let bell: NSImage
    let title: String
    let detail: String
    var open: () -> Void = {}
    @State private var swing = false
    @State private var still = false

    var body: some View {
        HStack(spacing: 10) {
            Pixel(img: bell).frame(width: 22, height: 22)
                .rotationEffect(.degrees(still ? 0 : (swing ? 16 : -16)), anchor: .top)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Image(systemName: "arrow.up.forward").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: 240)
        .card()
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.12).repeatCount(15, autoreverses: true)) { swing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { withAnimation(.easeOut(duration: 0.2)) { still = true } }
        }
    }
}

/// A short note by the pet, e.g. how to bring it back after hiding it. Tap to dismiss.
struct ToastView: View {
    let title: String
    let detail: String
    var close: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12.5, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .frame(width: 240, alignment: .leading)
        .card()
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
    }
}

/// A yes/no question by the pet (e.g. "Sharing your screen? Hide?").
struct AskView: View {
    let title: String
    let detail: String
    let yes: String, no: String
    var answer: (Bool) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Spacer()
                Button(no) { answer(false) }.buttonStyle(Pill())
                Button(yes) { answer(true) }.buttonStyle(Pill(strong: true))
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(width: 240, alignment: .leading)
        .card()
    }
}

/// One of your own reminders, by the pet.
struct HabitView: View {
    let text: String
    let schedule: String
    var answer: (Bool) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checklist").font(.system(size: 18)).foregroundStyle(Color.accentColor).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text).font(.system(size: 12.5, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(schedule).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Spacer()
                Button("Later") { answer(false) }.buttonStyle(Pill())
                Button("Done") { answer(true) }.buttonStyle(Pill(strong: true))
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(width: 240, alignment: .leading)
        .card()
    }
}

/// The pet's name above it, when switched on in Settings.
struct NameTagView: View {
    let name: String
    var body: some View {
        Text(name).font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

/// The water reminder: a pixel glass that fills up over the day, how you're doing, and two answers. After "I drank
/// some" it shows the glass fuller for a moment, then closes.
struct WaterView: View {
    let title: String
    let line: String                    // "3 of 8 glasses today", "750 of 2,000 ml today"
    let progress: Double
    var dots: (Int, Int)? = nil         // glasses had and goal, drawn as dots when they fit
    var pace = ""
    var drink = "I drank some"
    var done = false
    var answer: (Bool) -> Void = { _ in }

    var body: some View {
        let blue = Color(red: 0.24, green: 0.61, blue: 0.94)
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: waterGlassImage(progress))
                .interpolation(.none)
                .transition(.scale.combined(with: .opacity))
                .id(Int(progress * 100))
            VStack(alignment: .leading, spacing: 6) {
                Text(done ? (progress >= 1 ? "Goal reached!" : "Nice, keep it up!") : title).font(.system(size: 12.5, weight: .semibold))
                Text(line).font(.system(size: 11)).foregroundStyle(.secondary)
                if let (had, goal) = dots {
                    HStack(spacing: 3) {
                        ForEach(0..<goal, id: \.self) { i in
                            Capsule().fill(i < had ? blue : Color.primary.opacity(0.12)).frame(width: max(6, 112 / CGFloat(goal) - 3), height: 4)
                        }
                    }
                } else {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.12))
                            Capsule().fill(blue).frame(width: g.size.width * min(1, progress))
                        }
                    }
                    .frame(width: 140, height: 4)
                }
                if !pace.isEmpty && !done { Text(pace).font(.system(size: 10.5)).foregroundStyle(.secondary) }
                if !done {
                    HStack(spacing: 6) {
                        Button("Later") { answer(false) }.buttonStyle(Pill())
                        Button(drink) { answer(true) }.buttonStyle(Pill(strong: true))
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(width: 262, alignment: .leading)
        .card()
    }
}

/// A borderless glass window by the pet that takes clicks without stealing focus from your app.
final class FloatingCard {
    private var panel: NSPanel?
    private var generation = 0          // a fade-out finishing late must not hide a card that was shown again
    var until = 0.0
    var onClose: (() -> Void)?
    var clickThrough = false            // the name tag: the mouse goes right through it

    var visible: Bool { panel?.isVisible ?? false }
    /// The card itself, inside the window's margin (the margin leaves room for its shadow).
    var frame: NSRect { (panel?.frame ?? .zero).insetBy(dx: Self.margin, dy: Self.margin) }
    static let margin: CGFloat = 18

    /// Shows `view` next to `tip` (the top of the pet's head); `below` when the pet hangs from the top of the screen.
    func show<V: View>(_ view: V, tip: CGPoint, below: Bool, until: Double) {
        self.until = until
        generation += 1
        let host = ClickHostingView(rootView: view.padding(Self.margin))
        let size = host.fittingSize
        let p = panel ?? makePanel()
        panel = p
        p.contentView = host
        p.setFrame(frame(for: size, tip: tip, below: below), display: true)
        lastTip = (tip, below)
        if !p.isVisible { p.alphaValue = 0; p.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
    }

    /// Keeps the card next to the pet while it moves (or you drag it): only moves the window, nothing is redrawn.
    func follow(tip: CGPoint, below: Bool) {
        guard let p = panel, p.isVisible, let last = lastTip,
              abs(last.tip.x - tip.x) >= 1 || abs(last.tip.y - tip.y) >= 1 || last.below != below else { return }
        lastTip = (tip, below)
        p.setFrameOrigin(frame(for: p.frame.size, tip: tip, below: below).origin)
    }

    private var lastTip: (tip: CGPoint, below: Bool)?

    /// The window for a card of `size` (margin included): the card itself sits just above (or below) the tip.
    private func frame(for size: CGSize, tip: CGPoint, below: Bool) -> NSRect {
        let vf = (NSScreen.screens.first { $0.frame.contains(tip) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let m = Self.margin, edge = 8 - m
        let x = clamp(tip.x - size.width / 2, vf.minX + edge, max(vf.minX + edge, vf.maxX - size.width - edge))
        let y = clamp(below ? tip.y - size.height - 10 + m : tip.y + 10 - m, vf.minY + edge, max(vf.minY + edge, vf.maxY - size.height - edge))
        return NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    func hide() {
        guard let p = panel, p.isVisible else { return }
        onClose?()
        generation += 1
        let g = generation
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.08; p.animator().alphaValue = 0 }, completionHandler: { [weak self] in
            guard self?.generation == g else { return }
            p.orderOut(nil)
            p.contentView = nil
        })
    }

    var isKey: Bool { panel?.isKeyWindow ?? false }

    private func makePanel() -> NSPanel {
        let p = CardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.becomesKeyOnlyIfNeeded = true        // takes the keyboard only for a text field (the music search), never your app's focus otherwise
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false                    // the glass card draws its own edge; a window shadow turned square when tapped
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = clickThrough
        return p
    }
}
