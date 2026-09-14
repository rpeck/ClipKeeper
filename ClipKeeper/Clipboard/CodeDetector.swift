import Foundation

/// A language that ClipKeeper can name. `hljs` is the highlight.js name.
struct CodeLanguage: Hashable {
    let id: String
    let displayName: String
    let hljs: String
    let fileExtension: String

    static let all: [CodeLanguage] = [
        CodeLanguage(id: "python", displayName: "Python", hljs: "python", fileExtension: "py"),
        CodeLanguage(id: "javascript", displayName: "JavaScript", hljs: "javascript", fileExtension: "js"),
        CodeLanguage(id: "typescript", displayName: "TypeScript", hljs: "typescript", fileExtension: "ts"),
        CodeLanguage(id: "swift", displayName: "Swift", hljs: "swift", fileExtension: "swift"),
        CodeLanguage(id: "bash", displayName: "Shell", hljs: "bash", fileExtension: "sh"),
        CodeLanguage(id: "json", displayName: "JSON", hljs: "json", fileExtension: "json"),
        CodeLanguage(id: "yaml", displayName: "YAML", hljs: "yaml", fileExtension: "yml"),
        CodeLanguage(id: "html", displayName: "HTML", hljs: "xml", fileExtension: "html"),
        CodeLanguage(id: "xml", displayName: "XML", hljs: "xml", fileExtension: "xml"),
        CodeLanguage(id: "css", displayName: "CSS", hljs: "css", fileExtension: "css"),
        CodeLanguage(id: "sql", displayName: "SQL", hljs: "sql", fileExtension: "sql"),
        CodeLanguage(id: "go", displayName: "Go", hljs: "go", fileExtension: "go"),
        CodeLanguage(id: "rust", displayName: "Rust", hljs: "rust", fileExtension: "rs"),
        CodeLanguage(id: "c", displayName: "C", hljs: "c", fileExtension: "c"),
        CodeLanguage(id: "cpp", displayName: "C++", hljs: "cpp", fileExtension: "cpp"),
        CodeLanguage(id: "objectivec", displayName: "Objective-C", hljs: "objectivec", fileExtension: "m"),
        CodeLanguage(id: "java", displayName: "Java", hljs: "java", fileExtension: "java"),
        CodeLanguage(id: "kotlin", displayName: "Kotlin", hljs: "kotlin", fileExtension: "kt"),
        CodeLanguage(id: "csharp", displayName: "C#", hljs: "csharp", fileExtension: "cs"),
        CodeLanguage(id: "ruby", displayName: "Ruby", hljs: "ruby", fileExtension: "rb"),
        CodeLanguage(id: "php", displayName: "PHP", hljs: "php", fileExtension: "php"),
        CodeLanguage(id: "toml", displayName: "TOML", hljs: "ini", fileExtension: "toml"),
        CodeLanguage(id: "lisp", displayName: "Lisp", hljs: "lisp", fileExtension: "el"),
        CodeLanguage(id: "dockerfile", displayName: "Dockerfile", hljs: "dockerfile", fileExtension: "dockerfile"),
        CodeLanguage(id: "makefile", displayName: "Makefile", hljs: "makefile", fileExtension: "mk"),
        CodeLanguage(id: "diff", displayName: "Diff", hljs: "diff", fileExtension: "diff"),
    ]

    static func named(_ id: String?) -> CodeLanguage? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

/// Decides whether text looks like source code, and in which language.
enum CodeDetector {
    struct Result: Equatable {
        var isCode: Bool
        var language: String?
        var confidence: Double
    }

    private struct Signal {
        let regex: NSRegularExpression
        let weight: Double
        let cap: Double
        init(_ pattern: String, _ weight: Double, cap: Double? = nil, caseInsensitive: Bool = false) {
            var opts: NSRegularExpression.Options = [.anchorsMatchLines]
            if caseInsensitive { opts.insert(.caseInsensitive) }
            regex = try! NSRegularExpression(pattern: pattern, options: opts)
            self.weight = weight
            self.cap = cap ?? weight * 2
        }
        func score(_ text: String) -> Double {
            let n = regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            return min(cap, Double(n) * weight)
        }
    }

