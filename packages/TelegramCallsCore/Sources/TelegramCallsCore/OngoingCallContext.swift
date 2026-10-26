import Cocoa
import Foundation
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Postbox
import TgVoipWebrtc
import TGUIKit
import TelegramVoip
import Localization
import ColorPalette
import TelegramContext
import TelegramUtils
import AVFoundation
import TelegramMediaUtils
import SystemPermissions
import ProxyUtils






private func callConnectionDescriptionsWebrtc(_ connection: CallSessionConnection, idMapping: [Int64: UInt8]) -> [OngoingCallConnectionDescriptionWebrtc] {
    switch connection {
    case let .reflector(reflector):
        guard let id = idMapping[reflector.id] else {
            return []
        }
        var result: [OngoingCallConnectionDescriptionWebrtc] = []
        if !reflector.ip.isEmpty {
            result.append(OngoingCallConnectionDescriptionWebrtc(reflectorId: id, hasStun: false, hasTurn: true, hasTcp: reflector.isTcp, ip: reflector.ip, port: reflector.port, username: "reflector", password: hexString(reflector.peerTag)))
        }
        if !reflector.ipv6.isEmpty {
            result.append(OngoingCallConnectionDescriptionWebrtc(reflectorId: id, hasStun: false, hasTurn: true, hasTcp: reflector.isTcp, ip: reflector.ipv6, port: reflector.port, username: "reflector", password: hexString(reflector.peerTag)))
        }
        return result
    case let .webRtcReflector(reflector):
        var result: [OngoingCallConnectionDescriptionWebrtc] = []
        if !reflector.ip.isEmpty {
            result.append(OngoingCallConnectionDescriptionWebrtc(reflectorId: 0, hasStun: reflector.hasStun, hasTurn: reflector.hasTurn, hasTcp: false, ip: reflector.ip, port: reflector.port, username: reflector.username, password: reflector.password))
        }
        if !reflector.ipv6.isEmpty {
            result.append(OngoingCallConnectionDescriptionWebrtc(reflectorId: 0, hasStun: reflector.hasStun, hasTurn: reflector.hasTurn, hasTcp: false, ip: reflector.ipv6, port: reflector.port, username: reflector.username, password: reflector.password))
        }
        return result
    }
}




/*private func callConnectionDescriptionWebrtcCustom(_ connection: CallSessionConnection) -> OngoingCallConnectionDescriptionWebrtcCustom {
 return OngoingCallConnectionDescriptionWebrtcCustom(connectionId: connection.id, ip: connection.ip, ipv6: connection.ipv6, port: connection.port, peerTag: connection.peerTag)
 }*/

private let callLogsLimit = 20

public func callLogNameForId(id: Int64, account: Account) -> String? {
    let path = callLogsPath(account: account)
    let namePrefix = "\(id)_"
    
    if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants], errorHandler: nil) {
        for url in enumerator {
            if let url = url as? URL {
                if url.lastPathComponent.hasPrefix(namePrefix) {
                    return url.lastPathComponent
                }
            }
        }
    }
    return nil
}

public func callLogsPath(account: Account) -> String {
    return account.basePath + "/calls"
}

private func cleanupCallLogs(account: Account) {
    let path = callLogsPath(account: account)
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: path, isDirectory: nil) {
        try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
    }
    
    var files: [(URL, Date)] = []
    if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants], errorHandler: nil) {
        for url in enumerator {
            if let url = url as? URL, let date = (try? url.resourceValues(forKeys: Set([.contentModificationDateKey])))?.contentModificationDate {
                files.append((url, date))
            }
        }
    }
    for url in callLogsToRemove(files, limit: callLogsLimit) {
        try? fileManager.removeItem(at: url)
    }
}

func callLogsToRemove(_ files: [(URL, Date)], limit: Int) -> [URL] {
    guard files.count > limit else {
        return []
    }
    return files.sorted(by: { $0.1 < $1.1 }).prefix(files.count - limit).map { $0.0 }
}

