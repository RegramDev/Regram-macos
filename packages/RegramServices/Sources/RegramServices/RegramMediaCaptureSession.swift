import Foundation
import AVFoundation
import SwiftSignalKit

public enum RegramMediaCaptureError: Error, Equatable {
    case cameraDenied, microphoneDenied, unavailable, recording, storage, cancelled
}

public struct RegramMediaCaptureState: Equatable {
    public enum Phase: Equatable { case idle, preparing, ready, takingPhoto, recording, processing, failed }
    public var phase: Phase = .idle
    public var seconds: Int = 0
    public var error: RegramMediaCaptureError?
    public init() {}
}

public final class RegramMediaCaptureSession: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    public let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "Regram.media-capture", qos: .userInitiated)
    private let promise = ValuePromise(RegramMediaCaptureState(), ignoreRepeated: true)
    private let completion: (Result<URL, RegramMediaCaptureError>) -> Void
    private let maximumVideoDuration: TimeInterval
    private let cancelled = Atomic(value: false)
    private var configured = false
    private var workingState = RegramMediaCaptureState()
    private var paths = Set<URL>()
    private var export: AVAssetExportSession?
    private var timer: DispatchSourceTimer?
    public var state: Signal<RegramMediaCaptureState, NoError> { promise.get() }

    public init(maximumVideoDuration: TimeInterval = 60, completion: @escaping (Result<URL, RegramMediaCaptureError>) -> Void) {
        self.maximumVideoDuration = min(180, max(1, maximumVideoDuration))
        self.completion = completion
        super.init()
    }

    private func publish(_ phase: RegramMediaCaptureState.Phase, error: RegramMediaCaptureError? = nil) {
        workingState.phase = phase
        workingState.error = error
        promise.set(workingState)
    }

    public func start() {
        guard !cancelled.with({ $0 }) else { return }
        queue.async { [weak self] in
            guard let self, !self.cancelled.with({ $0 }), self.workingState.phase == .idle || self.workingState.phase == .failed else { return }
            self.publish(.preparing)
            func configure(_ allowed: Bool) {
                self.queue.async { [weak self] in
                    guard let self, !self.cancelled.with({ $0 }) else { return }
                    guard allowed else { self.publish(.failed, error: .cameraDenied); return }
                    do {
                        if !self.configured {
                            guard let camera = AVCaptureDevice.default(for: .video) else { self.publish(.failed, error: .unavailable); return }
                            let input = try AVCaptureDeviceInput(device: camera)
                            self.captureSession.beginConfiguration()
                            defer { self.captureSession.commitConfiguration() }
                            self.captureSession.sessionPreset = .high
                            guard self.captureSession.canAddInput(input), self.captureSession.canAddOutput(self.photoOutput), self.captureSession.canAddOutput(self.movieOutput) else { self.publish(.failed, error: .unavailable); return }
                            self.captureSession.addInput(input)
                            self.captureSession.addOutput(self.photoOutput)
                            self.captureSession.addOutput(self.movieOutput)
                            self.movieOutput.maxRecordedDuration = CMTime(seconds: self.maximumVideoDuration, preferredTimescale: 600)
                            self.movieOutput.maxRecordedFileSize = 512 * 1024 * 1024
                            self.configured = true
                        }
                        self.captureSession.startRunning()
                        self.publish(.ready)
                    } catch { self.publish(.failed, error: .unavailable) }
                }
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: configure(true)
            case .notDetermined: AVCaptureDevice.requestAccess(for: .video, completionHandler: configure)
            default: configure(false)
            }
        }
    }

    public func takePhoto() {
        queue.async { [weak self] in
            guard let self, !self.cancelled.with({ $0 }), self.workingState.phase == .ready else { return }
            self.publish(.takingPhoto)
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self)
        }
    }

    public func startRecording() {
        queue.async { [weak self] in
            guard let self, !self.cancelled.with({ $0 }), self.workingState.phase == .ready else { return }
            func record(_ allowed: Bool) {
                self.queue.async { [weak self] in
                    guard let self, !self.cancelled.with({ $0 }), self.workingState.phase == .ready else { return }
                    guard allowed else { self.publish(.failed, error: .microphoneDenied); return }
                    if !self.captureSession.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }) {
                        guard let microphone = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: microphone), self.captureSession.canAddInput(input) else { self.fail(.unavailable); return }
                        self.captureSession.beginConfiguration()
                        self.captureSession.addInput(input)
                        self.captureSession.commitConfiguration()
                    }
                    let path = FileManager.default.temporaryDirectory.appendingPathComponent("regram-capture-\(UUID().uuidString).mov")
                    self.paths.insert(path)
                    self.workingState.seconds = 0
                    self.publish(.recording)
                    self.movieOutput.startRecording(to: path, recordingDelegate: self)
                    let timer = DispatchSource.makeTimerSource(queue: self.queue)
                    timer.schedule(deadline: .now() + 1, repeating: 1)
                    timer.setEventHandler { [weak self] in
                        guard let self, self.workingState.phase == .recording else { return }
                        self.workingState.seconds += 1
                        self.promise.set(self.workingState)
                    }
                    self.timer = timer
                    timer.resume()
                }
            }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: record(true)
            case .notDetermined: AVCaptureDevice.requestAccess(for: .audio, completionHandler: record)
            default: record(false)
            }
        }
    }

    public func stopRecording() {
        queue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.publish(.processing)
            self.movieOutput.stopRecording()
        }
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        queue.async { [weak self] in
            guard let self, !self.cancelled.with({ $0 }) else { return }
            guard error == nil, let data = photo.fileDataRepresentation(), !data.isEmpty else { self.fail(.recording); return }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("regram-capture-\(UUID().uuidString).jpg")
            do { try data.write(to: path, options: .atomic); self.finish(path) }
            catch { self.fail(.storage) }
        }
    }

    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            guard !self.cancelled.with({ $0 }) else { try? FileManager.default.removeItem(at: outputFileURL); return }
            let successful = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
            guard error == nil || successful else { self.fail(.recording); return }
            self.publish(.processing)
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("regram-capture-\(UUID().uuidString).mp4")
            self.paths.insert(path)
            guard let export = AVAssetExportSession(asset: AVURLAsset(url: outputFileURL), presetName: AVAssetExportPresetHighestQuality) else { self.fail(.recording); return }
            self.export = export
            export.outputURL = path
            export.outputFileType = .mp4
            export.shouldOptimizeForNetworkUse = true
            export.exportAsynchronously { [weak self, weak export] in
                self?.queue.async { [weak self, weak export] in
                    guard let self, !self.cancelled.with({ $0 }) else { return }
                    guard export?.status == .completed else { self.fail(.recording); return }
                    self.finish(path)
                }
            }
        }
    }

    private func finish(_ path: URL) {
        guard !cancelled.swap(true) else { try? FileManager.default.removeItem(at: path); return }
        paths.remove(path)
        cleanup()
        DispatchQueue.main.async { [completion] in completion(.success(path)) }
    }

    private func fail(_ error: RegramMediaCaptureError) {
        cleanup()
        configured = false
        publish(.failed, error: error)
    }

    private func cleanup() {
        timer?.cancel()
        timer = nil
        export?.cancelExport()
        export = nil
        if movieOutput.isRecording { movieOutput.stopRecording() }
        if captureSession.isRunning { captureSession.stopRunning() }
        captureSession.beginConfiguration()
        for input in captureSession.inputs { captureSession.removeInput(input) }
        for output in captureSession.outputs { captureSession.removeOutput(output) }
        captureSession.commitConfiguration()
        for path in paths { try? FileManager.default.removeItem(at: path) }
        paths.removeAll()
    }

    public func cancel() {
        guard !cancelled.swap(true) else { return }
        queue.async { [self] in cleanup() }
    }

    deinit {
        timer?.cancel()
        export?.cancelExport()
        let session = captureSession
        let output = movieOutput
        let paths = paths
        queue.async {
            if output.isRecording { output.stopRecording() }
            if session.isRunning { session.stopRunning() }
            for path in paths { try? FileManager.default.removeItem(at: path) }
        }
    }
}
