import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Koi desktop close policy: Dart owns the cancellable save/exit protocol.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Koi desktop reopen begin
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows visible: Bool) -> Bool {
    if !visible {
      for window in NSApp.windows where window is MainFlutterWindow {
        window.makeKeyAndOrderFront(self)
      }
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }
  // Koi desktop reopen end

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
