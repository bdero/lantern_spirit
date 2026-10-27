import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // A phone-shaped window, so the desktop build reads like the app screen.
    let size = NSSize(width: 410, height: 860)
    var windowFrame = self.frame
    windowFrame.size = size
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.contentMinSize = NSSize(width: 360, height: 640)
    self.title = "Lantern Spirit"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