private let setupLogs: Bool = {
    OngoingCallThreadLocalContextWebrtc.setupLoggingFunction({ value in
        if let value = value {
            Logger.shared.log("TGVOIP", value)
        }
    })
    /*OngoingCallThreadLocalContextWebrtcCustom.setupLoggingFunction({ value in
     if let value = value {
     Logger.shared.log("TGVOIP", value)
     }
     })*/
    return true
}()

public struct OngoingCallContextState: Equatable {
    public enum State {
        case initializing
        case connected
        case reconnecting
        case failed
    }
    
    public enum VideoState: Equatable {
        case notAvailable
        case inactive
        case active
        case paused
    }
    
    public enum RemoteVideoState: Equatable {
        case inactive
        case active
        case paused
    }
    
    public enum RemoteAudioState: Equatable {
        case active
        case muted
    }
    
    public enum RemoteBatteryLevel: Equatable {
        case normal
        case low
    }
    
    public let state: State
    public let videoState: VideoState
    public let remoteVideoState: RemoteVideoState
    public let remoteAudioState: RemoteAudioState
    public let remoteBatteryLevel: RemoteBatteryLevel
    public let remoteAspectRatio: Float
    public init(state: State, videoState: VideoState, remoteVideoState: RemoteVideoState, remoteAudioState: RemoteAudioState, remoteBatteryLevel: RemoteBatteryLevel, remoteAspectRatio: Float) {
        self.state = state
        self.videoState = videoState
        self.remoteVideoState = remoteVideoState
        self.remoteAudioState = remoteAudioState
        self.remoteBatteryLevel = remoteBatteryLevel
        self.remoteAspectRatio = remoteAspectRatio
    }
}

public final class OngoingCallThreadLocalContextQueueImpl: NSObject, OngoingCallThreadLocalContextQueueWebrtc {
    
    
    private let queue: Queue
    
    public init(queue: Queue) {
        self.queue = queue
        
        super.init()
    }
    
    public func dispatch(_ f: @escaping () -> Void) {
        self.queue.async {
            f()
        }
    }
    
    public func dispatch(after seconds: Double, block f: @escaping () -> Void) {
        self.queue.after(seconds, f)
    }
    
    public func isCurrent() -> Bool {
        return self.queue.isCurrent()
    }
    
    public func scheduleBlock(_ f: @escaping () -> Void, after timeout: Double) -> GroupCallDisposable {
        let timer = SwiftSignalKit.Timer(timeout: timeout, repeat: false, completion: {
            f()
        }, queue: self.queue)
        timer.start()
        
        return GroupCallDisposable(block: {
            timer.invalidate()
        })
    }
}



private func ongoingNetworkTypeForTypeWebrtc(_ type: NetworkType) -> OngoingCallNetworkTypeWebrtc {
    switch type {
    case .none:
        return .wifi
    case .wifi:
        return .wifi
    }
}

/*private func ongoingNetworkTypeForTypeWebrtcCustom(_ type: NetworkType) -> OngoingCallNetworkTypeWebrtcCustom {
 switch type {
 case .none:
 return .wifi
 case .wifi:
 return .wifi
 case let .cellular(cellular):
 switch cellular {
 case .edge:
 return .cellularEdge
 case .gprs:
 return .cellularGprs
 case .thirdG, .unknown:
 return .cellular3g
 case .lte:
 return .cellularLte
 }
 }
 }*/

private func ongoingDataSavingForTypeWebrtc(_ type: VoiceCallDataSaving) -> OngoingCallDataSavingWebrtc {
    switch type {
    case .never:
        return .never
    case .cellular:
        return .cellular
    case .always:
        return .always
    }
}


