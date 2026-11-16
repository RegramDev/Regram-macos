import AlertsUI
import AppKit
import ChatHistoryModel
import GeneralRows
import InputDataUI
import Localization
import Postbox
import RegramCore
import RegramSignals
import SwiftSignalKit
import TGUIKit
import TelegramContext
import TelegramTheme

private struct RegramAdSamplesState: Equatable {
    var modelReady: Bool?
    var samples: [RGAdSample]?
    var error: String?
    var recordingFailed = false
    var limit = 100
}

private func regramAdSampleError(_ error: Error) -> String {
    switch error as? RGAdSampleError {
    case .capacity: return regramString("ReSieve.Capacity")
    case .damaged: return regramString("ReSieve.Damaged")
    case .changed: return regramString("ReSieve.SampleChanged")
    default: return regramString("ReSieve.StorageError")
    }
}

@available(macOS 12, *)
func RegramAdSamplesController(context: any AccountContextProtocol) -> InputDataController {
    let session = RegramAdFilterSession.get(context.account)
    let accountId = context.peerId.toInt64()
    let state = Atomic(value: RegramAdSamplesState())
    let promise = ValuePromise(RegramAdSamplesState(), ignoreRepeated: true)
    let generation = Atomic(value: UUID())

    func update(_ change: (inout RegramAdSamplesState) -> Void) {
        promise.set(
            state.modify { previous in
                var current = previous
                change(&current)
                return current
            })
    }

    func reload() {
        let revision = UUID()
        _ = generation.swap(revision)
        session.perform(
            { store in
                let samples = Result { try store.load() }
                return (samples, store.recordingFailed, RGAdSemanticClassifier.shared.prepareModel())
            },
            completion: { result in
                guard generation.with({ $0 }) == revision, !context.isFrozen else { return }
                guard case .success((let samples, let recordingFailed, let ready)) = result else { return }
                update {
                    $0.modelReady = ready
                    $0.recordingFailed = recordingFailed
                    switch samples {
                    case .success(let samples):
                        $0.samples = samples
                        $0.error = nil
                    case .failure(let error):
                        $0.error = regramAdSampleError(error)
                    }
                }
            })
    }

    func export(trainingOnly: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = trainingOnly ? "resieve-reviewed.jsonl" : "resieve-samples.jsonl"
        panel.message = regramString("ReSieve.ExportNotice")
        panel.beginSheetModal(for: context.window) { response in
            guard response == .OK, let url = panel.url, !context.isFrozen else { return }
            session.perform(
                { store in
                    try store.export(trainingOnly: trainingOnly).write(to: url, options: .atomic)
                },
                completion: { result in
                    if case .failure(let error) = result, !context.isFrozen {
                        alert(for: context.window, info: regramAdSampleError(error))
                    }
                })
        }
    }

    let signal =
        combineLatest(promise.get(), regramPreferenceChanges(accountId: accountId, keys: ["reSieveEnabled"]), appearanceSignal)
        |> map { state, settings, _ -> InputDataSignalValue in
            var page = RegramPageBuilder(page: "reSieve")
            page.section()
            page.row(
                "enabled", title: regramString("ReSieve.Enable"), type: .switchable(settings["reSieveEnabled"].bool),
                action: {
                    RegramPreferences.shared.update(accountId: accountId) { $0["reSieveEnabled"] = .bool(!$0["reSieveEnabled"].bool) }
                })
            let modelStatus = state.modelReady.map { $0 ? "ReSieve.Ready" : "ReSieve.Unavailable" } ?? "ReSieve.Checking"
            page.row("model", title: regramString("ReSieve.Model"), type: .context(regramString(modelStatus)))
            page.text(regramString("ReSieve.Notice"))
            page.section("ReSieve.Samples")
            if let error = state.error {
                page.text(error)
            } else if let samples = state.samples {
                let ready = samples.filter(\.isTrainingReady).count
                if !samples.isEmpty {
                    page.text(String(format: regramString("ReSieve.SampleCount"), samples.count, ready))
                }
                if samples.count >= RGAdSampleStore.maximumSamples {
                    page.text(regramString("ReSieve.Capacity"))
                } else if state.recordingFailed {
                    page.text(regramString("ReSieve.StorageError"))
                }
                if samples.isEmpty {
                    let emptyText = regramString("ReSieve.EmptySamples")
                    page.custom("empty", equatable: InputDataEquatable(emptyText)) { size, stableId in
                        RegramEmptyRowItem(size, stableId: stableId, height: 112, text: emptyText, symbolName: "tray")
                    }
                } else {
                    page.row("export", title: regramString("ReSieve.ExportAll"), action: { export(trainingOnly: false) })
                    page.row(
                        "exportReviewed", title: regramString("ReSieve.ExportReviewed"), enabled: ready > 0,
                        action: { export(trainingOnly: true) })
                    page.section()
                    for sample in samples.prefix(state.limit) {
                        let firstLine = sample.input.text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(120)) }
                        let title = firstLine ?? sample.input.buttons.first?.first?.title ?? regramString("ReSieve.Media")
                        var status = regramString(sample.reviewedAt == nil ? "ReSieve.Pending" : "ReSieve.Reviewed")
                        if let detection = sample.detection {
                            let outcome: String
                            if detection.hidMessage {
                                outcome = "ReSieve.HiddenMessage"
                            } else if !detection.removedRanges.isEmpty {
                                outcome = "ReSieve.TrimmedText"
                            } else {
                                outcome = "ReSieve.HiddenButtons"
                            }
                            status = regramString(outcome) + " · " + status
                        }
                        page.row(
                            sample.id, title: title, type: .next, description: status,
                            action: {
                                context.bindings.rootNavigation().push(regramAdSampleEditor(context: context, original: nil, sample: sample))
                            })
                    }
                    if samples.count > state.limit {
                        page.row("more", title: regramString("ReSieve.More"), action: { update { $0.limit += 100 } })
                    }
                }
            } else {
                let loadingText = regramString("ReSieve.Loading")
                page.custom("loading", equatable: InputDataEquatable(loadingText)) { size, stableId in
                    RegramEmptyRowItem(size, stableId: stableId, height: 112, isLoading: true, text: loadingText)
                }
            }
            return InputDataSignalValue(entries: page.entries)
        }
    let controller = RegramFormController(
        dataSignal: signal, title: regramString("ReSieve.Title"), removeAfterDisappear: false, hasDone: false, identifier: "regram.reSieve")
    controller.didAppear = { _ in reload() }
    controller.willDisappear = { _ in _ = generation.swap(UUID()) }
    return controller
}

