import Foundation

/// Compiles a regular expression that is a literal in the source. A pattern
/// that does not compile is a programming error, so this stops the app with
/// the pattern in the message instead of failing silently.
func compileRegex(pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
    do {
        return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
        preconditionFailure("Invalid regular expression \(pattern): \(error)")
    }
}
