// Every calendar this Mac already has (iCloud, Outlook/Exchange, Google and any account added in System Settings →
// Internet Accounts), read through macOS (EventKit). No setup beyond allowing access once.

import Cocoa
import EventKit

final class MacCalendar {
    private let store = EKEventStore()
    private(set) var events: [CalEvent] = []
    /// Events from the calendars picked for "Due soon" (Google Classroom's class calendars, a homework calendar...), a week ahead.
    private(set) var dueEvents: [CalEvent] = []
    /// Which calendars feed "Due soon" ("mac:" + the calendar's identifier); they're left out of the day's agenda.
    var dueIDs: Set<String> = []

    var authorized: Bool {
        if #available(macOS 14.0, *) { return EKEventStore.authorizationStatus(for: .event) == .fullAccess }
        return EKEventStore.authorizationStatus(for: .event) == .authorized
    }

    /// Where this Mac's calendars come from (iCloud, an Exchange or Google account...), for the menu.
    var accounts: [String] {
        guard authorized else { return [] }
        var seen = Set<String>()
        return store.calendars(for: .event).map { $0.source.title }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Every calendar on this Mac, for the "Due soon" picker: id, name and the account it belongs to.
    var calendars: [PickableCalendar] {
        guard authorized else { return [] }
        return store.calendars(for: .event).map { PickableCalendar(id: "mac:" + $0.calendarIdentifier, title: $0.title, account: $0.source.title) }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func connect(_ done: @escaping (Bool) -> Void) {
        let finish: (Bool) -> Void = { ok in
            DispatchQueue.main.async {
                if ok { self.refresh() }
                done(ok)
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { ok, _ in finish(ok) }
        } else {
            store.requestAccess(to: .event) { ok, _ in finish(ok) }
        }
    }

    /// Read off the main thread: with many calendar accounts this can take a while, and the app mustn't freeze.
    private let readQ = DispatchQueue(label: "pocketpet.maccalendar", qos: .userInitiated)

    func refresh(_ done: (() -> Void)? = nil) {
        guard authorized else { done?(); return }
        let store = self.store, due = dueIDs
        readQ.async { [weak self] in
            store.refreshSourcesIfNecessary()
            let start = Calendar.current.startOfDay(for: Date())
            let all = store.calendars(for: .event)
            let picked = all.filter { due.contains("mac:" + $0.calendarIdentifier) }
            let rest = all.filter { !due.contains("mac:" + $0.calendarIdentifier) }
            func read(_ cals: [EKCalendar], days: Double) -> [CalEvent] {
                guard !cals.isEmpty else { return [] }      // an empty list would mean every calendar
                let pred = store.predicateForEvents(withStart: start, end: start.addingTimeInterval(days * 86400), calendars: cals)
                return store.events(matching: pred).map {
                    // a repeating event shares one identifier, so its date keeps each one apart
                    CalEvent(id: ($0.eventIdentifier ?? UUID().uuidString) + "@\(Int($0.startDate.timeIntervalSince1970))",
                             title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay, location: $0.location)
                }.sorted { $0.start < $1.start }
            }
            let found = read(rest, days: 2), tasks = read(picked, days: 8)
            DispatchQueue.main.async { self?.events = found; self?.dueEvents = tasks; done?() }
        }
    }

    static func openInternetAccounts() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
    }
}

/// A calendar you can pick for "Due soon", from this Mac or a Google sign-in.
struct PickableCalendar: Identifiable {
    let id: String          // "mac:…" or "google:…"
    let title: String
    let account: String
}
