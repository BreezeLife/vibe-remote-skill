import AppKit
import ApplicationServices
import Foundation

protocol FocusedInputServicing: AnyObject {
    func capture() throws -> FocusedInputTarget
    func isCurrent(_ target: FocusedInputTarget, requireUnchangedText: Bool) -> Bool
    func insert(_ text: String, into target: FocusedInputTarget) throws
}

// This lease is deliberately not Codable: target text and AX references only live in memory.
final class FocusedInputTarget: Identifiable {
    let id = UUID()
    let appName: String
    fileprivate let owner: UUID
    fileprivate let snapshot: FocusedInputSnapshot
    fileprivate var attemptedInsertion = false

    fileprivate init(owner: UUID, snapshot: FocusedInputSnapshot) {
        self.owner = owner
        self.snapshot = snapshot
        self.appName = snapshot.appName
    }
}

protocol FocusedInputReference: AnyObject {
    func matches(_ other: FocusedInputReference) -> Bool
}

struct FocusedInputSnapshot {
    var processID: Int32
    var appName: String
    var window: FocusedInputReference
    var element: FocusedInputReference
    var role: String = "AXTextArea"
    var secure = false
    var enabled = true
    var canReplaceSelection = true
    var text: String
    var selection: NSRange
}

protocol FocusedInputDriver: AnyObject {
    var isTrusted: Bool { get }
    func snapshot() throws -> FocusedInputSnapshot
    func replaceSelectedText(_ text: String, in snapshot: FocusedInputSnapshot) throws
}

enum FocusedInputError: LocalizedError {
    case permission, unavailable, unsupported, changed, alreadyAttempted, invalidText, uncertain
    var errorDescription: String? {
        switch self {
        case .permission: return "请先在系统设置中为 Vibe Remote 启用辅助功能。"
        case .unavailable: return "无法读取当前输入框，请先点击可编辑的普通文本输入框。"
        case .unsupported: return "当前输入框不支持安全填入；密码框和只读区域不能接收听写。"
        case .changed: return "输入位置或文字已变化，听写文字已保留，请检查后手动填入。"
        case .alreadyAttempted: return "已经尝试填入这段文字，请检查目标输入框；不会重复填入。"
        case .invalidText: return "输入文字或选区不受支持，请手动复制需要的文字。"
        case .uncertain: return "已尝试填入，但无法确认结果；请检查目标输入框，不要重复填入。"
        }
    }
}

final class FocusedInputService: FocusedInputServicing {
    fileprivate static let maximumUTF16Length = 1_048_576
    private let driver: FocusedInputDriver
    private let identity = UUID()
    init(driver: FocusedInputDriver) { self.driver = driver }
    convenience init() { self.init(driver: SystemFocusedInputDriver()) }

    func capture() throws -> FocusedInputTarget {
        try checkAccess()
        let current = try driver.snapshot()
        try Self.validate(current)
        return FocusedInputTarget(owner: identity, snapshot: current)
    }

    func isCurrent(_ target: FocusedInputTarget, requireUnchangedText: Bool) -> Bool {
        guard Thread.isMainThread, driver.isTrusted, target.owner == identity,
              !target.attemptedInsertion, let current = try? driver.snapshot(),
              (try? Self.validate(current)) != nil,
              Self.sameDestination(target.snapshot, current) else { return false }
        return !requireUnchangedText || Self.sameContents(target.snapshot, current)
    }

    func insert(_ text: String, into target: FocusedInputTarget) throws {
        try checkAccess()
        guard target.owner == identity else { throw FocusedInputError.changed }
        guard !target.attemptedInsertion else { throw FocusedInputError.alreadyAttempted }
        guard !text.isEmpty, text.utf16.count <= Self.maximumUTF16Length else {
            throw FocusedInputError.invalidText
        }
        let current = try driver.snapshot()
        try Self.validate(current)
        guard Self.sameDestination(target.snapshot, current), Self.sameContents(target.snapshot, current) else {
            throw FocusedInputError.changed
        }
        let replacementLength = current.text.utf16.count - current.selection.length + text.utf16.count
        guard replacementLength <= Self.maximumUTF16Length else { throw FocusedInputError.invalidText }
        let expected = (current.text as NSString).replacingCharacters(in: current.selection, with: text)
        // Consume before touching AX: an error does not prove the target rejected the write.
        target.attemptedInsertion = true
        do {
            try driver.replaceSelectedText(text, in: current)
            try checkAccess()
            let result = try driver.snapshot()
            try Self.validate(result)
            guard Self.sameDestination(current, result), result.text == expected else {
                throw FocusedInputError.uncertain
            }
        } catch {
            // Do not include provider errors or text in messages; never retry uncertain writes.
            throw FocusedInputError.uncertain
        }
    }

    private func checkAccess() throws {
        guard Thread.isMainThread else { throw FocusedInputError.unavailable }
        guard driver.isTrusted else { throw FocusedInputError.permission }
    }

