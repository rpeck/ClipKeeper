import AppKit
#if SWIFT_PACKAGE
import BundleRedirect

// First, before any library touches its resource bundle. Xcode builds find
// the bundles on their own and do not compile this.
CKInstallBundleRedirect()
#endif

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
