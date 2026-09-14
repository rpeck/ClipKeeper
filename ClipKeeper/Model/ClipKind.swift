import Foundation

/// The kind of content a clip holds. The kind decides the preview, the
/// paste-as choices, and the save-as formats.
enum ClipKind: String, Codable, CaseIterable, Hashable {
    case text
    case markdown
    case code
    case richText
    case image
    case link
    case color
    case files

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .markdown: return "Markdown"
        case .code: return "Code"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .link: return "Link"
        case .color: return "Color"
        case .files: return "Files"
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .markdown: return "text.document"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .richText: return "textformat"
        case .image: return "photo"
        case .link: return "link"
        case .color: return "paintpalette"
        case .files: return "doc"
        }
    }

    /// Kinds whose main content is text that the user can edit.
    var isTextual: Bool {
        switch self {
        case .text, .markdown, .code, .richText, .link, .color: return true
        case .image, .files: return false
        }
    }
}
