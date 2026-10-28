// Talking to other apps (browsers, Spotify) with plain Apple Events: short timeouts, safe off the main thread,
// and a clear answer when macOS's Automation permission is missing.

import Cocoa

enum AE {
    static func code(_ s: String) -> FourCharCode { s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) } }

    static let notAllowed = OSStatus(errAEEventNotPermitted)       // -1743: switched off in Privacy & Security › Automation
    static let notAsked = OSStatus(errAEEventWouldRequireUserConsent) // -1744: macOS hasn't asked yet
    static let notRunning = OSStatus(procNotFound)                  // -600

    /// May Pocket Pet control this app? `ask` shows macOS's prompt if it hasn't been answered (blocks until it is; never on main).
    static func permission(_ bid: String, ask: Bool) -> OSStatus {
        AEDeterminePermissionToAutomateTarget(NSAppleEventDescriptor(bundleIdentifier: bid).aeDesc, code("****"), code("****"), ask)
    }

    /// An object specifier, e.g. property `pnam` of `container`.
    static func spec(_ want: String, _ form: String, _ data: NSAppleEventDescriptor, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let d = NSAppleEventDescriptor.record().coerce(toDescriptorType: code("obj "))!
        d.setDescriptor(NSAppleEventDescriptor(typeCode: code(want)), forKeyword: code("want"))
        d.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
        d.setDescriptor(data, forKeyword: code("seld"))
        d.setDescriptor(container, forKeyword: code("from"))
        return d
    }

    static func prop(_ c: String, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        spec("prop", "prop", NSAppleEventDescriptor(typeCode: code(c)), of: container)
    }

    static func element(_ cls: String, _ index: Int32, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        spec(cls, "indx", NSAppleEventDescriptor(int32: index), of: container)
    }

    /// Sends `cls`/`id` (e.g. "core"/"getd") and returns the reply's result, or the error.
    @discardableResult
    static func send(_ bid: String, _ cls: String, _ id: String, direct: NSAppleEventDescriptor? = nil,
                     params: [String: NSAppleEventDescriptor] = [:], timeout: TimeInterval = 2) -> (NSAppleEventDescriptor?, OSStatus) {
        let ev = NSAppleEventDescriptor(eventClass: code(cls), eventID: code(id), targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bid),
                                        returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let direct { ev.setParam(direct, forKeyword: code("----")) }
        for (k, v) in params { ev.setParam(v, forKeyword: code(k)) }
        do {
            let reply = try ev.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)
            return (reply.paramDescriptor(forKeyword: code("----")), noErr)
        } catch {
            return (nil, OSStatus((error as NSError).code))
        }
    }

    static func get(_ bid: String, _ spec: NSAppleEventDescriptor) -> (NSAppleEventDescriptor?, OSStatus) {
        send(bid, "core", "getd", direct: spec)
    }

    static func set(_ bid: String, _ spec: NSAppleEventDescriptor, _ value: NSAppleEventDescriptor) {
        send(bid, "core", "setd", direct: spec, params: ["data": value])
    }
}