    private static let shellCommands = #"(sudo|brew|apt|apt-get|yum|dnf|pacman|npm|npx|yarn|pnpm|pip3?|uv|poetry|git|gh|docker|docker-compose|kubectl|helm|cargo|rustup|make|cmake|cd|ls|cat|echo|curl|wget|chmod|chown|mkdir|rm|cp|mv|ln|ssh|scp|rsync|tar|zip|unzip|find|grep|rg|sed|awk|xargs|swift|swiftc|xcodebuild|xcrun|python3?|node|deno|bun|go|java|javac|ruby|gem|bundle|rails|php|composer|perl|open|killall|ps|kill|top|df|du|env|export|source|alias|touch|head|tail|less|more|sort|uniq|wc|tr|cut|diff|patch|which|man|tmux|screen|vim|nano|emacs|code|defaults|launchctl|systemctl|service|ifconfig|ip|ping|dig|nslookup|traceroute|netstat|lsof|ssh-keygen|gpg|openssl|base64|jq|yq|htop|nvim|conda|mamba|pyenv|nvm|rbenv|terraform|aws|gcloud|az|heroku|flyctl|vercel|netlify|pytest|jest|mocha|eslint|prettier|black|ruff|mypy|tsc|webpack|vite|next|nest|dotnet|mvn|gradle|ant|sbt|lein|mix|iex|elixir|erl|ghc|cabal|stack|ocaml|opam|julia|R|Rscript|matlab|octave|latex|pdflatex|xelatex|pandoc|ffmpeg|imagemagick|convert|magick|say|osascript|pbcopy|pbpaste|xattr|codesign|spctl|hdiutil|diskutil|tccutil|xcode-select|mas|softwareupdate|caffeinate|pmset|networksetup|scutil|sysctl|dtrace|instruments|lldb|gdb|valgrind|strace|ltrace|objdump|nm|otool|install_name_tool|lipo|ar|ld|clang|gcc|g\+\+|cc|c\+\+|tsx|ts-node)"#

