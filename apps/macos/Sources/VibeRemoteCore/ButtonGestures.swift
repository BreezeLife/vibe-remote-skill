import Foundation

public struct GestureTrigger: Equatable {
    public let button: RemoteButton
    public let gesture: ButtonGesture
    public let action: RemoteAction
    public let repeated: Bool
    public init(button: RemoteButton, gesture: ButtonGesture, action: RemoteAction, repeated: Bool = false) {
        self.button = button; self.gesture = gesture; self.action = action; self.repeated = repeated
    }
}

public struct ButtonGestureEngine {
    private struct Press {
        let mapping: ButtonMapping
        let began: TimeInterval
        let secondClick: Bool
        var heldAction: RemoteAction?
        var nextRepeat: TimeInterval?
    }
    private struct PendingClick {
        let mapping: ButtonMapping
        let deadline: TimeInterval
    }
    private let holdDuration: TimeInterval
    private let doubleClickInterval: TimeInterval
    private let repeatInterval: TimeInterval
    private var presses: [RemoteButton: Press] = [:]
    private var pending: [RemoteButton: PendingClick] = [:]
    private var lastTime: TimeInterval?

    public init(holdDuration: TimeInterval = 0.6, doubleClickInterval: TimeInterval = 0.3,
                repeatInterval: TimeInterval = 0.12) {
        self.holdDuration = holdDuration.isFinite && holdDuration > 0 ? holdDuration : 0.6
        self.doubleClickInterval = doubleClickInterval.isFinite && doubleClickInterval > 0 ? doubleClickInterval : 0.3
        self.repeatInterval = repeatInterval.isFinite && repeatInterval > 0 ? repeatInterval : 0.12
    }

    /// Call only for calibrated input. The caller resets this engine on mapping,
    /// device, permission, sleep or connection changes. Repeated HID downs are ignored.
    public mutating func process(button: RemoteButton, isDown: Bool, at: TimeInterval, mapping: ButtonMapping) -> [GestureTrigger] {
        guard acceptTime(at) else { return [] }
        guard button != .mic && mapping.button == button else {
            presses.removeValue(forKey: button)
            pending.removeValue(forKey: button)
            return []
        }
        if let press = presses[button], press.mapping != mapping {
            presses.removeValue(forKey: button)
            pending.removeValue(forKey: button)
            return []
        }
        if let click = pending[button], click.mapping != mapping { pending.removeValue(forKey: button) }
        var triggers = resolveTimers(at)
        if isDown {
            guard presses[button] == nil else { return triggers }
            let secondClick = pending.removeValue(forKey: button) != nil
            presses[button] = Press(mapping: mapping, began: at, secondClick: secondClick)
        } else if let press = presses.removeValue(forKey: button), press.heldAction == nil {
            if press.secondClick, let action = active(press.mapping.double) {
                triggers.append(GestureTrigger(button: button, gesture: .doubleClick, action: action))
            } else if active(press.mapping.double) != nil {
                pending[button] = PendingClick(mapping: press.mapping, deadline: at + doubleClickInterval)
            } else if press.mapping.single != .none {
                triggers.append(GestureTrigger(button: button, gesture: .click, action: press.mapping.single))
            }
        }
        return triggers
    }

    /// Inject monotonic time. Late ticks emit at most one repeat per held button;
    /// the engine never catches up a backlog of scroll/volume actions in a burst.
    public mutating func advance(to: TimeInterval) -> [GestureTrigger] {
        guard acceptTime(to) else { return [] }
        return resolveTimers(to)
    }

    public mutating func reset() {
        presses.removeAll()
        pending.removeAll()
        lastTime = nil
    }

    private mutating func acceptTime(_ time: TimeInterval) -> Bool {
        guard time.isFinite && time >= 0 && (lastTime == nil || time >= lastTime!) else {
            reset()
            return false
        }
        lastTime = time
        return true
    }

    private func active(_ action: RemoteAction?) -> RemoteAction? {
        guard let action, action != .none else { return nil }
        return action
    }

    private mutating func resolveTimers(_ time: TimeInterval) -> [GestureTrigger] {
        var triggers: [GestureTrigger] = []
        // Stable ordering makes simultaneous fake and physical events reproducible.
        for button in RemoteButton.allCases {
            if let click = pending[button], time >= click.deadline {
                pending.removeValue(forKey: button)
                if click.mapping.single != .none {
                    triggers.append(GestureTrigger(button: button, gesture: .click, action: click.mapping.single))
                }
            }
            guard var press = presses[button], press.mapping.input?.supportsHold != false else { continue }
            if press.heldAction == nil, time >= press.began + holdDuration {
                let hold = active(press.mapping.long) ?? (press.mapping.single.allowsRepeat ? press.mapping.single : nil)
                if let action = hold {
                    press.heldAction = action
                    press.nextRepeat = action.allowsRepeat ? time + repeatInterval : nil
                    triggers.append(GestureTrigger(button: button, gesture: .hold, action: action))
                }
            } else if let action = press.heldAction, action.allowsRepeat,
                      let deadline = press.nextRepeat, time >= deadline {
                press.nextRepeat = time + repeatInterval
                triggers.append(GestureTrigger(button: button, gesture: .hold, action: action, repeated: true))
            }
            presses[button] = press
        }
        return triggers
    }
}
