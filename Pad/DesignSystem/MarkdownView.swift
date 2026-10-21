import SwiftUI

/// Renders the Markdown Claude writes: paragraphs, headings, bullet and numbered lists, fenced code
/// and inline styles. Tables and other blocks fall back to monospaced text.
struct MarkdownView: View {
    let text: String
    var fontSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    enum Block {
        case paragraph(String)
        case heading(String)
        case bullets([String])
        case numbered([String])
        case code(String)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text)).font(.ui(fontSize)).lineSpacing(5).foregroundStyle(Theme.text)
        case .heading(let text):
            Text(Self.inline(text)).font(.ui(fontSize + 1, .semibold)).foregroundStyle(Theme.text).padding(.top, 4)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•").foregroundStyle(Theme.text3)
                        Text(Self.inline(item)).lineSpacing(4).foregroundStyle(Theme.text2)
                    }
                }
            }
            .font(.ui(fontSize))
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1).").foregroundStyle(Theme.text3).monospacedDigit()
                        Text(Self.inline(item)).lineSpacing(4).foregroundStyle(Theme.text2)
                    }
                }
            }
            .font(.ui(fontSize))
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code).font(.mono(13)).foregroundStyle(Color(hex: 0xE6DCCF)).lineSpacing(4)
                    .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.well, in: .rect(cornerRadius: 10, style: .continuous))
        }
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var list: [String] = []
        var listIsNumbered = false
        var code: [String]?

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        func flushList() {
            if !list.isEmpty { blocks.append(listIsNumbered ? .numbered(list) : .bullets(list)) }
            list = []
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph(); flushList()
                    code = []
                }
                continue
            }
            if code != nil { code?.append(raw); continue }

            if line.isEmpty {
                flushParagraph(); flushList()
            } else if line.hasPrefix("#") {
                flushParagraph(); flushList()
                blocks.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if let item = bullet(line) {
                flushParagraph()
                if listIsNumbered { flushList() }
                listIsNumbered = false
                list.append(item)
            } else if let item = numbered(line) {
                flushParagraph()
                if !listIsNumbered { flushList() }
                listIsNumbered = true
                list.append(item)
            } else {
                flushList()
                paragraph.append(line)
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flushParagraph(); flushList()
        return blocks
    }

    private static func bullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) { return String(line.dropFirst(marker.count)) }
        return nil
    }

    private static func numbered(_ line: String) -> String? {
        guard let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }), line[..<dot].allSatisfy(\.isNumber),
              !line[..<dot].isEmpty, line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " else { return nil }
        return String(line[line.index(dot, offsetBy: 2)...])
    }
}