    private static let languageSignals: [String: [Signal]] = [
        "python": [
            Signal(#"^\s*def \w+\(.*\)\s*(->\s*[\w\[\], .|]+)?:"#, 3),
            Signal(#"^\s*class \w+(\(.*\))?:"#, 2.5),
            Signal(#"^\s*(from [\w.]+ )?import [\w., ]+$"#, 2, cap: 6),
            Signal(#"^\s*if __name__ == ['"]__main__['"]:"#, 4),
            Signal(#"^\s*(elif|else|try|except|finally|with|for|while|if) .*:\s*$"#, 1.5, cap: 6),
            Signal(#"^\s*(elif|else|try|except|finally):\s*$"#, 1.5, cap: 4),
            Signal(#"\bself\."#, 1, cap: 4),
            Signal(#"\bprint\("#, 1, cap: 2),
            Signal(#"\b(None|True|False)\b"#, 0.5, cap: 2),
            Signal(#"^\s*@\w+"#, 1, cap: 2),
            Signal(#"\blambda \w+:"#, 1.5),
            Signal(#"\"\"\""#, 1, cap: 2),
            Signal(#"\bf['"]"#, 1, cap: 2),
            Signal(#"^\s*return\b"#, 0.75, cap: 2),
            Signal(#"\.append\(|\bdict\(|\blist\(|\brange\(|\blen\("#, 1, cap: 3),
        ],
        "javascript": [
            Signal(#"\b(const|let|var) \w+\s*="#, 1.5, cap: 6),
            Signal(#"=>"#, 1.5, cap: 4),
            Signal(#"\bfunction\s*\w*\s*\("#, 2, cap: 4),
            Signal(#"console\.(log|error|warn)\("#, 3),
            Signal(#"\brequire\(['"]"#, 2.5),
            Signal(#"^\s*(import|export) .*from ['"]"#, 2, cap: 6),
            Signal(#"^\s*export (default|const|function|class)\b"#, 2),
            Signal(#"===|!=="#, 2, cap: 4),
            Signal(#"\b(null|undefined)\b"#, 0.75, cap: 2),
            Signal(#"\b(await|async)\b"#, 1, cap: 3),
            Signal(#"\b(document|window)\.\w+"#, 2, cap: 4),
            Signal(#"\.then\(|\.catch\("#, 1.5),
            Signal(#"\bnew Promise\b|\bJSON\.(parse|stringify)\("#, 2),
            Signal(#"\$\{[^}]+\}"#, 1, cap: 2),
            Signal(#";\s*$"#, 0.25, cap: 3),
        ],
        "typescript": [
            Signal(#":\s*(string|number|boolean|any|void|unknown|never)\b"#, 2.5, cap: 8),
            Signal(#"\binterface \w+(<[^>]+>)?\s*(extends [\w, <>]+)?\{"#, 3),
            Signal(#"\btype \w+(<[^>]+>)? ="#, 2.5),
            Signal(#"\bimplements\b|\benum \w+ \{|\bnamespace \w+"#, 2),
            Signal(#"\bas const\b|\bas \w+\b"#, 1),
            Signal(#"\b(Readonly|Partial|Record|Pick|Omit|Promise|Array)<"#, 2, cap: 4),
            Signal(#"\b(public|private|protected|readonly) \w+"#, 1.5, cap: 4),
            Signal(#"\w+\?:"#, 1.5, cap: 3),
            Signal(#"<\w+(\[\])?>\("#, 1),
        ],
        "swift": [
            Signal(#"\bfunc \w+\s*(<[^>]+>)?\("#, 3, cap: 6),
            Signal(#"\b(let|var) \w+(\s*:\s*[\w\[\]<>?!., ]+)?\s*="#, 1, cap: 4),
            Signal(#"\bimport (Foundation|SwiftUI|AppKit|UIKit|Combine|CoreData|CoreGraphics|Cocoa|XCTest|Testing)\b"#, 4),
            Signal(#"\bguard .* else \{"#, 3),
            Signal(#"\b(struct|class|enum|protocol|extension|actor) \w+(\s*:\s*[\w, ]+)?\s*\{"#, 2, cap: 4),
            Signal(#"@(State|Published|MainActor|objc|escaping|Binding|Environment|ObservedObject|StateObject|Observable|discardableResult|main)\b"#, 3, cap: 6),
            Signal(#"\bsome View\b"#, 4),
            Signal(#"\?\?|\bif let\b|\bguard let\b"#, 1.5, cap: 4),
            Signal(#"\b(fileprivate|unowned|weak var|inout|mutating|override|convenience|lazy var)\b"#, 2, cap: 4),
            Signal(#"\bprint\("#, 0.5),
            Signal(#"->\s*[\w\[\]<>?]+\s*\{"#, 1.5, cap: 3),
            Signal(#"\bswitch .* \{|\bcase \.\w+"#, 1.5, cap: 4),
            Signal(#"\bself\."#, 0.5, cap: 2),
            Signal(#"\b(String|Int|Double|Bool|Void)\b"#, 0.5, cap: 2),
        ],
        "bash": [
            Signal(#"^#!.*\b(sh|bash|zsh|fish)\b"#, 6),
            Signal(#"^\s*(if|elif|while|until) \[\[? "#, 3, cap: 6),
            Signal(#"^\s*(fi|done|esac)\s*$"#, 3, cap: 6),
            Signal(#"^\s*(then|do|else)\s*$"#, 2, cap: 4),
            Signal(#"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#, 0.75, cap: 3),
            Signal(#"^\s*(export|alias|source|set -[euxo]+|unset) \w"#, 2.5, cap: 5),
            Signal(#"\|\s*(grep|awk|sed|xargs|sort|uniq|head|tail|cut|tr|wc|tee|jq|less|xargs)\b"#, 3, cap: 6),
            Signal("^\\s*(\\$ )?" + shellCommands + "\\b", 2, cap: 6),
            Signal(#"^\s*\$ \S"#, 2, cap: 4),
            Signal(#"\s&&\s|\s\|\|\s"#, 1, cap: 2),
            Signal(#"2>&1|>\s*/dev/null|>>?\s*[\w./]+"#, 2, cap: 4),
            Signal(#"^\s*(function \w+\s*\(\)|\w+\s*\(\))\s*\{"#, 3),
            Signal(#"\s--?[a-zA-Z][\w-]*(=|\s|$)"#, 0.5, cap: 3),
            Signal(#"^\s*#(?!!)\s"#, 0.5, cap: 1.5),
            Signal(#"\becho\s+["'$-]"#, 1.5, cap: 3),
        ],
        "yaml": [
            Signal(#"^\s{0,8}[\w.-]+:\s*(\S.*)?$"#, 1, cap: 6),
            Signal(#"^\s*- (\w[\w.-]*:\s|\S)"#, 0.75, cap: 3),
            Signal(#"^---\s*$"#, 2),
            Signal(#"^\s+[\w.-]+:\s+\S"#, 1, cap: 4),
            Signal(#":\s*(true|false|null|~)\s*$"#, 1.5, cap: 3),
        ],
        "html": [
            Signal(#"<(!DOCTYPE|html|head|body|div|span|p|a|ul|ol|li|script|style|meta|link|img|h[1-6]|table|tr|td|th|form|input|button|nav|section|article|header|footer|main|br|hr|svg|path)\b"#, 1.5, cap: 8, caseInsensitive: true),
            Signal(#"</\w+>"#, 1, cap: 4),
            Signal(#"\b(class|id|href|src|style)=["']"#, 1, cap: 4),
        ],
        "xml": [
            Signal(#"<\?xml\b"#, 6),
            Signal(#"<[a-zA-Z][\w:-]*(\s+[\w:-]+="[^"]*")*\s*/?>"#, 0.75, cap: 4),
            Signal(#"</[a-zA-Z][\w:-]*>"#, 0.75, cap: 4),
            Signal(#"<!\[CDATA\["#, 3),
        ],
        "css": [
            Signal(#"^\s*[.#]?[\w-]+(\s*[,>+~]\s*[.#]?[\w-]+)*\s*\{\s*$"#, 2, cap: 6),
            Signal(#"^\s*[\w-]+\s*:\s*[^;{}]+;\s*$"#, 1.5, cap: 6),
            Signal(#"\d(px|em|rem|vh|vw|%)\b"#, 0.75, cap: 3),
            Signal(#"@(media|import|keyframes|font-face)\b|!important"#, 3),
            Signal(#"\b(color|margin|padding|display|font-size|background|border|width|height|flex|grid)\s*:"#, 1.5, cap: 6),
        ],
        "sql": [
            Signal(#"\b(SELECT|INSERT INTO|UPDATE|DELETE FROM|CREATE (TABLE|INDEX|VIEW|VIRTUAL TABLE)|ALTER TABLE|DROP TABLE)\b"#, 3, cap: 6, caseInsensitive: true),
            Signal(#"\bFROM\s+[\w."]+"#, 2, cap: 4, caseInsensitive: true),
            Signal(#"\bWHERE\b"#, 2, cap: 4, caseInsensitive: true),
            Signal(#"\b(INNER |LEFT |RIGHT |OUTER )?JOIN\b|\bGROUP BY\b|\bORDER BY\b|\bLIMIT \d+|\bHAVING\b"#, 1.5, cap: 6, caseInsensitive: true),
            Signal(#"\bVALUES\s*\("#, 2, caseInsensitive: true),
            Signal(#"\b(PRIMARY KEY|NOT NULL|VARCHAR|INTEGER|FOREIGN KEY)\b"#, 2, cap: 6, caseInsensitive: true),
        ],
        "go": [
            Signal(#"^\s*package \w+\s*$"#, 3),
            Signal(#"\bfunc (\(\w+ \*?\w+\) )?\w+\("#, 3, cap: 6),
            Signal(#":="#, 2, cap: 6),
            Signal(#"\bfmt\.\w+\("#, 3),
            Signal(#"^\s*import \($"#, 2),
            Signal(#"\berr != nil\b"#, 4),
            Signal(#"\b(chan|go func|defer|goroutine)\b"#, 2, cap: 4),
            Signal(#"\bfunc main\(\)"#, 3),
        ],
        "rust": [
            Signal(#"\b(pub )?fn \w+(<[^>]+>)?\("#, 3, cap: 6),
            Signal(#"\blet mut\b"#, 3),
            Signal(#"\bimpl(<[^>]+>)? \w+|\bpub struct\b|\bpub enum\b|\btrait \w+"#, 3, cap: 6),
            Signal(#"\b(println|eprintln|format|vec|panic)!\("#, 4),
            Signal(#"\w+::\w+"#, 1, cap: 3),
            Signal(#"&str\b|&mut\b|&self\b"#, 2, cap: 4),
            Signal(#"#\[(derive|test|cfg)"#, 4),
            Signal(#"->\s*(Result|Option)<"#, 2),
            Signal(#"\bmatch \w+ \{"#, 2),
            Signal(#"\.unwrap\(\)|\.expect\("#, 2),
        ],
        "c": [
            Signal(#"^\s*#include\s*[<"]"#, 4, cap: 8),
            Signal(#"\bint main\s*\("#, 4),
            Signal(#"\b(printf|malloc|calloc|free|sizeof|memcpy|strlen)\s*\("#, 2, cap: 6),
            Signal(#"\b(unsigned|uint\d+_t|int\d+_t|size_t|char\s*\*|void\s*\*)\b"#, 1.5, cap: 4),
            Signal(#"^\s*#define\b"#, 3),
            Signal(#"\bstruct \w+ \{|\btypedef\b"#, 2),
            Signal(#"\breturn 0;"#, 1.5),
        ],
        "cpp": [
            Signal(#"^\s*#include\s*[<"]"#, 3, cap: 6),
            Signal(#"\bstd::"#, 3, cap: 6),
            Signal(#"\b(nullptr|constexpr|auto&|template\s*<|virtual|override)\b"#, 3, cap: 6),
            Signal(#"\b(cout|cin|cerr)\s*<<|>>"#, 3),
            Signal(#"\bclass \w+\s*(:\s*(public|private|protected)\s+\w+)?\s*\{"#, 2),
            Signal(#"\busing namespace\b"#, 4),
            Signal(#"\bint main\s*\("#, 3),
        ],
        "objectivec": [
            Signal(#"@(interface|implementation|end|property|synthesize|selector)\b"#, 4, cap: 8),
            Signal(#"^\s*#import\s*[<"]"#, 4),
            Signal(#"\[\w+ \w+(:|\])"#, 1.5, cap: 4),
            Signal(#"\bNS(String|Array|Dictionary|Object|Number)\s*\*"#, 3, cap: 6),
            Signal(#"^\s*[-+]\s*\(\w+\s*\*?\)\s*\w+"#, 4),
        ],
        "java": [
            Signal(#"\bpublic (static )?(final )?(void|class|int|String|boolean|interface)\b"#, 3, cap: 6),
            Signal(#"System\.out\.print(ln)?\("#, 4),
            Signal(#"^\s*import java\.|^\s*package [\w.]+;"#, 4),
            Signal(#"@(Override|Test|Autowired|Bean)\b"#, 3),
            Signal(#"\bpublic class \w+"#, 3),
            Signal(#"\bnew \w+(<[^>]*>)?\("#, 0.5, cap: 2),
            Signal(#"\b(ArrayList|HashMap|List<|Map<)\b"#, 2, cap: 4),
        ],
        "kotlin": [
            Signal(#"\bfun \w+\("#, 3, cap: 6),
            Signal(#"\bval \w+"#, 1.5, cap: 4),
            Signal(#"^\s*import (kotlin|android|androidx|kotlinx)\."#, 4),
            Signal(#"\bdata class\b|\bsealed class\b|\bobject \w+"#, 4),
            Signal(#"\bcompanion object\b"#, 4),
            Signal(#"\bprintln\("#, 1),
            Signal(#"\?\.|!!"#, 1, cap: 2),
            Signal(#"\bwhen \(|\bwhen \{"#, 2),
        ],
        "csharp": [
            Signal(#"\busing System(\.\w+)*;"#, 4),
            Signal(#"\bnamespace [\w.]+"#, 2),
            Signal(#"Console\.Write(Line)?\("#, 4),
            Signal(#"\bvar \w+ = new\b"#, 2),
            Signal(#"\bpublic (static |async )?(void|class|int|string|Task)\b"#, 2, cap: 4),
            Signal(#"\b(string|bool)\b \w+"#, 1, cap: 2),
            Signal(#"\[(HttpGet|HttpPost|Fact|Test)\]"#, 3),
        ],
        "ruby": [
            Signal(#"^\s*def \w+[?!]?(\(.*\))?\s*$"#, 2.5, cap: 5),
            Signal(#"^\s*end\s*$"#, 1.5, cap: 4.5),
            Signal(#"\bputs\b"#, 3),
            Signal(#"\brequire(_relative)? ['"]"#, 3),
            Signal(#"\bdo \|[\w, ]+\|"#, 3),
            Signal(#"\.each\b|\.map\b"#, 1, cap: 2),
            Signal(#"\battr_(accessor|reader|writer)\b"#, 4),
            Signal(#"^\s*class \w+ < \w+"#, 3),
            Signal(#"@\w+ ="#, 1, cap: 2),
            Signal(#"\bnil\b|\belsif\b|\bunless\b"#, 1.5, cap: 3),
        ],
        "php": [
            Signal(#"<\?php"#, 6),
            Signal(#"\$\w+\s*="#, 1, cap: 4),
            Signal(#"\becho\s+['"$]"#, 1.5),
            Signal(#"\bfunction \w+\("#, 1),
            Signal(#"\$this->"#, 3),
            Signal(#"\b(foreach|elseif) \("#, 2),
        ],
        "toml": [
            Signal(#"^\[\w[\w.-]*\]\s*$"#, 3, cap: 6),
            Signal(#"^\[\[\w[\w.-]*\]\]\s*$"#, 3),
            Signal(#"^\w[\w-]* = ("|\d|\[|true|false|\{)"#, 2, cap: 6),
        ],
        "lisp": [
            Signal(#"\(defun \w"#, 5),
            Signal(#"\((defvar|defcustom|defmacro|setq|let\*?|use-package|require) "#, 3, cap: 6),
            Signal(#"\(lambda \("#, 2),
            Signal(#"^\s*;;"#, 1, cap: 2),
            Signal(#"\((if|when|unless|progn|cond|dolist|mapcar) "#, 1.5, cap: 4),
        ],
        "dockerfile": [
            Signal(#"^(FROM|RUN|CMD|COPY|ADD|ENTRYPOINT|WORKDIR|EXPOSE|ENV|ARG|LABEL|USER|VOLUME) "#, 3, cap: 9),
        ],
        "makefile": [
            Signal(#"^\.PHONY:"#, 5),
            Signal(#"^[\w.-]+:(\s+[\w.-]+)*\s*\n\t"#, 3, cap: 6),
            Signal(#"\$\((\w+)\)|\$@|\$<"#, 2, cap: 4),
        ],
        "diff": [
            Signal(#"^diff --git "#, 5),
            Signal(#"^@@ .* @@"#, 4, cap: 8),
            Signal(#"^(\+\+\+|---) "#, 2, cap: 4),
            Signal(#"^index [0-9a-f]+\.\.[0-9a-f]+"#, 3),
        ],
    ]

    private static let proseSentence = try! NSRegularExpression(pattern: #"^[A-Z][^\n{}();=<>\[\]|$#]{40,}[.?!]\s*$"#, options: [.anchorsMatchLines])
    private static let commentLine = try! NSRegularExpression(pattern: #"^\s*(//|/\*|\*\s|--\s|;;)"#, options: [.anchorsMatchLines])
    private static let indentedLine = try! NSRegularExpression(pattern: #"^(\t| {2,})\S"#, options: [.anchorsMatchLines])
    private static let semicolonEnd = try! NSRegularExpression(pattern: #";\s*$"#, options: [.anchorsMatchLines])
    private static let blockOpen = try! NSRegularExpression(pattern: #"[{:]\s*$"#, options: [.anchorsMatchLines])
    private static let callSite = try! NSRegularExpression(pattern: #"\b\w+\([^)\n]*\)"#, options: [])
    private static let operators = try! NSRegularExpression(pattern: #"==|!=|<=|>=|\+=|-=|->|=>|::|&&|\|\||\+\+|--|<<|>>"#, options: [])

    private static func count(_ re: NSRegularExpression, _ text: String) -> Int {
        re.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Commands that almost never start an English sentence.
    private static let strongShellCommands: Set<String> = [
        "sudo", "brew", "apt", "apt-get", "yum", "dnf", "pacman", "npm", "npx", "yarn", "pnpm", "pip", "pip3", "uv", "poetry",
        "git", "gh", "docker", "docker-compose", "kubectl", "helm", "cargo", "rustup", "cmake", "ls", "chmod", "chown", "mkdir",
        "rm", "cp", "mv", "ln", "ssh", "scp", "rsync", "tar", "unzip", "grep", "rg", "sed", "awk", "xargs", "swiftc", "xcodebuild",
        "xcrun", "python", "python3", "node", "deno", "bun", "javac", "gem", "bundle", "composer", "perl", "killall", "ps", "df",
        "du", "export", "alias", "source", "touch", "wc", "tr", "which", "tmux", "vim", "nano", "emacs", "nvim", "defaults",
        "launchctl", "systemctl", "ifconfig", "ping", "dig", "nslookup", "traceroute", "netstat", "lsof", "ssh-keygen", "gpg",
        "openssl", "base64", "jq", "yq", "htop", "conda", "mamba", "pyenv", "nvm", "rbenv", "terraform", "aws", "gcloud", "az",
        "heroku", "flyctl", "vercel", "netlify", "pytest", "jest", "mocha", "eslint", "prettier", "ruff", "mypy", "tsc", "webpack",
        "vite", "dotnet", "mvn", "gradle", "sbt", "ghc", "cabal", "julia", "rscript", "pandoc", "ffmpeg", "magick", "osascript",
        "pbcopy", "pbpaste", "xattr", "codesign", "spctl", "hdiutil", "diskutil", "tccutil", "xcode-select", "mas", "softwareupdate",
        "caffeinate", "pmset", "networksetup", "scutil", "sysctl", "lldb", "gdb", "valgrind", "strace", "otool", "lipo", "clang",
        "gcc", "g++", "cc", "tsx", "ts-node", "echo", "curl", "wget", "cd", "cat", "swift", "make", "open", "chsh", "crontab",
        "pkill", "nohup", "ulimit", "printf", "env", "head", "tail", "sort", "uniq", "cut", "diff", "patch", "find",
    ]

    /// True for one line that reads as a shell command: a known command
    /// first, a few words, and no sentence punctuation at the end.
    static func isShellCommandLine(_ line: String) -> Bool {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("$ ") { text.removeFirst(2) }
        if text.hasPrefix("% ") { text.removeFirst(2) }
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= 2, words.count <= 40, let first = words.first.map({ String($0).lowercased() }) else { return false }
        guard strongShellCommands.contains(first) else { return false }
        if let last = text.last, ".?!:,".contains(last) { return false }
        // Weak commands need a shell-shaped argument: a flag, a path, a pipe, or an assignment.
        let weak: Set<String> = ["open", "cat", "make", "find", "head", "tail", "sort", "cut", "diff", "patch", "env", "echo", "cd", "swift", "which", "printf"]
        if weak.contains(first) {
            let shellShape = text.contains(" -") || text.contains("/") || text.contains("|") || text.contains("=") || text.contains("*") || text.contains("~") || text.contains("&&") || text.contains(".")
            return shellShape
        }
        return true
    }

    static func detect(_ text: String) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(isCode: false, language: nil, confidence: 0) }

        // JSON is decided exactly.
        if let first = trimmed.first, first == "{" || first == "[", trimmed.count >= 2,
           let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            let isContainer = (trimmed.last == "}" || trimmed.last == "]")
            if isContainer { return Result(isCode: true, language: "json", confidence: 1) }
        }

        let lines = trimmed.components(separatedBy: "\n")
        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let lineCount = max(1, nonBlank.count)
        let sample = String(trimmed.prefix(20_000))

        // A single shell command line is decided by its first word.
        if lineCount == 1, isShellCommandLine(trimmed) {
            return Result(isCode: true, language: "bash", confidence: 0.6)
        }

        // Language scores.
        var scores: [String: Double] = [:]
        for (lang, signals) in languageSignals {
            var s = 0.0
            for sig in signals { s += sig.score(sample) }
            scores[lang] = s
        }
        // TypeScript is JavaScript plus type signals.
        if let ts = scores["typescript"], let js = scores["javascript"] {
            scores["typescript"] = ts >= 2 ? ts + js : 0
        }
        // C++ inherits C signals.
        if let cpp = scores["cpp"], let c = scores["c"] {
            let cppOnly = cpp - min(cpp, Signal(#"^\s*#include\s*[<"]"#, 3, cap: 6).score(sample))
            scores["cpp"] = cppOnly >= 2 ? cpp + c * 0.5 : 0
        }
        // YAML needs most lines to be keys or list items.
        if let y = scores["yaml"] {
            let keyLines = count(try! NSRegularExpression(pattern: #"^\s{0,8}[\w.-]+:(\s.*)?$"#, options: [.anchorsMatchLines]), sample)
            let listLines = count(try! NSRegularExpression(pattern: #"^\s*- \S"#, options: [.anchorsMatchLines]), sample)
            let ratio = Double(keyLines + listLines) / Double(lineCount)
            scores["yaml"] = (ratio >= 0.5 && keyLines >= 2 && lineCount >= 2 && !sample.contains(";")) ? y : 0
        }
        // HTML is XML with known tags. Prefer HTML when both fire.
        if let h = scores["html"], let x = scores["xml"], h >= 3 { scores["xml"] = x * 0.5 }

        let (bestLang, bestScore) = scores.max { a, b in a.value < b.value } ?? ("", 0)

        // Structure score, language independent.
        var structure = 0.0
        let semis = Double(count(semicolonEnd, sample)) / Double(lineCount)
        if semis >= 0.3 { structure += 2 } else if semis >= 0.15 { structure += 1 }
        let opens = sample.filter { $0 == "{" }.count, closes = sample.filter { $0 == "}" }.count
        if opens >= 2, abs(opens - closes) <= 1 { structure += 1.5 }
        let indented = Double(count(indentedLine, sample)) / Double(lineCount)
        if lineCount >= 3, indented >= 0.25 { structure += 1 }
        if count(blockOpen, sample) >= 2 { structure += 0.5 }
        if count(callSite, sample) >= 3 { structure += 1 }
        if count(operators, sample) >= 2 { structure += 1 }
        if count(commentLine, sample) >= 1 { structure += 1 }

        // Prose penalty.
        var penalty = 0.0
        penalty += min(6, Double(count(proseSentence, sample)) * 2)
        let letters = sample.filter { $0.isLetter || $0 == " " }.count
        let ratio = Double(letters) / Double(max(1, sample.count))
        if ratio >= 0.92 { penalty += 3 } else if ratio >= 0.85 { penalty += 1.5 }
        if lineCount == 1 && bestScore < 2 { penalty += 2 }

        let total = structure + bestScore - penalty
        var isCode = false
        if bestScore >= 3 && total >= 4 { isCode = true }
        else if structure >= 4 && total >= 4 { isCode = true }
        else if lineCount == 1, bestLang == "bash", bestScore >= 2, penalty < 3 { isCode = true }

        let language: String? = (isCode && bestScore >= 2) ? bestLang : nil
        let confidence = isCode ? min(1, max(0, total) / 10) : 0
        return Result(isCode: isCode, language: language, confidence: confidence)
    }
}
