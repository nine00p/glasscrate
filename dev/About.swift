// Glass Crate — ABOUT AND WHAT'S NEW WINDOWS
// Shows the text from About.md (About window) and CHANGELOG.md (What's New window).
// To change the wording, edit those files (not this one) and rebuild.
//
// Formatting for both files:
//   # Big heading        ## Small heading        ### Smaller heading        - Bullet point
//   **bold**   *italic*   [link text](https://example.com)
//   A blank line starts a new paragraph.

import SwiftUI

struct AboutView: View {
    var resource = "About"       // which .md file to show: "About" or "CHANGELOG"
    var showVersion = true       // the "Version 1.1.0 (build 12)" line under the title
    private var blocks: [AboutBlock] { AboutBlock.load(resource) }

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (build \(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(blocks.indices, id: \.self) { i in
                    blocks[i].view
                    if i == 0 && showVersion {
                        // Version line comes from the app itself (set in build.sh), so it's always right
                        Text(Self.versionText)
                            .font(.gcCallout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(UIScale.s(24))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.gcBody)
        .frame(width: UIScale.s(560), height: UIScale.s(600))
    }
}

enum AboutBlock {
    case heading(String)
    case subheading(String)
    case minorHeading(String)
    case bullet(String)
    case paragraph(String)

    @ViewBuilder var view: some View {
        switch self {
        case .heading(let s):
            Text(Self.inline(s)).font(.gcTitle)
        case .subheading(let s):
            Text(Self.inline(s)).font(.gcHeadline).padding(.top, 6)
        case .minorHeading(let s):
            Text(Self.inline(s)).font(.gcCallout.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 2)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                Text(Self.inline(s)).fixedSize(horizontal: false, vertical: true)
            }
        case .paragraph(let s):
            Text(Self.inline(s)).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Handles **bold**, *italic*, and [links](https://...) inside a line.
    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }

    /// Reads a .md file from inside the app and splits it into headings, bullets, and paragraphs.
    static func load(_ resource: String) -> [AboutBlock] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [.paragraph("Text not found. Make sure \(resource).md is in the folder when you build.")]
        }

        var blocks: [AboutBlock] = []
        var lines: [String] = []
        func finishParagraph() {
            if !lines.isEmpty {
                blocks.append(.paragraph(lines.joined(separator: " ")))
                lines = []
            }
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                finishParagraph()
            } else if line.hasPrefix("### ") {
                finishParagraph()
                blocks.append(.minorHeading(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                finishParagraph()
                blocks.append(.subheading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                finishParagraph()
                blocks.append(.heading(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                finishParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                lines.append(line)
            }
        }
        finishParagraph()
        return blocks
    }
}
