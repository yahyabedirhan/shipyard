import AppKit

/// Opens and closes the menu bar icon's window (the panel) the way a click
/// on the icon does.
///
/// SwiftUI has no API to present or dismiss a `.window` style
/// `MenuBarExtra` (FB11984872), and closing its window directly leaves
/// SwiftUI thinking it's open, so the next click on the icon does nothing.
/// This goes through the status item, as the MenuBarExtraAccess package
/// does. On macOS 26 and earlier the icon's button toggles the window and
/// is on while it's presented. From macOS 27 the window lives for an
/// "expanded interface session" (private, so reached by selector and
/// guarded): closing cancels it, and opening clicks the button, best
/// effort, since the button's target is then nil. Each private selector is
/// called only when it takes no argument and returns an object, so a
/// change to it leaves the window as it was instead of crashing.
/// Each change runs on the next turn of the main loop, after the click
/// that asked for it is handled.
@MainActor
enum MenuBarWindow {
    static func open() { present(true) }
    static func close() { present(false) }

    private static func present(_ wanted: Bool) {
        DispatchQueue.main.async {
            guard let item = menuBarStatusItem() else { return }
            let delegate = NSSelectorFromString("expandedInterfaceDelegate")
            let session = NSSelectorFromString("expandedInterfaceSession")
            if returnsObject(item, delegate), returnsObject(item, session),
               item.perform(delegate)?.takeUnretainedValue() != nil {
                // macOS 27+: SwiftUI drives the window through a session
                // (the button's target is nil); it's presented while one exists.
                let current = item.perform(session)?.takeUnretainedValue() as? NSObject
                if wanted {
                    if current == nil { item.button?.performClick(nil) }
                } else if let current {
                    let cancel = NSSelectorFromString("cancel")
                    if takesNoArguments(current, cancel) { current.perform(cancel) }
                }
            } else if let button = item.button, (button.state != .off) != wanted {
                // macOS 26 and earlier: the button is on while presented.
                button.performClick(nil)
            }
        }
    }

    /// Whether `object` has an instance method `selector` that takes no
    /// argument and returns an object, so `perform(_:)` can call it and
    /// read its result.
    private static func returnsObject(_ object: NSObject, _ selector: Selector) -> Bool {
        guard takesNoArguments(object, selector),
              let method = class_getInstanceMethod(type(of: object), selector) else { return false }
        let type = method_copyReturnType(method)
        defer { free(type) }
        return String(cString: type) == "@"
    }

    /// Whether `object` has an instance method `selector` that takes no
    /// argument (besides `self` and `_cmd`), so `perform(_:)` can call it.
    private static func takesNoArguments(_ object: NSObject, _ selector: Selector) -> Bool {
        guard object.responds(to: selector),
              let method = class_getInstanceMethod(type(of: object), selector) else { return false }
        return method_getNumberOfArguments(method) == 2
    }

    /// The menu bar icon's status item: the app has one, found through
    /// its status bar window (a private `NSWindow` subclass that holds it).
    private static func menuBarStatusItem() -> NSStatusItem? {
        let key = "statusItem"
        for window in NSApp.windows where window.responds(to: NSSelectorFromString(key)) {
            if let item = window.value(forKey: key) as? NSStatusItem { return item }
        }
        return nil
    }
}
