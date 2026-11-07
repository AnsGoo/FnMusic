import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()

    // Mirror the desktop build: open at 1180x780, never shrink below 940x640.
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1180, height: 780)
    self.minSize = NSSize(width: 940, height: 640)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "乐记"
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
