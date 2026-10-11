import Foundation

final class FakeInputReference: FocusedInputReference {
    let id: Int
    init(_ id: Int) { self.id = id }
    func matches(_ other: FocusedInputReference) -> Bool {
        (other as? FakeInputReference)?.id == id
    }
}

final class FakeFocusedDriver: FocusedInputDriver {
    var isTrusted = true
    var current = FocusedInputSnapshot(processID: 42, appName: "Fixture Editor",
        window: FakeInputReference(1), element: FakeInputReference(2),
        text: "before 👩🏽‍💻 after", selection: NSRange(location: 7, length: 7))
    var readError = false
    var throwAfterWrite = false
    var corruptAfterWrite = false
    var changeFocusAfterWrite = false
    var losePermissionAfterWrite = false
    var loseSnapshotAfterWrite = false
    var writes = 0
    func snapshot() throws -> FocusedInputSnapshot {
        if readError { throw FocusedInputError.unavailable }
        return current
    }
    func replaceSelectedText(_ text: String, in snapshot: FocusedInputSnapshot) throws {
        writes += 1
        current.text = (snapshot.text as NSString).replacingCharacters(in: snapshot.selection, with: text)
        current.selection = NSRange(location: snapshot.selection.location + text.utf16.count, length: 0)
        if corruptAfterWrite { current.text += "!" }
        if changeFocusAfterWrite { current.element = FakeInputReference(3) }
        if losePermissionAfterWrite { isTrusted = false }
        if loseSnapshotAfterWrite { readError = true }
        if throwAfterWrite { throw FocusedInputError.unavailable }
    }
}

@MainActor var failures = 0
@MainActor var assertions = 0
@MainActor func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    assertions += 1
    if !condition() { failures += 1; print("FAIL \(label)") }
}
@MainActor func rejects(_ label: String, _ action: () throws -> Void) {
    do { try action(); check(false, label) }
    catch { check(true, label) }
}
@MainActor func scenario(_ label: String, _ action: (FakeFocusedDriver, FocusedInputService) throws -> Void) {
    let driver = FakeFocusedDriver()
    do { try action(driver, FocusedInputService(driver: driver)) }
    catch { check(false, "\(label): unexpected safe error \(error.localizedDescription)") }
}