@available(macOS 12, *)
public func RegramAdSampleController(context: any AccountContextProtocol, message: Message) -> InputDataController? {
    let original = rgAdOriginalMessage(message)
    guard rgCanCorrectAds(original) else { return nil }
    return regramAdSampleEditor(context: context, original: original, sample: nil)
}

private struct RegramAdSampleDraft: Equatable {
    var sample: RGAdSample?
    var error: String?
    var saving = false
}

@available(macOS 12, *)
private func regramAdSampleEditor(context: any AccountContextProtocol, original: Message?, sample: RGAdSample?) -> InputDataController {
    let session = RegramAdFilterSession.get(context.account)
    let initial = RegramAdSampleDraft(sample: sample)
    let draft = Atomic(value: initial)
    let promise = ValuePromise(initial, ignoreRepeated: true)
    let selection = Atomic(value: NSRange(location: 0, length: 0))
    let visible = Atomic(value: false)
    let loadGeneration = Atomic(value: UUID())

    func update(_ change: (inout RegramAdSampleDraft) -> Void) {
        promise.set(
            draft.modify { previous in
                var current = previous
                change(&current)
                return current
            })
    }

    func edit(_ change: (inout RGAdSample) -> Void) {
        update {
            guard !$0.saving, var sample = $0.sample else { return }
            change(&sample)
            $0.sample = sample
        }
    }

    func mark(_ label: RGAdLabel) {
        let range = selection.with { $0 }
        guard range.length > 0 else {
            alert(for: context.window, info: regramString("ReSieve.SelectText"))
            return
        }
        edit { try? $0.mark(range, as: label) }
    }

    func markAll(_ label: RGAdLabel) {
        edit { sample in
            let length = sample.input.text.utf16.count
            if length > 0 { try? sample.mark(NSRange(location: 0, length: length), as: label) }
            for id in Array(sample.buttonLabels.keys) { sample.buttonLabels[id] = label }
            sample.mediaLabel = label
        }
    }

    func preview() {
        guard let sample = draft.with({ $0.sample }) else { return }
        session.perform(
            { _ in sample.previewText },
            completion: { result in
                guard visible.with({ $0 }), !context.isFrozen, case .success(let text) = result else { return }
                showModalText(
                    for: context.window, text: text.isEmpty ? regramString("ReSieve.EmptyPreview") : text,
                    title: regramString("ReSieve.Preview"))
            })
    }

    func persist(_ sample: RGAdSample, remove: Bool) {
        guard !context.isFrozen, !draft.with({ $0.saving }) else { return }
        update { $0.saving = true }
        session.perform(
            changes: true,
            { store in
                if remove { try store.remove(sample) } else { try store.save(sample) }
            },
            completion: { result in
                update { $0.saving = false }
                guard visible.with({ $0 }), !context.isFrozen else { return }
                switch result {
                case .success:
                    context.bindings.rootNavigation().back()
                case .failure(let error):
                    alert(for: context.window, info: regramAdSampleError(error))
                }
            })
    }

    func labelTitle(_ label: RGAdLabel) -> String {
        switch label {
        case .normal: return regramString("ReSieve.Normal")
        case .ad: return regramString("ReSieve.Ad")
        case .uncertain: return regramString("ReSieve.Uncertain")
        }
    }

    func choices(_ label: RGAdLabel, action: @escaping (RGAdLabel) -> Void) -> GeneralInteractedType {
        .contextSelector(
            labelTitle(label),
            RGAdLabel.allCases.map { option in
                ContextMenuItem(labelTitle(option), handler: { action(option) }, state: option == label ? .on : .off)
            })
    }

    let signal =
        combineLatest(promise.get(), appearanceSignal)
        |> map { state, _ -> InputDataSignalValue in
            var page = RegramPageBuilder(page: "reSieve.sample")
            page.section()
            guard let sample = state.sample else {
                page.text(state.error ?? regramString("ReSieve.Loading"))
                return InputDataSignalValue(entries: page.entries)
            }
            if !sample.input.text.isEmpty {
                page.text(regramString("ReSieve.MarkText"), header: true)
                page.custom(
                    "original", equatable: InputDataEquatable(sample.spans),
                    item: { size, id in
                        RegramAdSampleTextItem(size, stableId: id, sample: sample, selection: selection)
                    })
                page.row("normal", title: regramString("ReSieve.MarkNormal"), enabled: !state.saving, action: { mark(.normal) })
                page.row("ad", title: regramString("ReSieve.MarkAd"), enabled: !state.saving, action: { mark(.ad) })
                page.row("uncertain", title: regramString("ReSieve.MarkUncertain"), enabled: !state.saving, action: { mark(.uncertain) })
            }
            if !sample.buttonLabels.isEmpty || !sample.mediaKinds.isEmpty {
                page.section("ReSieve.Attachments")
                for button in sample.input.buttons.flatMap({ $0 }) {
                    page.row(
                        "button." + button.id, title: button.title,
                        type: choices(
                            sample.buttonLabels[button.id] ?? .uncertain,
                            action: { label in
                                edit { $0.buttonLabels[button.id] = label }
                            }), enabled: !state.saving, description: button.target)
                }
                if !sample.mediaKinds.isEmpty {
                    page.row(
                        "media", title: regramString("ReSieve.Media"),
                        type: choices(
                            sample.mediaLabel,
                            action: { label in
                                edit { $0.mediaLabel = label }
                            }), enabled: !state.saving)
                }
            }
            page.section()
            page.row("allNormal", title: regramString("ReSieve.AllNormal"), enabled: !state.saving, action: { markAll(.normal) })
            page.row("allAd", title: regramString("ReSieve.AllAd"), enabled: !state.saving, action: { markAll(.ad) })
            page.row("preview", title: regramString("ReSieve.Preview"), enabled: !state.saving, action: preview)
            page.row(
                "save", title: regramString("ReSieve.Save"), type: state.saving ? .loading : .none, enabled: !state.saving,
                action: {
                    if let current = draft.with({ $0.sample }) { persist(current, remove: false) }
                })
            if sample.reviewedAt != nil || sample.detection != nil {
                page.section()
                page.row(
                    "delete", title: regramString("ReSieve.Delete"), enabled: !state.saving, color: theme.colors.redUI,
                    action: {
                        verifyAlert(
                            for: context.window, header: regramString("ReSieve.Delete"), information: regramString("ReSieve.DeleteNotice"),
                            successHandler: { _ in
                                persist(sample, remove: true)
                            })
                    })
            }
            return InputDataSignalValue(entries: page.entries)
        }
    let controller = RegramFormController(
        dataSignal: signal, title: regramString("ReSieve.Correct"), removeAfterDisappear: false, hasDone: false,
        identifier: "regram.reSieve.sample")
    controller.didAppear = { _ in
        _ = visible.swap(true)
        guard let original, draft.with({ $0.sample == nil }) else { return }
        let revision = UUID()
        _ = loadGeneration.swap(revision)
        session.perform(
            { try rgAdSampleDraft(original, store: $0) },
            completion: { result in
                guard visible.with({ $0 }), loadGeneration.with({ $0 }) == revision else { return }
                update {
                    switch result {
                    case .success(let sample): $0.sample = sample
                    case .failure(let error): $0.error = regramAdSampleError(error)
                    }
                }
            })
    }
    controller.willDisappear = { _ in _ = visible.swap(false) }
    return controller
}

