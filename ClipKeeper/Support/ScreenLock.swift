import CoreGraphics
import Foundation

enum ScreenLock {
    /// The lock state at this moment, from the window server.
    static func isLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
