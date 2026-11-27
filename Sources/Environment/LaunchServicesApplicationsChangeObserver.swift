import Foundation
import Dispatch

extension Notification.Name {
    static let filterKitAppInventoryDidRefresh = Notification.Name("FilterKit.AppInventoryDidRefresh")
}

#if canImport(notify)
import notify

/// Process-wide observer for LaunchServices application inventory changes.
/// It debounces notification bursts and delegates all work to the shared cache;
/// it never scans from the notification callback itself.
final class LaunchServicesApplicationsChangeObserver {
    private let notificationName = "com.apple.LaunchServices.ApplicationsChanged"
    private let queue = DispatchQueue(label: "com.filterkit.launchservices-change", qos: .utility)
    private var token: Int32 = 0
    private var workItem: DispatchWorkItem?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let status = notify_register_dispatch(notificationName, &token, queue) { [weak self] _ in
            self?.scheduleDebouncedChange()
        }
        if status != NOTIFY_STATUS_OK {
            token = 0
            NSLog("[FilterKit][AppDiscovery] LaunchServices change observer unavailable: %d", status)
        }
    }

    private func scheduleDebouncedChange() {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        workItem = item
        queue.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    deinit {
        workItem?.cancel()
        if token != 0 { notify_cancel(token) }
    }
}
#else
/// Host builds do not expose Darwin's notify API. Keep the same lifecycle surface
/// so shared registry code remains type-checkable in non-Apple validation hosts.
final class LaunchServicesApplicationsChangeObserver {
    init(onChange: @escaping () -> Void) {}
}
#endif
