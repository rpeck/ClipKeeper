#ifndef BUNDLE_REDIRECT_H
#define BUNDLE_REDIRECT_H

/// Lets SwiftPM resource bundles load from Contents/Resources of the app.
///
/// SwiftPM's generated `Bundle.module` looks for a library's resource bundle
/// in the root folder of the .app, and then at an absolute path into the
/// build folder of the Mac that built it. Code signing forbids files in the
/// root folder, so the build script puts the bundles in Contents/Resources.
/// On the Mac that built the app the build-folder path saves the lookup; on
/// any other Mac the app stopped at launch.
///
/// Call once, first thing in main, before any library touches its bundle.
void CKInstallBundleRedirect(void);

#endif