private protocol OngoingCallThreadLocalContextProtocol: AnyObject {
    func nativeSetNetworkType(_ type: NetworkType)
    func nativeSetIsMuted(_ value: Bool)
    func nativeSetIsLowBatteryLevel(_ value: Bool)
    func nativeRequestVideo(_ capturer: OngoingCallVideoCapturer)
    func nativeSetRequestedVideoAspect(_ aspect: Float)
    func nativeDisableVideo()
    func nativeStop(_ completion: @escaping (String?, Int64, Int64, Int64, Int64) -> Void)
    func nativeBeginTermination()
    func nativeDebugInfo() -> String
    func nativeVersion() -> String
    func nativeGetDerivedState() -> Data
    func nativeSwitchAudioOutput(_ deviceId: String)
    func nativeSwitchAudioInput(_ deviceId: String)
}


private final class OngoingCallThreadLocalContextHolder {
    public let context: OngoingCallThreadLocalContextProtocol
    
    public init(_ context: OngoingCallThreadLocalContextProtocol) {
        self.context = context
    }
}

extension OngoingCallThreadLocalContextWebrtc: OngoingCallThreadLocalContextProtocol {
    public func nativeSetNetworkType(_ type: NetworkType) {
        self.setNetworkType(ongoingNetworkTypeForTypeWebrtc(type))
    }
    
    public func nativeStop(_ completion: @escaping (String?, Int64, Int64, Int64, Int64) -> Void) {
        self.stop(completion)
    }
    
    public func nativeBeginTermination() {
        self.beginTermination()
    }
    
    public func nativeSetIsMuted(_ value: Bool) {
        self.setIsMuted(value)
    }
    
    public func nativeSetIsLowBatteryLevel(_ value: Bool) {
        self.setIsLowBatteryLevel(value)
    }
    
    public func nativeSwitchAudioOutput(_ deviceId: String) {
        self.switchAudioOutput(deviceId)
    }
    public func nativeSwitchAudioInput(_ deviceId: String) {
        self.switchAudioInput(deviceId)
    }
    public func nativeRequestVideo(_ capturer: OngoingCallVideoCapturer) {
        self.requestVideo(capturer.impl)
    }
    public func nativeSetRequestedVideoAspect(_ aspect: Float) {
        self.setRequestedVideoAspect(aspect)
    }
    
    public func nativeDisableVideo() {
        self.disableVideo()
    }
    
    public func nativeDebugInfo() -> String {
        return self.debugInfo() ?? ""
    }
    
    public func nativeVersion() -> String {
        return self.version() ?? ""
    }
    
    public func nativeGetDerivedState() -> Data {
        return self.getDerivedState()
    }
    
}


private extension OngoingCallContextState.State {
    init(_ state: OngoingCallStateWebrtc) {
        switch state {
        case .initializing:
            self = .initializing
        case .connected:
            self = .connected
        case .failed:
            self = .failed
        case .reconnecting:
            self = .reconnecting
        default:
            self = .failed
        }
    }
}

/*private extension OngoingCallContextState {
 init(_ state: OngoingCallStateWebrtcCustom) {
 switch state {
 case .initializing:
 self = .initializing
 case .connected:
 self = .connected
 case .failed:
 self = .failed
 case .reconnecting:
 self = .reconnecting
 default:
 self = .failed
 }
 }
 }*/

public final class OngoingCallContext {
    public struct AuxiliaryServer {
        public enum Connection {
            case stun
            case turn(username: String, password: String)
        }
        
        public let host: String
        public let port: Int
        public let connection: Connection
        
        public init(
            host: String,
            port: Int,
            connection: Connection
            ) {
            self.host = host
            self.port = port
            self.connection = connection
        }
    }
    
    public let internalId: CallSessionInternalId
    
    private let queue = Queue()
    private let account: Account
    private let callSessionManager: CallSessionManager
    private let logPath: String
    
    private var contextRef: Unmanaged<OngoingCallThreadLocalContextHolder>?
    
    private let contextState = Promise<OngoingCallContextState?>(nil)
    public var state: Signal<OngoingCallContextState?, NoError> {
        return self.contextState.get()
    }
    
    private var didReportCallAsVideo: Bool = false
    
    
    private var signalingDataDisposable: Disposable?
    
