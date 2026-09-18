//
//  ClipSaveTests.swift
//  ClipSaveTests
//
//  Created by Someshwar Sreeram on 4/9/26.
//

import Foundation
import SwiftUI // EventModifiers members (.command, .shift) used by shortcut tests
import Testing
@testable import ClipSave

// MARK: - Colour detection

@Suite("Colour detection")
struct ColorDetectionTests {

    @Test("Hex notation, including shorthand and alpha", arguments: [
        ("#FF5722", "#FF5722"),
        ("#ff5722", "#FF5722"),
        ("  #F57  ", "#FF5577"),
        ("#FF572280", "#FF572280")
    ])
    func hex(input: String, expected: String) {
        #expect(DetectedColor.parse(input)?.hexString == expected)
    }

    @Test("Functional rgb notation", arguments: [
        ("rgb(255, 87, 34)", "#FF5722"),
        ("rgb(255 87 34)", "#FF5722"),
        ("rgba(255, 87, 34, 0.5)", "#FF572280"),
        ("rgb(100%, 0%, 0%)", "#FF0000")
    ])
    func rgb(input: String, expected: String) {
        #expect(DetectedColor.parse(input)?.hexString == expected)
    }

    @Test("Functional hsl notation", arguments: [
        ("hsl(0, 100%, 50%)", "#FF0000"),
        ("hsl(120, 100%, 50%)", "#00FF00"),
        ("hsl(240deg, 100%, 50%)", "#0000FF"),
        ("hsl(0, 0%, 100%)", "#FFFFFF")
    ])
    func hsl(input: String, expected: String) {
        #expect(DetectedColor.parse(input)?.hexString == expected)
    }

    @Test("Non-colours are rejected", arguments: [
        "hello world",
        "#GGHHII",
        "#FF57221",           // 7 digits is not a legal length
        "rgb(300, 0, 0)",     // out of range
        "rgb(1, 2)",          // too few components
        "hsl(0, 100, 50)",    // s/l must be percentages
        "The colour is #FF5722 today",
        ""
    ])
    func rejects(input: String) {
        #expect(DetectedColor.parse(input) == nil)
    }

    @Test("Well-known colours are named, arbitrary ones are not")
    func naming() {
        #expect(DetectedColor.parse("#FF5722")?.name == "Deep Orange")
        #expect(DetectedColor.parse("#FF0000")?.name == "Red")
        // A colour nowhere near an entry in the table must stay unnamed rather
        // than being mislabelled with the nearest match.
        #expect(DetectedColor.parse("#4A2F71")?.name == nil)
    }

    @Test("Conversions round-trip through each notation")
    func conversions() throws {
        let color = try #require(DetectedColor.parse("#FF5722"))
        #expect(color.rgbString == "rgb(255, 87, 34)")
        // Re-parsing the emitted strings must land on the same colour.
        #expect(DetectedColor.parse(color.rgbString)?.hexString == "#FF5722")
        #expect(DetectedColor.parse(color.hslString)?.hexString == "#FF5722")
    }
}

// MARK: - Text transforms

@Suite("Text transforms")
struct TextTransformTests {

    @Test("Trim only offers itself when there is whitespace to remove")
    func trim() {
        #expect(TextTransform.trimWhitespace.output(for: .text("  padded  ")) == "padded")
        #expect(TextTransform.trimWhitespace.output(for: .text("tight")) == nil)
    }

    @Test("Case transforms skip text that is already in that case")
    func casing() {
        #expect(TextTransform.uppercase.output(for: .text("abc")) == "ABC")
        #expect(TextTransform.uppercase.output(for: .text("ABC")) == nil)
        #expect(TextTransform.lowercase.output(for: .text("ABC")) == "abc")
        #expect(TextTransform.lowercase.output(for: .text("abc")) == nil)
    }