@MainActor func run() {
    scenario("UTF-16 replacement") { driver, service in
        let target = try service.capture()
        check(target.appName == "Fixture Editor", "lease has human-readable app name")
        check(service.isCurrent(target, requireUnchangedText: true), "captured lease is current")
        try service.insert("语音 🐈", into: target)
        check(driver.current.text == "before 语音 🐈 after", "replace exact emoji UTF-16 selection")
        check(driver.writes == 1, "exactly one replacement")
        rejects("no repeated insertion") { try service.insert("语音 🐈", into: target) }
        check(driver.writes == 1, "repeat never reaches driver")
    }
    scenario("caret insertion") { driver, service in
        driver.current.text = "abc"
        driver.current.selection = NSRange(location: 1, length: 0)
        let target = try service.capture()
        try service.insert("\n中文", into: target)
        check(driver.current.text == "a\n中文bc", "newlines inserted as text, not key events")
    }
    scenario("single-line text field") { driver, service in
        driver.current.role = "AXTextField"
        driver.current.text = ""
        driver.current.selection = NSRange(location: 0, length: 0)
        let target = try service.capture()
        try service.insert("🐱", into: target)
        check(driver.current.text == "🐱", "empty ordinary text field accepts exact input")
        check(!service.isCurrent(target, requireUnchangedText: false), "consumed lease cannot be reused")
    }
    scenario("empty utterance") { driver, service in
        let target = try service.capture()
        rejects("empty utterance does not erase selection") { try service.insert("", into: target) }
        check(driver.writes == 0, "empty utterance never reaches driver")
    }
    scenario("frontmost process changes") { driver, service in
        let target = try service.capture(); driver.current.processID = 43
        check(!service.isCurrent(target, requireUnchangedText: false), "different process invalidates provider lease")
        rejects("different process blocks insertion") { try service.insert("x", into: target) }
        check(driver.writes == 0, "focus failure is read-only")
    }
    scenario("window changes") { driver, service in
        let target = try service.capture(); driver.current.window = FakeInputReference(9)
        check(!service.isCurrent(target, requireUnchangedText: false), "different window invalidates lease")
        rejects("different window blocks insertion") { try service.insert("x", into: target) }
    }
    scenario("input changes") { driver, service in
        let target = try service.capture(); driver.current.element = FakeInputReference(9)
        check(!service.isCurrent(target, requireUnchangedText: false), "different input invalidates lease")
    }
    scenario("provider types into current field") { driver, service in
        let target = try service.capture()
        driver.current.text += "live"; driver.current.selection = NSRange(location: 0, length: 0)
        check(service.isCurrent(target, requireUnchangedText: false), "provider lease allows its own text changes")
        check(!service.isCurrent(target, requireUnchangedText: true), "native lease rejects changed text")
        rejects("changed content blocks insertion") { try service.insert("x", into: target) }
        check(driver.writes == 0, "changed content cannot be overwritten")
    }
    scenario("selection changes") { driver, service in
        let target = try service.capture(); driver.current.selection = NSRange(location: 0, length: 0)
        check(!service.isCurrent(target, requireUnchangedText: true), "selection move invalidates native lease")
        rejects("selection move blocks insertion") { try service.insert("x", into: target) }
    }
    scenario("missing permissions") { driver, service in
        driver.isTrusted = false
        rejects("capture needs trusted AX") { _ = try service.capture() }
    }
    scenario("permission revoked") { driver, service in
        let target = try service.capture(); driver.isTrusted = false
        check(!service.isCurrent(target, requireUnchangedText: false), "revoked permission invalidates lease")
        rejects("revoked permission blocks insertion") { try service.insert("x", into: target) }
    }
    scenario("secure field") { driver, service in
        driver.current.secure = true
        rejects("password field rejected") { _ = try service.capture() }
    }
    scenario("unsupported role") { driver, service in
        driver.current.role = "AXStaticText"
        rejects("non-input role rejected") { _ = try service.capture() }
    }
    scenario("disabled field") { driver, service in
        driver.current.enabled = false
        rejects("disabled input rejected") { _ = try service.capture() }
    }
    scenario("selected text not writable") { driver, service in
        driver.current.canReplaceSelection = false
        rejects("no full-value or clipboard fallback") { _ = try service.capture() }
    }
    for selection in [NSRange(location: -1, length: 0), NSRange(location: Int.max, length: 1),
                      NSRange(location: 0, length: Int.max), NSRange(location: 0, length: -1),
                      NSRange(location: 8, length: 0), NSRange(location: 0, length: 8)] {
        scenario("invalid UTF-16 selection") { driver, service in
            driver.current.selection = selection
            rejects("invalid range rejected: \(selection)") { _ = try service.capture() }
        }
    }
    scenario("bounded text") { driver, service in
        driver.current.text = String(repeating: "a", count: 1_048_577)
        driver.current.selection = NSRange(location: 0, length: 0)
        rejects("oversized target rejected") { _ = try service.capture() }
    }
    scenario("bounded insertion") { driver, service in
        let target = try service.capture()
        rejects("oversized insertion rejected") { try service.insert(String(repeating: "a", count: 1_048_577), into: target) }
        check(driver.writes == 0, "oversized insertion never mutates")
    }
    scenario("bounded resulting value") { driver, service in
        driver.current.text = String(repeating: "a", count: 1_048_576)
        driver.current.selection = NSRange(location: 0, length: 0)
        let target = try service.capture()
        rejects("resulting value limit cannot be exceeded") { try service.insert("x", into: target) }
        check(driver.writes == 0, "result limit checked before mutation")
    }
    scenario("target becomes secure") { driver, service in
        let target = try service.capture(); driver.current.secure = true
        check(!service.isCurrent(target, requireUnchangedText: false), "secure transition invalidates provider lease")
        rejects("secure transition blocks native insertion") { try service.insert("x", into: target) }
        check(driver.writes == 0, "secure transition never mutates")
    }
    scenario("different adapter instance") { driver, service in
        let target = try service.capture()
        let other = FocusedInputService(driver: driver)
        check(!other.isCurrent(target, requireUnchangedText: false), "lease belongs to capturing service")
        rejects("foreign lease rejected") { try other.insert("x", into: target) }
    }
    for outcome in 0..<5 {
        scenario("uncertain write \(outcome)") { driver, service in
            let target = try service.capture()
            driver.throwAfterWrite = outcome == 0
            driver.corruptAfterWrite = outcome == 1
            driver.changeFocusAfterWrite = outcome == 2
            driver.losePermissionAfterWrite = outcome == 3
            driver.loseSnapshotAfterWrite = outcome == 4
            rejects("uncertain mutation reported") { try service.insert("keep this utterance", into: target) }
            rejects("uncertain result never retried") { try service.insert("keep this utterance", into: target) }
            check(driver.writes == 1, "uncertain mutation attempted once")
        }
    }
    scenario("unavailable snapshot") { driver, service in
        let target = try service.capture(); driver.readError = true
        check(!service.isCurrent(target, requireUnchangedText: false), "snapshot failure invalidates lease")
        rejects("snapshot failure blocks write") { try service.insert("x", into: target) }
        check(driver.writes == 0, "failed snapshot never mutates")
    }
    print("\(assertions) focused input assertions; \(failures) failures")
    exit(failures == 0 ? 0 : 1)
}

MainActor.assumeIsolated { run() }