    private let receptionPromise = Promise<Int32?>(nil)
    public var reception: Signal<Int32?, NoError> {
        return self.receptionPromise.get()
    }
    
    private let audioLevelPromise = ValuePromise<Float>(0.0, ignoreRepeated: true)
       public var audioLevel: Signal<Float, NoError> {
           return self.audioLevelPromise.get()
       }

    
    private let audioSessionDisposable = MetaDisposable()
    private var networkTypeDisposable: Disposable?
    
    private let tempLogFile: TempBoxFile
    private let tempStatsLogFile: TempBoxFile
    
    
    public static var maxLayer: Int32 {
        return OngoingCallThreadLocalContextWebrtc.maxLayer()
    }
    
    static let referenceImplementationVersions: Set<String> = ["10.0.0", "11.0.0"]
    
    public static func ignoresInitialAudioDevices(version: String) -> Bool {
        return referenceImplementationVersions.contains(version)
    }
    
    public static func versions(includeExperimental: Bool, includeReference: Bool) -> [(version: String, supportsVideo: Bool)] {
        var result: [(version: String, supportsVideo: Bool)] = []
        result.append(contentsOf: OngoingCallThreadLocalContextWebrtc.versions(withIncludeReference: includeReference).map { version -> (version: String, supportsVideo: Bool) in
            return (version, true)
        })
        return result
    }


    
    public init(account: Account, callSessionManager: CallSessionManager, internalId: CallSessionInternalId, proxyServer: ProxyServerSettings?, initialNetworkType: NetworkType, updatedNetworkType: Signal<NetworkType, NoError>, serializedData: String?, dataSaving: VoiceCallDataSaving, derivedState: VoipDerivedState, key: Data, isOutgoing: Bool, video: OngoingCallVideoCapturer?, connections: CallSessionConnectionSet, maxLayer: Int32, version: String, allowP2P: Bool, enableTCP: Bool, enableStunMarking: Bool, logName: String, preferredVideoCodec: String?, inputDeviceId: String?, outputDeviceId: String?) {
        let _ = setupLogs
        OngoingCallThreadLocalContextWebrtc.applyServerConfig(serializedData)
        
        self.internalId = internalId
        self.account = account
        self.callSessionManager = callSessionManager
        self.logPath = logName.isEmpty ? "" : callLogsPath(account: self.account) + "/" + logName + ".log"
        _ = self.logPath
        self.tempLogFile = TempBox.shared.tempFile(fileName: "CallLog.txt")
        let tempLogPath = self.tempLogFile.path
        
        
        self.tempStatsLogFile = TempBox.shared.tempFile(fileName: "CallStats.json")
        let tempStatsLogPath = self.tempStatsLogFile.path


        let queue = self.queue
        
        cleanupCallLogs(account: account)
        queue.sync {
            
            let version = version
            let allowP2P = allowP2P

            var voipProxyServer: VoipProxyServerWebrtc?
            if let proxyServer = proxyServer {
                switch proxyServer.connection {
                case let .socks5(username, password):
                    voipProxyServer = VoipProxyServerWebrtc(host: proxyServer.host, port: proxyServer.port, username: username, password: password)
                case .mtp, .web:
                    break
                }
            }
            
            let unfilteredConnections = [connections.primary] + connections.alternatives
            
            var reflectorIdList: [Int64] = []
            for connection in unfilteredConnections {
                switch connection {
                case let .reflector(reflector):
                    reflectorIdList.append(reflector.id)
                case .webRtcReflector:
                    break
                }
            }
            
            reflectorIdList.sort()
            
            var reflectorIdMapping: [Int64: UInt8] = [:]
            for i in 0 ..< reflectorIdList.count {
                reflectorIdMapping[reflectorIdList[i]] = UInt8(i + 1)
            }
            
            var processedConnections: [CallSessionConnection] = []
            var filteredConnections: [OngoingCallConnectionDescriptionWebrtc] = []
            for connection in unfilteredConnections {
                if processedConnections.contains(connection) {
                    continue
                }
                processedConnections.append(connection)
                filteredConnections.append(contentsOf: callConnectionDescriptionsWebrtc(connection, idMapping: reflectorIdMapping))
            }
            
            for connection in filteredConnections {
                if connection.username == "reflector" {
                    _ = dataWithHexString(connection.password)
                    break
                }
            }

            let context = OngoingCallThreadLocalContextWebrtc(version: version, queue: OngoingCallThreadLocalContextQueueImpl(queue: queue), proxy: voipProxyServer, networkType: ongoingNetworkTypeForTypeWebrtc(initialNetworkType), dataSaving: ongoingDataSavingForTypeWebrtc(dataSaving), derivedState: derivedState.data, key: key, isOutgoing: isOutgoing, connections: filteredConnections, maxLayer: maxLayer, allowP2P: allowP2P, allowTCP: enableTCP, enableStunMarking: enableStunMarking, logPath: tempLogPath, statsLogPath: tempStatsLogPath, sendSignalingData: { [weak callSessionManager] data in
                callSessionManager?.sendSignalingData(internalId: internalId, data: data)
            }, videoCapturer: video?.impl, preferredVideoCodec: preferredVideoCodec, inputDeviceId: inputDeviceId ?? "", outputDeviceId: outputDeviceId ?? "")
            
            
            self.contextRef = Unmanaged.passRetained(OngoingCallThreadLocalContextHolder(context))
            context.stateChanged = { [weak self, weak callSessionManager] state, videoState, remoteVideoState, remoteAudioState, remoteBatteryLevel, remotePreferredAspectRatio in
                queue.async {
                    guard let strongSelf = self else {
                        return
                    }
                    
                    let mappedState = OngoingCallContextState.State(state)
                    let mappedVideoState: OngoingCallContextState.VideoState
                    switch videoState {
                    case .inactive:
                        mappedVideoState = .inactive
                    case .active:
                        mappedVideoState = .active
                    case .paused:
                        mappedVideoState = .paused
                    @unknown default:
                        mappedVideoState = .notAvailable
                    }
                    let mappedRemoteVideoState: OngoingCallContextState.RemoteVideoState
                    switch remoteVideoState {
                    case .inactive:
                        mappedRemoteVideoState = .inactive
                    case .active:
                        mappedRemoteVideoState = .active
                    case .paused:
                        mappedRemoteVideoState = .paused
                    @unknown default:
                        mappedRemoteVideoState = .inactive
                    }
                    let mappedRemoteAudioState: OngoingCallContextState.RemoteAudioState
                    switch remoteAudioState {
                    case .active:
                        mappedRemoteAudioState = .active
                    case .muted:
                        mappedRemoteAudioState = .muted
                    @unknown default:
                        mappedRemoteAudioState = .active
                    }
                    let mappedRemoteBatteryLevel: OngoingCallContextState.RemoteBatteryLevel
                    switch remoteBatteryLevel {
                    case .normal:
                        mappedRemoteBatteryLevel = .normal
                    case .low:
                        mappedRemoteBatteryLevel = .low
                    @unknown default:
                        mappedRemoteBatteryLevel = .normal
                    }
                    if case .active = mappedVideoState, !strongSelf.didReportCallAsVideo {
                        strongSelf.didReportCallAsVideo = true
                        callSessionManager?.updateCallType(internalId: internalId, type: .video)
                    }
                    strongSelf.contextState.set(.single(OngoingCallContextState(state: mappedState, videoState: mappedVideoState, remoteVideoState: mappedRemoteVideoState, remoteAudioState: mappedRemoteAudioState, remoteBatteryLevel: mappedRemoteBatteryLevel, remoteAspectRatio: remotePreferredAspectRatio)))

                }
            }
            self.receptionPromise.set(.single(4))
            context.signalBarsChanged = { [weak self] signalBars in
                self?.receptionPromise.set(.single(signalBars))
            }
            context.audioLevelUpdated = { [weak self] level in
                self?.audioLevelPromise.set(level)
            }

            
            self.networkTypeDisposable = (updatedNetworkType
                |> deliverOn(queue)).start(next: { [weak self] networkType in
                    self?.withContext { context in
                        context.nativeSetNetworkType(networkType)
                    }
                })
        }
        
        
        
        self.signalingDataDisposable = callSessionManager.beginReceivingCallSignalingData(internalId: internalId, { [weak self] dataList in
            queue.async {
                self?.withContext { context in
                    if let context = context as? OngoingCallThreadLocalContextWebrtc {
                        for data in dataList {
                            context.addSignaling(data)
                        }
                    }
                }
            }
        })
    }
    