    @Test("JSON formatting applies only to parseable objects and arrays")
    func json() throws {
        let formatted = try #require(
            TextTransform.formatJSON.output(for: .text(#"{"b":2,"a":1}"#))
        )
        #expect(formatted.contains("\n"))
        #expect(formatted.contains("\"a\" : 1"))
        // Keys come out sorted, so the output is deterministic.
        let aIndex = try #require(formatted.range(of: "\"a\""))
        let bIndex = try #require(formatted.range(of: "\"b\""))
        #expect(aIndex.lowerBound < bIndex.lowerBound)

        #expect(TextTransform.formatJSON.output(for: .text("not json")) == nil)
        #expect(TextTransform.formatJSON.output(for: .text("{ broken")) == nil)
        // A bare scalar isn't a document worth reformatting.
        #expect(TextTransform.formatJSON.output(for: .text("42")) == nil)
    }

    @Test("Plain-text extraction is rich-text only")
    func plainText() {
        let rtf = ClipContent.richText(Data(), "styled text")
        #expect(TextTransform.plainText.output(for: rtf) == "styled text")
        #expect(TextTransform.plainText.output(for: .text("plain")) == nil)
        #expect(TextTransform.plainText.output(for: .image(Data([1, 2, 3]))) == nil)
    }

    @Test("Images and files offer no transforms at all")
    func nonTextual() {
        let image = ClipContent.image(Data([1, 2, 3]))
        let file = ClipContent.file(URL(fileURLWithPath: "/tmp/x.txt"))
        for transform in TextTransform.allCases {
            #expect(transform.output(for: image) == nil)
            #expect(transform.output(for: file) == nil)
        }
    }
}

// MARK: - Content fingerprints

@Suite("Content fingerprints")
struct ContentHashTests {

    @Test("Same-size images with identical headers still hash differently")
    func imagesDoNotCollide() {
        // The v3.4 key was byte count plus the first 64 bytes. These two blobs
        // share both, so they used to collide and the second was dropped as a
        // duplicate.
        var a = Data(repeating: 0xAB, count: 4096)
        var b = Data(repeating: 0xAB, count: 4096)
        a[2048] = 0x01
        b[2048] = 0x02

        #expect(a.count == b.count)
        #expect(a.prefix(64) == b.prefix(64))
        #expect(ClipContent.image(a).computeHash() != ClipContent.image(b).computeHash())
    }

    @Test("Hashes are stable across calls and distinguish content kinds")
    func stability() {
        let text = ClipContent.text("hello")
        #expect(text.computeHash() == text.computeHash())
        // A file whose path equals another clip's text must not be confused
        // with it, hence the kind prefix.
        #expect(ClipContent.text("/tmp/a").computeHash()
                != ClipContent.file(URL(fileURLWithPath: "/tmp/a")).computeHash())
    }

    @Test("Clips decoded from pre-v3.5 JSON recover their hash")
    func legacyDecode() throws {
        // Written before `contentHash` existed.
        let legacy = #"{"id":"\#(UUID().uuidString)","text":"old clip","timestamp":0}"#
        let decoded = try JSONDecoder().decode(Clip.self, from: Data(legacy.utf8))
        #expect(decoded.content == .text("old clip"))
        #expect(decoded.contentHash == ClipContent.text("old clip").computeHash())
    }

    @Test("Encoding a clip and reading it back preserves the fingerprint")
    func codableRoundTrip() throws {
        let original = Clip(content: .text("round trip"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)
        #expect(decoded.contentHash == original.contentHash)
        #expect(decoded.id == original.id)
    }
}

// MARK: - Derived clip facts

@Suite("Link and colour detection on clips")
struct ClipDerivedFactsTests {

    @Test("Bare URLs are links; prose mentioning a URL is not", arguments: [
        ("https://example.com", true),
        ("http://example.com/a?b=c", true),
        ("mailto:someone@example.com", true),
        ("  https://example.com  ", true),
        ("see https://example.com for details", false),
        ("just text", false),
        ("example.com", false)  // no scheme
    ])
    func links(input: String, isLink: Bool) {
        #expect((Clip(content: .text(input)).detectedURL != nil) == isLink)
    }

    @Test("Derived facts are cached on the clip, not recomputed per access")
    func cached() {
        let clip = Clip(content: .text("#FF5722"))
        #expect(clip.detectedColor?.hexString == "#FF5722")
        #expect(clip.detectedURL == nil)
    }
}

// MARK: - Filter chips

@Suite("Clip filters")
struct ClipFilterTests {