private final class RegramAdSampleTextItem: GeneralRowItem {
    let sample: RGAdSample
    let selection: Atomic<NSRange>

    init(_ size: NSSize, stableId: AnyHashable, sample: RGAdSample, selection: Atomic<NSRange>) {
        self.sample = sample
        self.selection = selection
        super.init(size, height: 224, stableId: stableId, viewType: .singleItem)
    }

    override func viewClass() -> AnyClass { RegramAdSampleTextView.self }
}

private final class RegramAdSampleTextView: GeneralContainableRowView, NSTextViewDelegate {
    private let scroll = NSScrollView()
    private let textView = NSTextView()
    private var binding = false

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 7, height: 6)
        textView.delegate = self
        textView.setAccessibilityLabel(regramString("ReSieve.Original"))
        scroll.documentView = textView
        containerView.addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RegramAdSampleTextItem else { return }
        binding = true
        defer { binding = false }
        let body = NSMutableAttributedString(
            string: item.sample.input.text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: theme.colors.text])
        for span in item.sample.spans where NSMaxRange(span.range.nsRange) <= body.length {
            let color = span.label == .ad ? NSColor.systemRed : NSColor.systemOrange
            body.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.24), range: span.range.nsRange)
        }
        textView.textStorage?.setAttributedString(body)
        let range = item.selection.with { $0 }
        if NSMaxRange(range) <= body.length { textView.setSelectedRange(range) }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !binding, let item = item as? RegramAdSampleTextItem else { return }
        _ = item.selection.swap(textView.selectedRange())
    }

    override func layout() {
        super.layout()
        scroll.frame = containerView.bounds.insetBy(dx: 6, dy: 4)
        textView.minSize = scroll.contentSize
        textView.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(textView.frame.height, scroll.contentSize.height)))
    }
}
