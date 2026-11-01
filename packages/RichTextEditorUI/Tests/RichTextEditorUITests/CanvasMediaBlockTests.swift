#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
private final class FlippedContainer: NSView { override var isFlipped: Bool { true } }

/// Phase 1 (package side) of media attachments: inserting a media block, the interactive host overlay's
/// pass-through hit-testing, and the host-view sync (realize/pool by id, learn the view's height back
/// into the box, remove on deletion).
@available(macOS 12, *)
final class CanvasMediaBlockTests: AppKitTestCase {

    private func seeded() -> (DocumentCanvasView, NSWindow) {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "hello")]))], width: 400)
        let win = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        return (v, win)
    }

    private func mediaBoxes(_ v: DocumentCanvasView) -> [MediaBlockBox] { v.boxes.compactMap { $0 as? MediaBlockBox } }

    private func pressReturn(_ v: DocumentCanvasView, shift: Bool, in win: NSWindow) {
        let flags: NSEvent.ModifierFlags = shift ? [.shift] : []
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: win.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        v.keyDown(with: e)
    }

    func test_imagesAndVideos_routeToHostedMediaBoxes() throws {
        XCTAssertEqual(RichTextEditorUI.MediaKind(rawValue: "video"), RichTextEditorUI.MediaKind.video, "the host inserts video via the \"video\" kind string")
        let v = DocumentCanvasView()
        v.setModelBlocks([
            .media(MediaBlock(id: BlockID("v"), kind: .video, mediaID: "vid")),       // hosted chat node
            .media(MediaBlock(id: BlockID("i"), kind: .image, mediaID: "img", naturalSize: Size2D(width: 10, height: 10))),
        ], width: 400)
        XCTAssertTrue(v.boxes[0] is MediaBlockBox, "video renders as a hosted media view, like file/audio/map")
        XCTAssertFalse(v.boxes[0] is ImageBlockBox)
        let video = try XCTUnwrap(v.boxes[0] as? MediaBlockBox)
        let image = try XCTUnwrap(v.boxes[1] as? MediaBlockBox)
        XCTAssertEqual(video.kind, .video)
        XCTAssertEqual(image.kind, .image)
        XCTAssertEqual(image.mediaID, "img")
    }

    func test_videoBleedsFullWidth_otherMediaDont() {
        func box(_ kind: RichTextEditorUI.MediaKind) -> MediaBlockBox {
            MediaBlockBox(media: RichTextEditorUI.MediaBlock(id: BlockID("m"), kind: kind, mediaID: "x"),
                          mapper: AttributedStringMapper(), width: 300)
        }
        XCTAssertTrue(box(.video).mediaBleeds, "video fills the full bled width, like a photo")
        XCTAssertFalse(box(.file).mediaBleeds)
        XCTAssertFalse(box(.audio).mediaBleeds)
        XCTAssertFalse(box(.map).mediaBleeds)
    }

    func test_insertMediaBlock_acceptsHostedImageKind() throws {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart)
        v.insertMediaBlock(kind: .image, mediaID: "x")
        XCTAssertEqual(mediaBoxes(v).count, 1)
        let image = try XCTUnwrap(mediaBoxes(v).first)
        XCTAssertEqual(image.kind, .image)
        XCTAssertEqual(image.mediaID, "x")
        XCTAssertEqual(v.head, image.textStart)
        XCTAssertFalse(v.boxes.contains { $0 is ImageBlockBox })
    }

    func test_clickSelectsMedia_thenBackspaceDeletesIt() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
        v.insertMediaBlock(kind: .file, mediaID: "m1")
        let media = mediaBoxes(v).first!
        v.selectMediaBlock(id: media.id)                                   // simulate a click on the media
        XCTAssertEqual(v.mediaBoxesInSelection().map { $0.id }, [media.id], "clicking selects (highlights) the media block")
        XCTAssertNotNil(v.soleSelectedMediaBlock(), "it's a sole-media selection")
        v.performDeleteBackward()
        XCTAssertEqual(mediaBoxes(v).count, 0, "Backspace removes the click-selected media block")
    }

    func test_clickMediaTwice_togglesSelectionOff() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
        v.insertMediaBlock(kind: .file, mediaID: "m1")
        let media = mediaBoxes(v).first!
        v.selectMediaBlock(id: media.id)
        XCTAssertNotNil(v.soleSelectedMediaBlock(), "first click selects")
        v.selectMediaBlock(id: media.id)
        XCTAssertNil(v.soleSelectedMediaBlock(), "second click deselects (toggle)")
        v.selectMediaBlock(id: media.id)
        XCTAssertNotNil(v.soleSelectedMediaBlock(), "third click re-selects")
    }

    func test_shiftEnterInMediaCaption_exitsIntoNewParagraph() {
        let (v, win) = seeded()
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
        v.insertMediaBlock(kind: .file, mediaID: "m1")                     // caret in the media caption
        let mediaIdx = v.boxes.firstIndex { $0 is MediaBlockBox }!
        pressReturn(v, shift: true, in: win)
        XCTAssertTrue(v.boxes[mediaIdx + 1] is BlockBox, "Shift+Enter inserts a body paragraph after the media")
        XCTAssertEqual(v.head, v.boxes[mediaIdx + 1].textStart, "caret exits the caption into that paragraph")
    }

    func test_selectAllCoversLeadingMedia_andDeleteClearsEverything() {
        let v = DocumentCanvasView()
        v.setModelBlocks([
            .media(MediaBlock(id: BlockID("m"), kind: .map, mediaID: "x")),                      // leading media
            .core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "hello")]))),
            .media(MediaBlock(id: BlockID("f"), kind: .file, mediaID: "y")),
            .core(.paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "bye")]))),
        ], width: 400)
        v.selectAllText()
        let selected = Set(v.mediaBoxesInSelection().map { $0.id })
        XCTAssertTrue(selected.contains(BlockID("m")), "select-all covers the LEADING media block")
        XCTAssertTrue(selected.contains(BlockID("f")), "select-all covers the other media block")

        v.performDeleteBackward()
        XCTAssertEqual(mediaBoxes(v).count, 0, "select-all + delete removes every media block")
        XCTAssertEqual(v.currentBlocks().count, 1, "the document collapses to a single (empty) paragraph")
        XCTAssertEqual(v.currentBlocks().first.flatMap { if case .paragraph(let p) = $0 { return p.runs.count } else { return nil } }, 0,
                       "and that paragraph is empty")
    }

    func test_emptyCaption_reservesALine() {
        let box = MediaBlockBox(media: MediaBlock(id: BlockID("m"), kind: .file, mediaID: "x"), mapper: AttributedStringMapper(), width: 300)
        let belowMedia = box.height - (MediaBlockBox.verticalInset * 2 + box.mediaAreaHeight + MediaBlockBox.captionGap)
        XCTAssertGreaterThan(belowMedia, 12, "an empty caption still reserves ~a line so the 'Add caption…' placeholder doesn't overflow")
    }

    func test_insertMediaBlock_addsBoxAndLandsCaretInCaption() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)   // end of "hello"
        v.insertMediaBlock(kind: .file, mediaID: "m1")
        XCTAssertEqual(mediaBoxes(v).count, 1, "a media block was inserted")
        XCTAssertEqual(v.head, mediaBoxes(v).first!.textStart, "caret lands in the media's caption")
        XCTAssertNotNil(v.leafRegion(containingGlobal: v.head), "the caption is an editable text region")
    }

    func test_emptyMediaCaption_showsAddCaptionPlaceholder() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
        v.insertMediaBlock(kind: .file, mediaID: "m1")
        XCTAssertTrue(v.placeholderDraws().contains { $0.text == "Add caption…" }, "an empty media caption shows the placeholder")
        v.commitText("x")
        XCTAssertFalse(v.placeholderDraws().contains { $0.text == "Add caption…" }, "typing a caption hides the placeholder")
    }

    func test_canTypeIntoMediaCaption() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
        v.insertMediaBlock(kind: .file, mediaID: "m1")                     // caret in the caption
        v.commitText("hi")
        let media = mediaBoxes(v).first!
        XCTAssertEqual(media.caption.length, 2, "typed text goes into the media caption")
        guard case .media(let m) = media.currentModelBlock() else { return XCTFail() }
        XCTAssertEqual(m.caption.map { $0.text }.joined(), "hi", "the caption round-trips into the model")
    }

    func test_interactiveOverlay_hitsMediaButPassesEmptyAreasThrough() {
        let host = FlippedContainer(frame: NSMakeRect(0, 0, 200, 200))
        let overlay = InteractiveMediaOverlayView(frame: NSMakeRect(0, 0, 200, 200))
        host.addSubview(overlay)
        let media = NSView(frame: NSMakeRect(10, 10, 50, 50))
        overlay.addSubview(media)
        XCTAssertEqual(overlay.hitTest(NSMakePoint(20, 20)), media, "a hit inside a media view reaches it")
        XCTAssertNil(overlay.hitTest(NSMakePoint(120, 120)), "an empty area passes through (nil), so text editing still works")
    }

    func test_backspaceAtMediaCaptionStart_deletesIt_andUndoRestores() {
        let (v, _) = seeded()
        let um = UndoManager(); um.groupsByEvent = false; v.undoManagerOverride = um
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)   // end of "hello"
        um.beginUndoGrouping(); v.insertMediaBlock(kind: .file, mediaID: "m1"); um.endUndoGrouping()
        XCTAssertEqual(mediaBoxes(v).count, 1)
        XCTAssertEqual(v.head, mediaBoxes(v).first!.textStart, "caret is at the empty caption start")

        um.beginUndoGrouping(); v.performDeleteBackward(); um.endUndoGrouping()  // backspace at empty-caption start
        XCTAssertEqual(mediaBoxes(v).count, 0, "backspace at the empty caption start deletes the media block")

        um.undo()
        XCTAssertEqual(mediaBoxes(v).count, 1, "undo restores the media block")
        XCTAssertEqual(mediaBoxes(v).first?.mediaID, "m1", "the restored block keeps its mediaID")
    }

    func test_backspaceOnMediaAtom_deletesIt() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
        v.insertMediaBlock(kind: .map, mediaID: "m2")
        let media = mediaBoxes(v).first!
        v.setCaret(global: media.nodeStart)                                // caret resolves onto the atom
        v.performDeleteBackward()
        XCTAssertEqual(mediaBoxes(v).count, 0, "backspace with the caret on the media atom deletes it")
    }

    func test_selectionCoveringMedia_marksItSelected_andDeleteRemovesIt() {
        // [hello, media, world] — select from inside "hello" across the media into "world".
        let v = DocumentCanvasView()
        v.setModelBlocks([
            .core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "hello")]))),
            .media(MediaBlock(id: BlockID("m"), kind: .file, mediaID: "x")),
            .core(.paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "world")]))),
        ], width: 400)
        let media = mediaBoxes(v).first!
        v.setCaret(global: v.boxes[0].textStart + 2)                       // anchor inside "hello"
        v.setSelectionHead(global: v.boxes[2].textStart + 2)               // head inside "world", across the media
        XCTAssertEqual(v.mediaBoxesInSelection().map { $0.id }, [media.id], "the spanned media is part of the selection")

        v.applySelectionReplace(globalFrom: v.selFrom, globalTo: v.selTo, text: "")
        XCTAssertEqual(mediaBoxes(v).count, 0, "deleting a selection that spans a media block removes it")
    }

    func test_selectionInsideCaptionOnly_doesNotMarkMediaSelected() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
        v.insertMediaBlock(kind: .file, mediaID: "m1")
        v.commitText("cap")                                                // caption = "cap", caret after it
        let media = mediaBoxes(v).first!
        v.setCaret(global: media.textStart)                                // caption start
        v.setSelectionHead(global: media.textStart + 3)                    // select the caption text only
        XCTAssertTrue(v.mediaBoxesInSelection().isEmpty, "selecting only caption text does not select the media area")
    }

    func test_syncRealizesHostView_learnsHeight_andRemovesOnDeletion() {
        let (v, _) = seeded()
        v.mediaBlockViewProvider = { _, _, _, width in NSView(frame: NSMakeRect(0, 0, width, 80)) }
        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
        v.insertMediaBlock(kind: .file, mediaID: "m1")
        v.layoutSubtreeIfNeeded()

        XCTAssertEqual(v.mediaBlockViews.count, 1, "the provider's view is realized and pooled")
        XCTAssertTrue(v.mediaBlockViews.values.allSatisfy { $0.view.superview === v.mediaBlockHost },
                      "the media view is hosted in the interactive overlay (+ its click/selection overlay)")
        XCTAssertEqual(mediaBoxes(v).first?.hostHeight, 80, "the box learns the host view's height")

        // Replace the document with one that has no media block → the host view is torn down.
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("q"), runs: [TextRun(text: "bye")]))], width: 400)
        v.layoutSubtreeIfNeeded()
        XCTAssertTrue(v.mediaBlockViews.isEmpty, "removing the block removes its host view")
        XCTAssertTrue(v.mediaBlockHost.subviews.isEmpty)
    }
}
#endif