    deinit {
        let contextRef = self.contextRef
        self.queue.async {
            contextRef?.release()
        }
        self.signalingDataDisposable?.dispose()
        
        self.audioSessionDisposable.dispose()
        self.networkTypeDisposable?.dispose()
    }
    
    private func withContext(_ f: @escaping (OngoingCallThreadLocalContextProtocol) -> Void) {
        self.queue.async {
            if let contextRef = self.contextRef {
                let context = contextRef.takeUnretainedValue()
                f(context.context)
            }
        }
    }
    
    private func withContextThenDeallocate(_ f: @escaping (OngoingCallThreadLocalContextProtocol) -> Void) {
        self.queue.async {
            if let contextRef = self.contextRef {
                let context = contextRef.takeUnretainedValue()
                f(context.context)
                
                self.contextRef?.release()
                self.contextRef = nil
            }
        }
    }

    
    public func stop(callId: CallId? = nil, sendDebugLogs: Bool = false, debugLogValue: Promise<String?>) {
        let account = self.account
        let logPath = self.logPath
        var statsLogPath = ""
        if !logPath.isEmpty {
            statsLogPath = logPath + ".json"
        }
        let tempLogPath = self.tempLogFile.path
        let tempStatsLogPath = self.tempStatsLogFile.path
        
        self.withContextThenDeallocate { context in
            context.nativeStop { debugLog, bytesSentWifi, bytesReceivedWifi, bytesSentMobile, bytesReceivedMobile in
                let delta = NetworkUsageStatsConnectionsEntry(
                    cellular: NetworkUsageStatsDirectionsEntry(
                        incoming: bytesReceivedMobile,
                        outgoing: bytesSentMobile),
                    wifi: NetworkUsageStatsDirectionsEntry(
                        incoming: bytesReceivedWifi,
                        outgoing: bytesSentWifi))
                updateAccountNetworkUsageStats(account: self.account, category: .call, delta: delta)
                
                if !logPath.isEmpty {
                    let logsPath = callLogsPath(account: account)
                    let _ = try? FileManager.default.createDirectory(atPath: logsPath, withIntermediateDirectories: true, attributes: nil)
                    let _ = try? FileManager.default.moveItem(atPath: tempLogPath, toPath: logPath)
                }
                
                if !statsLogPath.isEmpty {
                    let logsPath = callLogsPath(account: account)
                    let _ = try? FileManager.default.createDirectory(atPath: logsPath, withIntermediateDirectories: true, attributes: nil)
                    let _ = try? FileManager.default.moveItem(atPath: tempStatsLogPath, toPath: statsLogPath)
                }
                
                if callId != nil, !statsLogPath.isEmpty, let data = try? Data(contentsOf: URL(fileURLWithPath: statsLogPath)), let dataString = String(data: data, encoding: .utf8) {
                    debugLogValue.set(.single(dataString))
                    if sendDebugLogs {
//                        let _ = saveCallDebugLog(network: self.account.network, callId: callId, log: dataString).start()
                    }
                }
            }
            let derivedState = context.nativeGetDerivedState()
            let _ = updateVoipDerivedStateInteractively(postbox: self.account.postbox, { _ in
                return VoipDerivedState(data: derivedState)
            }).start()
        }

    }
    