    private let clips: [Clip] = [
        Clip(content: .text("plain words")),
        Clip(content: .text("#FF5722")),
        Clip(content: .text("https://example.com")),
        Clip(content: .richText(Data(), "styled")),
        Clip(content: .image(Data([0x89, 0x50, 0x4E, 0x47]))),
        Clip(content: .file(URL(fileURLWithPath: "/tmp/a.pdf")))
    ]

    @Test("Every clip lands in exactly one category, so counts add up")
    func partitionsCleanly() {
        let categories: [ClipFilter] = [.text, .images, .links, .files]
        for clip in clips {
            let matches = categories.filter { $0.matches(clip) }
            #expect(matches.count == 1, "\(clip.content.kind) matched \(matches.count)")
        }

        let total = categories.reduce(0) { sum, filter in
            sum + clips.filter { filter.matches($0) }.count
        }
        #expect(total == clips.count)
        #expect(clips.filter { ClipFilter.all.matches($0) }.count == clips.count)
    }

    @Test("Colour literals count as text, links do not")
    func categoryPlacement() {
        #expect(ClipFilter.text.matches(Clip(content: .text("#FF5722"))))
        #expect(!ClipFilter.links.matches(Clip(content: .text("#FF5722"))))
        #expect(ClipFilter.links.matches(Clip(content: .text("https://example.com"))))
        #expect(!ClipFilter.text.matches(Clip(content: .text("https://example.com"))))
    }
}

// MARK: - Global shortcut

@Suite("In-panel shortcuts")
struct PanelShortcutTests {

    @Test("Every action ships a distinct default, so nothing clashes out of the box")
    func defaultsAreUnique() {
        var seen: [LocalShortcut: PanelAction] = [:]
        for action in PanelAction.allCases {
            let shortcut = action.defaultShortcut
            #expect(seen[shortcut] == nil,
                    "\(action.title) collides with \(seen[shortcut]?.title ?? "")")
            seen[shortcut] = action
        }
        #expect(seen.count == PanelAction.allCases.count)
    }

    @Test("Bare keys are allowed, unlike global hotkeys")
    func bareKeysAllowed() {
        #expect(PanelAction.moveUp.defaultShortcut.modifiers.isEmpty)
        #expect(PanelAction.quickLook.defaultShortcut.modifiers.isEmpty)
        // And modified ones still carry their modifiers.
        #expect(PanelAction.focusSearch.defaultShortcut.modifiers.contains(.command))
    }

    @Test("Display strings use macOS glyph order")
    func display() {
        #expect(LocalShortcut(key: "j", modifiers: [.command, .shift]).display == "⇧⌘J")
        #expect(LocalShortcut(key: "up").display == "↑")
        #expect(LocalShortcut(key: "space").display == "Space")
        #expect(LocalShortcut(key: "escape").display == "⎋")
        #expect(LocalShortcut(key: "f", modifiers: .command).display == "⌘F")
    }

    @Test("Shortcuts survive a storage round-trip")
    func codable() throws {
        let original = [
            PanelAction.focusSearch.rawValue: LocalShortcut(key: "k", modifiers: .command),
            PanelAction.quickLook.rawValue: LocalShortcut(key: "p")
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: LocalShortcut].self, from: data)
        #expect(decoded == original)
    }

    @Test("Equality accounts for modifiers, not just the key")
    func equality() {
        #expect(LocalShortcut(key: "f") != LocalShortcut(key: "f", modifiers: .command))
        #expect(LocalShortcut(key: "f", modifiers: .command)
                == LocalShortcut(key: "f", modifiers: .command))
        #expect(LocalShortcut(key: "f", modifiers: [.command, .shift])
                != LocalShortcut(key: "f", modifiers: .command))
    }
}

@Suite("Key combinations")
struct KeyComboTests {

    @Test("The default combination survives a storage round-trip")
    func codable() throws {
        let data = try JSONEncoder().encode(KeyCombo.defaultCombo)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
        #expect(decoded == KeyCombo.defaultCombo)
        #expect(decoded.display == "⌘⇧V")
    }
}
