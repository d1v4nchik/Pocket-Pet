// Google Calendar from its private link ("Secret address in iCal format"): no sign-in, no setup.
// Fetches the .ics feed and works out today's and tomorrow's events, including repeating ones.

import Foundation

final class ICSCalendar {
    private(set) var events: [CalEvent] = []
    private(set) var lastFetch = Date.distantPast
    var status = ""
    private var url: String?

    var connected: Bool { url != nil }

    /// After `Secrets.load()`.
    func loadSecrets() {
        url = Secrets.get("icsURL")
    }

    /// Accepts the link copied from Google Calendar (https://… or webcal://…, ending in .ics).
    func setLink(_ raw: String, _ done: @escaping (Bool) -> Void) {
        var link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.hasPrefix("webcal://") { link = "https://" + link.dropFirst("webcal://".count) }
        guard link.hasPrefix("https://"), URL(string: link) != nil else {
            status = "That doesn't look like a calendar link"
            done(false)
            return
        }
        url = link
        status = "Checking…"
        refresh { [weak self] in
            guard let self else { return }
            if self.lastFetch == .distantPast {
                self.url = nil
                self.status = "Couldn't read that link. Copy the “Secret address in iCal format”."
                done(false)
            } else {
                Secrets.set(link, "icsURL")
                self.status = ""
                done(true)
            }
        }
    }

    func disconnect() {
        url = nil
        events = []
        lastFetch = .distantPast
        Secrets.set(nil, "icsURL")
    }