    public func setIsMuted(_ value: Bool) {
        self.withContext { context in
            context.nativeSetIsMuted(value)
        }
    }
    
    public func setIsLowBatteryLevel(_ value: Bool) {
        self.withContext { context in
            context.nativeSetIsLowBatteryLevel(value)
        }
    }
    
    public func requestVideo(_ capturer: OngoingCallVideoCapturer) {
        self.withContext { context in
            context.nativeRequestVideo(capturer)
        }
    }
    
    public func setRequestedVideoAspect(_ aspect: Float) {
        self.withContext { context in
            context.nativeSetRequestedVideoAspect(aspect)
        }
    }
    
    public func disableVideo() {
        self.withContext { context in
            context.nativeDisableVideo()
        }
    }
    
    public func switchAudioOutput(_ deviceId: String) {
        self.withContext { context in
            context.nativeSwitchAudioOutput(deviceId)
        }
    }
    public func switchAudioInput(_ deviceId: String) {
        self.withContext { context in
            context.nativeSwitchAudioInput(deviceId)
        }
    }
    public func debugInfo() -> Signal<(String, String), NoError> {
        let poll = Signal<(String, String), NoError> { subscriber in
            self.withContext { context in
                let version = context.nativeVersion()
                let debugInfo = context.nativeDebugInfo()
                subscriber.putNext((version, debugInfo))
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        }
        return (poll |> then(.complete() |> delay(0.5, queue: Queue.concurrentDefaultQueue()))) |> restart
    }
    
    public func video(isIncoming: Bool) -> Signal<OngoingGroupCallContext.VideoFrameData, NoError> {
        let queue = self.queue
        return Signal { [weak self] subscriber in
            let disposable = MetaDisposable()

            queue.async {
                guard let strongSelf = self else {
                    return
                }
                strongSelf.withContext { context in
                    if let context = context as? OngoingCallThreadLocalContextWebrtc {
                        let innerDisposable = context.addVideoOutput(withIsIncoming: isIncoming, sink: { videoFrameData in
                            subscriber.putNext(OngoingGroupCallContext.VideoFrameData(frameData: videoFrameData))
                        })
                        disposable.set(ActionDisposable {
                            innerDisposable.dispose()
                        })
                    }
                }
            }

            return disposable
        }
    }
        

    
    public func makeIncomingVideoView(completion: @escaping (OngoingCallContextPresentationCallVideoView?) -> Void) {
        self.withContext { context in
            if let context = context as? OngoingCallThreadLocalContextWebrtc {
                context.makeIncomingVideoView { view in
                    if let view = view {
                        completion(OngoingCallContextPresentationCallVideoView(
                            view: view,
                            setOnFirstFrameReceived: { [weak view] f in
                                view?.setOnFirstFrameReceived(f)
                            },
                            getOrientation: { [weak view] in
                                if let view = view {
                                    return OngoingCallVideoOrientation(view.orientation)
                                } else {
                                    return .rotation0
                                }
                            },
                            getAspect: { [weak view] in
                                if let view = view {
                                    return view.aspect
                                } else {
                                    return 0.0
                                }
                            },
                            setOnOrientationUpdated: { [weak view] f in
                                view?.setOnOrientationUpdated { value, aspect in
                                    f?(OngoingCallVideoOrientation(value), aspect)
                                }
                            }, setVideoContentMode: { [weak view] mode in
                                view?.setVideoContentMode(mode)
                            }, setOnIsMirroredUpdated: { [weak view] f in
                                view?.setOnIsMirroredUpdated { value in
                                    f?(value)
                                }
                            },
                            setIsPaused: { [weak view] paused in
                                view?.setIsPaused(paused)
                            }, renderToSize: { [weak view] size, animated in
                                view?.render(to: size, animated: animated)
                            }
                        ))
                    } else {
                        completion(nil)
                    }
                }
            } else {
                completion(nil)
            }
        }
    }

}
