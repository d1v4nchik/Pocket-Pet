// Every calendar this Mac already has (iCloud, Outlook/Exchange, Google and any account added in System Settings →
// Internet Accounts), read through macOS (EventKit). No setup beyond allowing access once.

import Cocoa
import EventKit

final class MacCalendar {
    private let store = EKEventStore()
    private(set) var events: [CalEvent] = []

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

    func refresh() {
        guard authorized else { return }
        store.refreshSourcesIfNecessary()
        let start = Calendar.current.startOfDay(for: Date())
        let pred = store.predicateForEvents(withStart: start, end: start.addingTimeInterval(2 * 86400), calendars: nil)
        events = store.events(matching: pred).map {
            CalEvent(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Event",
                     start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay, location: $0.location)
        }.sorted { $0.start < $1.start }
    }

    static func openInternetAccounts() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
    }
}
