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
    @ViewBuilder func card() -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if plainGlass {
            self.background(shape.fill(Color(nsColor: .windowBackgroundColor)))
        } else if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
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
            // search and play, right here
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Search and play", text: $query, onCommit: { sp.quickSearch(query) }).textFieldStyle(.plain).font(.system(size: 12))
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
                        }
                    }
                }
                .frame(maxHeight: 160)
            } else if !sp.status.isEmpty {
                Text(sp.status).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 250)
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

/// A borderless glass window by the pet that takes clicks without stealing focus from your app.
final class FloatingCard {
    private var panel: NSPanel?
    private var generation = 0          // a fade-out finishing late must not hide a card that was shown again
    var until = 0.0
    var onClose: (() -> Void)?

    var visible: Bool { panel?.isVisible ?? false }
    var frame: NSRect { panel?.frame ?? .zero }

    /// Shows `view` next to `tip` (the top of the pet's head); `below` when the pet hangs from the top of the screen.
    func show<V: View>(_ view: V, tip: CGPoint, below: Bool, until: Double) {
        self.until = until
        generation += 1
        let host = ClickHostingView(rootView: view)
        let size = host.fittingSize
        let p = panel ?? makePanel()
        panel = p
        p.contentView = host
        let vf = (NSScreen.screens.first { $0.frame.contains(tip) } ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = clamp(tip.x - size.width / 2, vf.minX + 8, max(vf.minX + 8, vf.maxX - size.width - 8))
        let y = clamp(below ? tip.y - size.height - 10 : tip.y + 10, vf.minY + 8, max(vf.minY + 8, vf.maxY - size.height - 8))
        p.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height), display: true)
        if !p.isVisible { p.alphaValue = 0; p.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
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
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isReleasedWhenClosed = false
        return p
    }
}