    fileprivate static func validate(_ snapshot: FocusedInputSnapshot) throws {
        guard snapshot.processID > 0, ["AXTextField", "AXTextArea"].contains(snapshot.role),
              !snapshot.secure, snapshot.enabled, snapshot.canReplaceSelection else {
            throw FocusedInputError.unsupported
        }
        let count = snapshot.text.utf16.count
        let range = snapshot.selection
        guard count <= maximumUTF16Length, range.location >= 0, range.length >= 0,
              range.location <= count, range.length <= count - range.location else {
            throw FocusedInputError.invalidText
        }
        let utf16 = snapshot.text.utf16
        let start = utf16.index(utf16.startIndex, offsetBy: range.location)
        let end = utf16.index(start, offsetBy: range.length)
        guard String.Index(start, within: snapshot.text) != nil,
              String.Index(end, within: snapshot.text) != nil else {
            throw FocusedInputError.invalidText
        }
    }

    fileprivate static func sameDestination(_ lhs: FocusedInputSnapshot, _ rhs: FocusedInputSnapshot) -> Bool {
        lhs.processID == rhs.processID && lhs.window.matches(rhs.window) && lhs.element.matches(rhs.element)
    }

    fileprivate static func sameContents(_ lhs: FocusedInputSnapshot, _ rhs: FocusedInputSnapshot) -> Bool {
        lhs.text == rhs.text && lhs.selection == rhs.selection
    }
}

private final class AXFocusedInputReference: FocusedInputReference {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
    func matches(_ other: FocusedInputReference) -> Bool {
        guard let other = other as? AXFocusedInputReference else { return false }
        return CFEqual(element, other.element)
    }
}

// Access is lazy: construction performs no inspection, permission prompt, activation or mutation.
private final class SystemFocusedInputDriver: FocusedInputDriver {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func snapshot() throws -> FocusedInputSnapshot {
        guard Thread.isMainThread, isTrusted,
              let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated else {
            throw FocusedInputError.unavailable
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let element = try axElement(application, kAXFocusedUIElementAttribute)
        let window = try axElement(application, kAXFocusedWindowAttribute)
        let elementWindow = try axElement(element, kAXWindowAttribute)
        var elementPID: pid_t = 0
        let role = try string(element, kAXRoleAttribute)
        guard AXUIElementGetPid(element, &elementPID) == .success,
              elementPID == app.processIdentifier, CFEqual(window, elementWindow),
              [kAXTextFieldRole as String, kAXTextAreaRole as String].contains(role) else {
            throw FocusedInputError.unsupported
        }
        let subrole = optionalAttribute(element, kAXSubroleAttribute) as? String
        let protected = optionalAttribute(element, "AXProtectedContent") as? Bool ?? false
        var settable: DarwinBoolean = false
        // Reject secure fields before reading any value or selection.
        guard subrole != kAXSecureTextFieldSubrole as String, !protected,
              (try attribute(element, kAXEnabledAttribute) as? Bool) == true,
              AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { throw FocusedInputError.unsupported }
        let text = try string(element, kAXValueAttribute)
        guard text.utf16.count <= FocusedInputService.maximumUTF16Length else {
            throw FocusedInputError.invalidText
        }
        let rangeValue = try attribute(element, kAXSelectedTextRangeAttribute)
        guard CFGetTypeID(rangeValue) == AXValueGetTypeID() else { throw FocusedInputError.unsupported }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            throw FocusedInputError.unsupported
        }
        // An application can switch focus while AX reads are in progress. Observe it again.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              CFEqual(element, try axElement(application, kAXFocusedUIElementAttribute)),
              CFEqual(window, try axElement(application, kAXFocusedWindowAttribute)) else {
            throw FocusedInputError.changed
        }
        return FocusedInputSnapshot(processID: app.processIdentifier,
            appName: app.localizedName ?? "当前应用", window: AXFocusedInputReference(window),
            element: AXFocusedInputReference(element), role: role, text: text,
            selection: NSRange(location: range.location, length: range.length))
    }

    func replaceSelectedText(_ text: String, in expected: FocusedInputSnapshot) throws {
        let current = try snapshot()
        try FocusedInputService.validate(current)
        guard FocusedInputService.sameDestination(expected, current),
              FocusedInputService.sameContents(expected, current),
              let reference = current.element as? AXFocusedInputReference else {
            throw FocusedInputError.changed
        }
        guard AXUIElementSetAttributeValue(reference.element, kAXSelectedTextAttribute as CFString,
                                           text as CFString) == .success else {
            throw FocusedInputError.uncertain
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value else { throw FocusedInputError.unavailable }
        return value
    }

    private func optionalAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        try? attribute(element, name)
    }

    private func string(_ element: AXUIElement, _ name: String) throws -> String {
        guard let value = try attribute(element, name) as? String else { throw FocusedInputError.unsupported }
        return value
    }

    private func axElement(_ element: AXUIElement, _ name: String) throws -> AXUIElement {
        let value = try attribute(element, name)
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw FocusedInputError.unavailable }
        return value as! AXUIElement
    }
}
