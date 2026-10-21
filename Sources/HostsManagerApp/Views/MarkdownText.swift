import AppKit
import SwiftUI

/// AI replies as Markdown: headings, bullet / numbered lists, quotes, tables, rules, fenced code (monospaced, with
/// Copy — hosts lines are meant to be pasted) and paragraphs; inline **bold**, *italic*, `code` and links come from
/// Foundation's own Markdown. Line-based so a half-streamed reply (an unclosed ``` fence) still renders.
struct MarkdownText: View {
    let text: String

    enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case bullet(level: Int, text: String)
        case numbered(marker: String, text: String)
        case quote(String)
        case code(String)
        case table([[String]])
        case rule
        case paragraph(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in view(block) }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Parsing (pure, unit-tested)

    nonisolated static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = [], paragraph: [String] = [], table: [[String]] = []
        var code: [String]?
        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        func flushTable() {
            if !table.isEmpty { blocks.append(.table(table)) }
            table = []
        }
        func flush() {
            flushParagraph()
            flushTable()
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var lines = code {  // inside a fence
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    lines.append(line)
                    code = lines
                }
                continue
            }
            if trimmed.hasPrefix("|") {
                flushParagraph()
                if let cells = tableRow(trimmed) { table.append(cells) }
                continue
            }
            if let block = singleLineBlock(line, trimmed) {
                flush()
                if block != .paragraph("") { blocks.append(block) }
            } else if trimmed.hasPrefix("```") {
                flush()
                code = []
            } else {
                flushTable()
                paragraph.append(trimmed)
            }
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }  // still streaming
        flush()
        return blocks
    }

    /// `| a | b |` → cells; nil for the `|---|:--|` separator row.
    private nonisolated static func tableRow(_ line: String) -> [String]? {
        let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        return cells.allSatisfy { $0.allSatisfy { "-: ".contains($0) } } ? nil : cells
    }

    /// A line that is a block on its own; `.paragraph("")` = blank line (ends the paragraph). nil = paragraph text.
    private nonisolated static func singleLineBlock(_ line: String, _ trimmed: String) -> Block? {
        if trimmed.isEmpty { return .paragraph("") }
        if ["---", "***", "___"].contains(trimmed) { return .rule }
        if let hashes = trimmed.firstIndex(where: { $0 != "#" }), trimmed.hasPrefix("#"),
           trimmed[hashes] == " ", trimmed.distance(from: trimmed.startIndex, to: hashes) <= 6 {
            return .heading(level: trimmed.distance(from: trimmed.startIndex, to: hashes),
                            text: String(trimmed[hashes...]).trimmingCharacters(in: .whitespaces))
        }
        if let marker = ["- ", "* ", "+ "].first(where: { trimmed.hasPrefix($0) }) {
            let indent = line.prefix { $0 == " " }.count
            return .bullet(level: min(indent / 2, 3), text: String(trimmed.dropFirst(marker.count)))
        }
        if let match = trimmed.firstMatch(of: /^(\d{1,3}[.)])\s+(.*)$/) {
            return .numbered(marker: String(match.1), text: String(match.2))
        }
        if trimmed.hasPrefix(">") {
            return .quote(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    // MARK: - Views

    @ViewBuilder
    private func view(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text).font(level <= 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
        case .bullet(let level, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(text)
            }
            .padding(.leading, CGFloat(level) * 14)
        case .numbered(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).monospacedDigit().foregroundStyle(.secondary)
                inline(text)
            }
        case .quote(let text):
            inline(text)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Capsule().fill(.tertiary).frame(width: 3) }
        case .code(let code):
            CodeBlock(code: code)
        case .table(let rows):
            table(rows)
        case .rule:
            Divider()
        case .paragraph(let text):
            inline(text)
        }
    }

    private func inline(_ markdown: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown))
    }

    private func table(_ rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                GridRow {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        inline(cell).fontWeight(index == 0 ? .semibold : .regular)
                    }
                }
                if index == 0 { Divider() }
            }
        }
    }
}

/// Fenced code: monospaced, scrolls sideways, Copy flips to ✓ for 1.5 s.
private struct CodeBlock: View {
    let code: String
    @State private var copied = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.callout.monospaced())
                .padding(10)
                .padding(.trailing, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))  // long lines scroll inside the block, not past the panel
        .overlay(alignment: .topTrailing) {
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .padding(4)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 5))  // over scrolled text
            }
            .buttonStyle(.borderless)
            .padding(5)
            .help(localized(copied ? "raw.copied" : "btn.copy"))
            .accessibilityLabel(localized(copied ? "raw.copied" : "btn.copy"))
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
