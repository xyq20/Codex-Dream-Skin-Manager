import AppKit
import CoreGraphics

// Native facts only: the shared runtime decides when decorative rendering idles.
final class PowerState {
    private var screenSleeping = CGDisplayIsAsleep(CGMainDisplayID()) != 0
    private var systemSleeping = false, sessionActive = true
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private let changed: (Bool, TimeInterval) -> Void

    init(changed: @escaping (Bool, TimeInterval) -> Void) { self.changed = changed }
    func start(observeInput: Bool = false) {
        let workspace = NSWorkspace.shared.notificationCenter
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ update: @escaping () -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                update(); self?.sample()
            }
            observers.append((center, token))
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.screenSleeping = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.screenSleeping = false }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.systemSleeping = true }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.systemSleeping = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.sessionActive = false }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.sessionActive = true }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.sessionActive = false }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.sessionActive = true }
        if observeInput {
            let value = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.sample() }
            value.tolerance = 1; timer = value; RunLoop.main.add(value, forMode: .common)
        }
        sample()
    }
    private func sample() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        changed(!screenSleeping && !systemSleeping && sessionActive, idle)
    }
    deinit {
        timer?.invalidate()
        for (center, observer) in observers { center.removeObserver(observer) }
    }
}
