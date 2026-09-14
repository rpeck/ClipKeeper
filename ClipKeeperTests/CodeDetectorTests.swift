import Testing
@testable import ClipKeeper

@Suite struct CodeDetectorTests {
    @Test func python() {
        let src = """
        import json
        from pathlib import Path

        def extract(archive, destination):
            with open(archive) as f:
                data = json.load(f)
            return data
        """
        let r = CodeDetector.detect(src)
        #expect(r.isCode)
        #expect(r.language == "python")
    }

    @Test func swift() {
        let src = """
        import SwiftUI

        struct ContentView: View {
            @State private var count = 0
            var body: some View {
                Button("Tap \\(count)") { count += 1 }
            }
        }
        """
        let r = CodeDetector.detect(src)
        #expect(r.isCode)
        #expect(r.language == "swift")
    }

    @Test func typeScript() {
        let src = """
        interface User { id: number; name: string }
        export const load = async (id: number): Promise<User> => {
          const res = await fetch(`/api/users/${id}`);
          return res.json();
        };
        """
        let r = CodeDetector.detect(src)
        #expect(r.isCode)
        #expect(r.language == "typescript")
    }

    @Test func javaScript() {
        let src = """
        const fs = require('fs');
        function readAll(dir) {
          return fs.readdirSync(dir).map((f) => f.toUpperCase());
        }
        console.log(readAll('.'));
        """
        let r = CodeDetector.detect(src)
        #expect(r.isCode)
        #expect(r.language == "javascript")
    }

    @Test func bashScript() {
        let src = """
        #!/bin/bash
        set -euo pipefail
        for f in *.log; do
          grep -c ERROR "$f" | sort -n
        done
        """
        let r = CodeDetector.detect(src)
        #expect(r.isCode)
        #expect(r.language == "bash")
    }

    @Test func singleShellCommand() {
        let r = CodeDetector.detect("brew install xcodegen")
        #expect(r.isCode)
        #expect(r.language == "bash")
        let r2 = CodeDetector.detect("git commit -m \"Initial commit\" && git push origin main")
        #expect(r2.isCode)
    }

    @Test func json() {
        let r = CodeDetector.detect("{\"name\": \"ClipKeeper\", \"tags\": [\"mac\", \"clipboard\"]}")
        #expect(r.isCode)
        #expect(r.language == "json")
    }

    @Test func sql() {
        let r = CodeDetector.detect("SELECT id, name FROM users WHERE active = 1 ORDER BY name LIMIT 10;")
        #expect(r.isCode)
        #expect(r.language == "sql")
    }

    @Test func go() {
        let src = """
        package main

        import "fmt"

        func main() {
            x := 42
            if err := run(); err != nil {
                fmt.Println(err)
            }
        }
        """
        let r = CodeDetector.detect(src)
        #expect(r.isCode)
        #expect(r.language == "go")
    }

    @Test func rust() {
        let src = """
        fn main() {
            let mut v: Vec<i32> = Vec::new();
            v.push(1);
            println!("{:?}", v);
        }
        """
        let r = CodeDetector.detect(src)
        #expect(r.isCode)
        #expect(r.language == "rust")
    }

    @Test func yaml() {
        let src = """
        name: ClipKeeper
        options:
          bundleIdPrefix: com.example
          deploymentTarget:
            macOS: "15.0"
        targets:
          - app
        """
        let r = CodeDetector.detect(src)
        #expect(r.isCode)
        #expect(r.language == "yaml")
    }

    @Test func html() {
        let src = "<div class=\"card\"><h1>Hello</h1><p>World</p><a href=\"/x\">link</a></div>"
        let r = CodeDetector.detect(src)
        #expect(r.isCode)
        #expect(r.language == "html")
    }

    @Test func css() {
        let src = """
        .card {
          display: flex;
          padding: 12px;
          color: #333;
        }
        """
        let r = CodeDetector.detect(src)
        #expect(r.isCode)
        #expect(r.language == "css")
    }

    @Test func proseIsNotCode() {
        let prose = """
        The quick brown fox jumps over the lazy dog. This sentence is here to look like ordinary writing.
        We met on Tuesday to talk about the plan, and everyone agreed that the schedule was fine.
        Please send the notes to the team by Friday so that we can review them before the meeting.
        """
        #expect(!CodeDetector.detect(prose).isCode)
    }

    @Test func shortPhrasesAreNotCode() {
        #expect(!CodeDetector.detect("B1 Ledge running").isCode)
        #expect(!CodeDetector.detect("Nate's Substack | Substack - 9 September 2026").isCode)
        #expect(!CodeDetector.detect("Meeting at 3pm tomorrow").isCode)
    }

    @Test func listOfNamesIsNotCode() {
        let text = "Alice Johnson\nBob Smith\nCarol Danvers\nDave Grohl"
        #expect(!CodeDetector.detect(text).isCode)
    }

    @Test func diff() {
        let src = """
        diff --git a/foo.swift b/foo.swift
        index 83db48f..bf12a3c 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,3 @@
        -let x = 1
        +let x = 2
        """
        let r = CodeDetector.detect(src)
        #expect(r.isCode)
        #expect(r.language == "diff")
    }
}