    func refresh(_ done: (() -> Void)?) {
        guard let link = url, let u = URL(string: link) else { done?(); return }
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            let text = ok ? data.flatMap { String(data: $0, encoding: .utf8) } : nil
            let evs = text.flatMap { $0.contains("BEGIN:VCALENDAR") ? ICSCalendar.parse($0) : nil }
            DispatchQueue.main.async {
                guard let self else { return }
                if let evs {
                    self.events = evs
                    self.lastFetch = Date()
                }
                done?()
            }
        }.resume()
    }

    // MARK: Parsing

    private struct Rule {
        var freq = "", interval = 1, count: Int?, until: Date?
        var byDay: [(Int, Int)] = []      // (nth or 0, weekday 1=Sunday)
        var byMonthDay: [Int] = []
    }

    private struct VEvent {
        var uid = "", summary = "Event", location: String?, start: Date?, end: Date?, allDay = false, tz = TimeZone.current
        var rule: Rule?, exdates: [Date] = [], recurrenceID: Date?, cancelled = false
    }

    /// Events overlapping today and tomorrow.
    static func parse(_ text: String) -> [CalEvent] {
        let cal = Calendar.current
        let winStart = cal.startOfDay(for: Date())
        let winEnd = winStart.addingTimeInterval(2 * 86400)

        // unfold continued lines
        var lines: [String] = []
        for raw in text.components(separatedBy: CharacterSet.newlines) where !raw.isEmpty {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty { lines[lines.count - 1] += raw.dropFirst() }
            else { lines.append(raw) }
        }

        let dates = Dates()
        var all: [VEvent] = []
        var cur: VEvent?
        for line in lines {
            if line == "BEGIN:VEVENT" { cur = VEvent(); continue }
            if line == "END:VEVENT" { if let e = cur { all.append(e) }; cur = nil; continue }
            guard cur != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon], value = String(line[line.index(after: colon)...])
            let parts = head.split(separator: ";").map(String.init)
            let name = parts.first?.uppercased() ?? ""
            var params: [String: String] = [:]
            for p in parts.dropFirst() {
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { params[kv[0].uppercased()] = kv[1] }
            }
            switch name {
            case "UID": cur!.uid = value
            case "SUMMARY": cur!.summary = unescape(value)
            case "LOCATION": cur!.location = unescape(value)
            case "DTSTART":
                if let (d, allDay, tz) = dates.parse(value, params) { cur!.start = d; cur!.allDay = allDay; cur!.tz = tz }
            case "DTEND":
                cur!.end = dates.parse(value, params)?.0
            case "RRULE": cur!.rule = parseRule(value, dates)
            case "EXDATE": cur!.exdates += value.split(separator: ",").compactMap { dates.parse(String($0), params)?.0 }
            case "RECURRENCE-ID": cur!.recurrenceID = dates.parse(value, params)?.0
            case "STATUS": cur!.cancelled = value.uppercased() == "CANCELLED"
            default: break
            }
        }

        // moved/cancelled single occurrences of a repeating event
        var overridden: [String: Set<Date>] = [:]
        for e in all where e.recurrenceID != nil { overridden[e.uid, default: []].insert(e.recurrenceID!) }

        var out: [CalEvent] = []
        for e in all {
            guard let start = e.start else { continue }
            let dur = max(0, (e.end ?? start.addingTimeInterval(e.allDay ? 86400 : 3600)).timeIntervalSince(start))
            var starts = [start]
            if e.recurrenceID == nil, let rule = e.rule {
                let skip = Set(e.exdates).union(overridden[e.uid] ?? [])
                starts = expand(start, rule, tz: e.tz, from: winStart.addingTimeInterval(-14 * 86400), until: winEnd).filter { !skip.contains($0) }
            }
            if e.cancelled { continue }
            for s in starts where s < winEnd && s.addingTimeInterval(dur) > winStart {
                out.append(CalEvent(id: e.uid + "@\(Int(s.timeIntervalSince1970))", title: e.summary,
                                    start: s, end: s.addingTimeInterval(dur), allDay: e.allDay, location: e.location))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Reads iCal dates without a DateFormatter per value (feeds can hold thousands of events).
    private final class Dates {
        private var cals: [String: Calendar] = [:], zones: [String: TimeZone] = [:]
        let utc = TimeZone(identifier: "UTC")!

        func cal(_ tz: TimeZone) -> Calendar {
            if let c = cals[tz.identifier] { return c }
            var c = Calendar(identifier: .gregorian)
            c.timeZone = tz
            cals[tz.identifier] = c
            return c
        }

        func zone(_ id: String?) -> TimeZone {
            guard let id = id?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) else { return .current }
            if let z = zones[id] { return z }
            let z = TimeZone(identifier: id) ?? .current
            zones[id] = z
            return z
        }

        func parse(_ v: String, _ params: [String: String]) -> (Date, Bool, TimeZone)? {
            let d = v.utf8.filter { $0 >= 48 && $0 <= 57 }.map { Int($0) - 48 }
            guard d.count >= 8 else { return nil }
            func num(_ at: Int, _ n: Int) -> Int { d[at..<at + n].reduce(0) { $0 * 10 + $1 } }
            var c = DateComponents(year: num(0, 4), month: num(4, 2), day: num(6, 2))
            if params["VALUE"] == "DATE" || d.count < 14 { return cal(.current).date(from: c).map { ($0, true, .current) } }
            c.hour = num(8, 2); c.minute = num(10, 2); c.second = num(12, 2)
            let tz = v.hasSuffix("Z") ? utc : zone(params["TZID"])
            return cal(tz).date(from: c).map { ($0, false, tz) }
        }
    }

    private static func unescape(_ v: String) -> String {
        v.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func parseRule(_ v: String, _ dates: Dates) -> Rule {
        var r = Rule()
        let days = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        for part in v.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0].uppercased() {
            case "FREQ": r.freq = kv[1].uppercased()
            case "INTERVAL": r.interval = max(1, Int(kv[1]) ?? 1)
            case "COUNT": r.count = Int(kv[1])
            case "UNTIL": r.until = dates.parse(kv[1], [:])?.0
            case "BYDAY":
                r.byDay = kv[1].split(separator: ",").compactMap { d in
                    let code = String(d.suffix(2)).uppercased()
                    guard let wd = days[code] else { return nil }
                    return (Int(d.dropLast(2)) ?? 0, wd)
                }
            case "BYMONTHDAY": r.byMonthDay = kv[1].split(separator: ",").compactMap { Int($0) }
            default: break
            }
        }
        return r
    }

    /// Occurrence start times up to `until`. Without COUNT it jumps straight to near `from`;
    /// with COUNT it walks from the first one so the count is right.
    private static func expand(_ start: Date, _ r: Rule, tz: TimeZone, from: Date, until limit: Date) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let time = cal.dateComponents([.hour, .minute, .second], from: start)
        let end = min(limit, r.until.map { $0.addingTimeInterval(1) } ?? limit)
        let skipTo = r.count == nil && from > start ? from : nil
        /// Whole intervals of `unit` between `a` and the skip point.
        func jump(_ unit: Calendar.Component, _ a: Date) -> Int {
            guard let skipTo, let k = cal.dateComponents([unit], from: a, to: skipTo).value(for: unit), k > 0 else { return 0 }
            return k / r.interval * r.interval
        }
        var out: [Date] = []
        var n = 0
        func add(_ d: Date) -> Bool {          // false = stop
            if d >= end { return false }
            if let c = r.count, n >= c { return false }
            if d >= start { out.append(d); n += 1 }
            return true
        }
        func at(_ day: Date) -> Date? {
            var c = cal.dateComponents([.year, .month, .day], from: day)
            c.hour = time.hour; c.minute = time.minute; c.second = time.second
            return cal.date(from: c)
        }
        switch r.freq {
        case "DAILY":
            var d = cal.date(byAdding: .day, value: jump(.day, start), to: start) ?? start
            for _ in 0..<20000 {
                guard add(d), let next = cal.date(byAdding: .day, value: r.interval, to: d) else { break }
                d = next
            }
        case "WEEKLY":
            let weekdays = r.byDay.isEmpty ? [cal.component(.weekday, from: start)] : r.byDay.map { $0.1 }.sorted()
            guard var week = cal.dateInterval(of: .weekOfYear, for: start)?.start else { break }
            week = cal.date(byAdding: .weekOfYear, value: jump(.weekOfYear, week), to: week) ?? week
            outer: for _ in 0..<5000 {
                for wd in weekdays {
                    let offset = (wd - cal.component(.weekday, from: week) + 7) % 7
                    guard let day = cal.date(byAdding: .day, value: offset, to: week), let d = at(day) else { continue }
                    if !add(d) { break outer }
                }
                guard let next = cal.date(byAdding: .weekOfYear, value: r.interval, to: week) else { break }
                week = next
            }
        case "MONTHLY":
            guard var month = cal.date(from: cal.dateComponents([.year, .month], from: start)) else { break }
            month = cal.date(byAdding: .month, value: jump(.month, month), to: month) ?? month
            outer: for _ in 0..<2000 {
                var days: [Date] = []
                if !r.byDay.isEmpty {
                    let range = cal.range(of: .day, in: .month, for: month) ?? 1..<29
                    let all = range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: month) }
                    for (nth, wd) in r.byDay {
                        let matches = all.filter { cal.component(.weekday, from: $0) == wd }
                        if nth > 0, nth <= matches.count { days.append(matches[nth - 1]) }
                        else if nth < 0, -nth <= matches.count { days.append(matches[matches.count + nth]) }
                        else if nth == 0 { days += matches }
                    }
                } else {
                    let mdays = r.byMonthDay.isEmpty ? [cal.component(.day, from: start)] : r.byMonthDay
                    let count = cal.range(of: .day, in: .month, for: month)?.count ?? 28
                    days = mdays.compactMap { md in
                        let dnum = md > 0 ? md : count + md + 1
                        return dnum >= 1 && dnum <= count ? cal.date(byAdding: .day, value: dnum - 1, to: month) : nil
                    }
                }
                for day in days.sorted() { if let d = at(day), !add(d) { break outer } }
                guard let next = cal.date(byAdding: .month, value: r.interval, to: month) else { break }
                month = next
            }
        case "YEARLY":
            var d = start
            for _ in 0..<500 {
                guard add(d), let next = cal.date(byAdding: .year, value: r.interval, to: d) else { break }
                d = next
            }
        default:
            out = [start]
        }
        return out
    }
}
