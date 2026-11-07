import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Comfortable default size, centered; the layout adapts down to minSize.
    self.title = "CourseGrab"
    self.minSize = NSSize(width: 820, height: 560)
    self.setContentSize(NSSize(width: 1280, height: 820))
    self.center()
    self.titlebarAppearsTransparent = false

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
