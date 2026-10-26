import Cocoa
import RegramCore
import TGUIKit
import TelegramCore
import InAppSettings
import SwiftSignalKit
import Postbox
import TelegramMedia
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import TelegramMediaResources
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import AudioPlayerCore
import ChatHistoryModel
import InputTextView

public func canTranscribeMessage(_ message: Message, context: any AccountContextProtocol) -> Bool {
    if message.autoclearTimeout != nil {
        return false
    }
    let file = message.media.first! as! TelegramMediaFile
    if regramCanTranscribe(message, settings: RegramPreferences.shared.settings(accountId: context.peerId.toInt64())) {
        return true
    }
    if context.isPremium {
        return true
    } else {
        let has_trial = context.appConfiguration.getGeneralValue("transcribe_audio_trial_weekly_number", orElse: 0) > 0
        let max_trial_duration = context.appConfiguration.getGeneralValue("transcribe_audio_trial_duration_max", orElse: 0)
        if has_trial, max_trial_duration > Int(file.duration ?? 0) {
            return true
        } else {
            return false
        }
    }
}

public class ChatMediaVoiceLayoutParameters : ChatMediaLayoutParameters {
    
    public enum TranscribeState {
        case possible
        case locked
        case state(TranscribeAudioState)
    }
    
    public final class TranscribeData {
        public let state: TranscribeState
        public let text: FoldingTextLayout?
        public let isPending: Bool
        public let isTranslateLoading: Bool
        public let fontColor: NSColor
        public let backgroundColor: NSColor
        public init(state: TranscribeState, text: FoldingTextLayout?, isPending: Bool, isTranslateLoading: Bool = false, fontColor: NSColor, backgroundColor: NSColor) {
            self.state = state
            self.text = text
            self.isPending = isPending
            self.isTranslateLoading = isTranslateLoading
            self.fontColor = fontColor
            self.backgroundColor = backgroundColor
        }

        public let dotsSize: NSSize = NSMakeSize(18, 18)

        public func makeSize(_ width: CGFloat) -> NSSize? {
            switch state {
            case .possible:
                self.size = nil
            case .locked:
                self.size = nil
            case  let .state(state):
                switch state {
                case .loading:
                    self.size = nil
                case .collapsed:
                    self.size = nil
                case .revealed:
                    if let textLayout = text {
                        textLayout.measure(width: width)

                        var size = NSMakeSize(width, textLayout.size.height)
                        if let line = textLayout.lastLine {
                            if line.frame.maxX + dotsSize.width > width {
                                size.height += 10
                            }
                        }
                        self.size = size
                    } else {
                        self.size = dotsSize
                    }
                }
            }
            return self.size
        }

        public var size: NSSize?
    }
    
    public let showPlayer:(APController) -> Void
    public let waveform:AudioWaveform?
    public let durationLayout:TextViewLayout
    public let isMarked:Bool
    public let isWebpage:Bool
    public let resource: TelegramMediaResource
    public var waveformWidth:CGFloat = 120
    public let duration: Double
    
    public var transcribe:()->Void = {}
    
    public var transcribeData: TranscribeData?
    
    public init(showPlayer:@escaping(APController) -> Void, waveform:AudioWaveform?, duration: Double, isMarked:Bool, isWebpage: Bool, resource: TelegramMediaResource, presentation: ChatMediaPresentation, media: Media, automaticDownload: Bool) {
        self.showPlayer = showPlayer
        self.waveform = waveform
        self.duration = duration
        self.isMarked = isMarked
        self.isWebpage = isWebpage
        self.resource = resource
        durationLayout = TextViewLayout(NSAttributedString.initialize(string: String.durationTransformed(elapsed: duration), color: presentation.grayText, font: .normal(.text)), maximumNumberOfLines: 1, truncationType:.end, alignment: .left)
        super.init(presentation: presentation, media: media, automaticDownload: automaticDownload, autoplayMedia: AutoplayMediaPreferences.defaultSettings, isRevealed: nil)
    }
    
    public func duration(for duration:TimeInterval) -> TextViewLayout {
        return TextViewLayout(NSAttributedString.initialize(string: String.durationTransformed(elapsed: Int(round(duration))), color: presentation.grayText, font: .normal(.text)), maximumNumberOfLines: 1, truncationType:.end, alignment: .left)
    }
}
