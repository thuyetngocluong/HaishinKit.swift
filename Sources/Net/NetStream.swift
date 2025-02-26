import AVFoundation
import CoreImage
import CoreMedia
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
#if os(iOS) || os(tvOS)
import UIKit
#endif

/// The interface a NetStream uses to inform its delegate.
public protocol NetStreamDelegate: AnyObject {
    /// Tells the receiver to playback an audio packet incoming.
    func stream(_ stream: NetStream, didOutput audio: AVAudioBuffer, presentationTimeStamp: CMTime)
    /// Tells the receiver to playback a video packet incoming.
    func stream(_ stream: NetStream, didOutput video: CMSampleBuffer)
    #if os(iOS) || os(tvOS)
    /// Tells the receiver to session was interrupted.
    @available(tvOS 17.0, *)
    func stream(_ stream: NetStream, sessionWasInterrupted session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason?)
    /// Tells the receiver to session interrupted ended.
    @available(tvOS 17.0, *)
    func stream(_ stream: NetStream, sessionInterruptionEnded session: AVCaptureSession)
    #endif
    /// Tells the receiver to video codec error occured.
    func stream(_ stream: NetStream, videoCodecErrorOccurred error: VideoCodec.Error)
    /// Tells the receiver to audio codec error occured.
    func stream(_ stream: NetStream, audioCodecErrorOccurred error: AudioCodec.Error)
    /// Tells the receiver to the stream opened.
    func streamDidOpen(_ stream: NetStream)
}

/// The `NetStream` class is the foundation of a RTMPStream, HTTPStream.
open class NetStream: NSObject {
    /// The lockQueue.
    public let lockQueue: DispatchQueue = .init(label: "com.haishinkit.HaishinKit.NetStream.lock")

    /// The mixer object.
    public private(set) lazy var mixer: IOMixer = {
        let mixer = IOMixer()
        mixer.delegate = self
        return mixer
    }()

    /// Specifies the adaptibe bitrate strategy.
    public var bitrateStrategy: any NetBitRateStrategyConvertible = NetBitRateStrategy.shared {
        didSet {
            bitrateStrategy.stream = self
            bitrateStrategy.setUp()
        }
    }

    /// Specifies the delegate..
    public weak var delegate: (any NetStreamDelegate)?

    /// Specifies the audio monitoring enabled or not.
    public var isMonitoringEnabled: Bool {
        get {
            mixer.audioIO.isMonitoringEnabled
        }
        set {
            mixer.audioIO.isMonitoringEnabled = newValue
        }
    }

    /// Specifies the context object.
    public var context: CIContext {
        get {
            mixer.videoIO.context
        }
        set {
            mixer.videoIO.context = newValue
        }
    }

    #if os(iOS) || os(macOS) || os(tvOS)
    /// Specifiet the device torch indicating wheter the turn on(TRUE) or not(FALSE).
    public var torch: Bool {
        get {
            var torch = false
            lockQueue.sync {
                torch = self.mixer.videoIO.torch
            }
            return torch
        }
        set {
            lockQueue.async {
                self.mixer.videoIO.torch = newValue
            }
        }
    }

    /// Specifies the frame rate of a device capture.
    public var frameRate: Float64 {
        get {
            var frameRate: Float64 = IOMixer.defaultFrameRate
            lockQueue.sync {
                frameRate = self.mixer.videoIO.frameRate
            }
            return frameRate
        }
        set {
            lockQueue.async {
                self.mixer.videoIO.frameRate = newValue
            }
        }
    }

    /// Specifies the sessionPreset for the AVCaptureSession.
    @available(tvOS 17.0, *)
    public var sessionPreset: AVCaptureSession.Preset {
        get {
            var sessionPreset: AVCaptureSession.Preset = .default
            lockQueue.sync {
                sessionPreset = self.mixer.sessionPreset
            }
            return sessionPreset
        }
        set {
            lockQueue.async {
                self.mixer.sessionPreset = newValue
            }
        }
    }
    #endif

    #if os(iOS) || os(macOS)
    /// Specifies the video orientation for stream.
    public var videoOrientation: AVCaptureVideoOrientation {
        get {
            mixer.videoIO.videoOrientation
        }
        set {
            mixer.videoIO.videoOrientation = newValue
        }
    }
    #endif

    /// Specifies the multi camera capture properties.
    public var multiCamCaptureSettings: MultiCamCaptureSettings {
        get {
            mixer.videoIO.multiCamCaptureSettings
        }
        set {
            mixer.videoIO.multiCamCaptureSettings = newValue
        }
    }

    /// Specifies the hasAudio indicies whether no signal audio or not.
    public var hasAudio: Bool {
        get {
            !mixer.audioIO.muted
        }
        set {
            mixer.audioIO.muted = !newValue
        }
    }

    /// Specifies the hasVideo indicies whether freeze video signal or not.
    public var hasVideo: Bool {
        get {
            !mixer.videoIO.muted
        }
        set {
            mixer.videoIO.muted = !newValue
        }
    }

    /// Specifies the audio compression properties.
    public var audioSettings: AudioCodecSettings {
        get {
            mixer.audioIO.settings
        }
        set {
            mixer.audioIO.settings = newValue
        }
    }

    /// Specifies the video compression properties.
    public var videoSettings: VideoCodecSettings {
        get {
            mixer.videoIO.settings
        }
        set {
            mixer.videoIO.settings = newValue
        }
    }

    /// Creates a NetStream object.
    override public init() {
        super.init()
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        #endif
    }

    #if os(iOS) || os(macOS) || os(tvOS)
    /// Attaches the primary camera object.
    /// - Warning: This method can't use appendSampleBuffer at the same time.
    @available(tvOS 17.0, *)
    open func attachCamera(_ device: AVCaptureDevice?, onError: ((_ error: any Error) -> Void)? = nil) {
        lockQueue.async {
            do {
                try self.mixer.videoIO.attachCamera(device)
            } catch {
                onError?(error)
            }
        }
    }

    /// Attaches the 2ndary camera  object for picture in picture.
    /// - Warning: This method can't use appendSampleBuffer at the same time.
    @available(iOS 13.0, tvOS 17.0, *)
    open func attachMultiCamera(_ device: AVCaptureDevice?, onError: ((_ error: any Error) -> Void)? = nil) {
        lockQueue.async {
            do {
                try self.mixer.videoIO.attachMultiCamera(device)
            } catch {
                onError?(error)
            }
        }
    }

    /// Attaches the audio capture object.
    /// - Warning: This method can't use appendSampleBuffer at the same time.
    @available(tvOS 17.0, *)
    open func attachAudio(_ device: AVCaptureDevice?, automaticallyConfiguresApplicationAudioSession: Bool = false, onError: ((_ error: any Error) -> Void)? = nil) {
        lockQueue.async {
            do {
                try self.mixer.audioIO.attachAudio(device, automaticallyConfiguresApplicationAudioSession: automaticallyConfiguresApplicationAudioSession)
            } catch {
                onError?(error)
            }
        }
    }

    /// Returns the IOVideoCaptureUnit by index.
    @available(tvOS 17.0, *)
    public func videoCapture(for index: Int) -> IOVideoCaptureUnit? {
        return mixer.videoIO.lockQueue.sync {
            switch index {
            case 0:
                return self.mixer.videoIO.capture
            case 1:
                return self.mixer.videoIO.multiCamCapture
            default:
                return nil
            }
        }
    }
    #endif

    #if os(macOS)
    /// Attaches the screen input object.
    public func attachScreen(_ input: AVCaptureScreenInput?) {
        lockQueue.async {
            self.mixer.videoIO.attachScreen(input)
        }
    }
    #endif

    /// Append a CMSampleBuffer?.
    /// - Warning: This method can't use attachCamera or attachAudio method at the same time.
    open func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, options: [NSObject: AnyObject]? = nil) {
        switch sampleBuffer.formatDescription?._mediaType {
        case kCMMediaType_Audio:
            mixer.audioIO.lockQueue.async {
                self.mixer.audioIO.appendSampleBuffer(sampleBuffer)
            }
        case kCMMediaType_Video:
            mixer.videoIO.lockQueue.async {
                self.mixer.videoIO.appendSampleBuffer(sampleBuffer)
            }
        default:
            break
        }
    }

    /// Register a video effect.
    public func registerVideoEffect(_ effect: VideoEffect) -> Bool {
        mixer.videoIO.lockQueue.sync {
            self.mixer.videoIO.registerEffect(effect)
        }
    }

    /// Unregister a video effect.
    public func unregisterVideoEffect(_ effect: VideoEffect) -> Bool {
        mixer.videoIO.lockQueue.sync {
            self.mixer.videoIO.unregisterEffect(effect)
        }
    }

    /// Starts recording.
    public func startRecording(_ settings: [AVMediaType: [String: Any]] = IORecorder.defaultOutputSettings) {
        mixer.recorder.outputSettings = settings
        mixer.recorder.startRunning()
    }

    /// Stop recording.
    public func stopRecording() {
        mixer.recorder.stopRunning()
    }

    #if os(iOS) || os(tvOS)
    @objc
    private func didEnterBackground(_ notification: Notification) {
        // Require main thread. Otherwise the microphone cannot be used in the background.
        mixer.inBackgroundMode = true
    }

    @objc
    private func willEnterForeground(_ notification: Notification) {
        lockQueue.async {
            self.mixer.inBackgroundMode = false
        }
    }
    #endif
}

extension NetStream: IOMixerDelegate {
    // MARK: IOMixerDelegate
    func mixer(_ mixer: IOMixer, didOutput video: CMSampleBuffer) {
        delegate?.stream(self, didOutput: video)
    }

    func mixer(_ mixer: IOMixer, didOutput audio: AVAudioPCMBuffer, presentationTimeStamp: CMTime) {
        delegate?.stream(self, didOutput: audio, presentationTimeStamp: presentationTimeStamp)
    }

    func mixer(_ mixer: IOMixer, audioCodecErrorOccurred error: AudioCodec.Error) {
        delegate?.stream(self, audioCodecErrorOccurred: error)
    }

    func mixer(_ mixer: IOMixer, videoCodecErrorOccurred error: VideoCodec.Error) {
        delegate?.stream(self, videoCodecErrorOccurred: error)
    }

    #if os(iOS) || os(tvOS)
    @available(tvOS 17.0, *)
    func mixer(_ mixer: IOMixer, sessionWasInterrupted session: AVCaptureSession, reason: AVCaptureSession.InterruptionReason?) {
        delegate?.stream(self, sessionWasInterrupted: session, reason: reason)
    }

    @available(tvOS 17.0, *)
    func mixer(_ mixer: IOMixer, sessionInterruptionEnded session: AVCaptureSession) {
        delegate?.stream(self, sessionInterruptionEnded: session)
    }
    #endif
}

//extension NetStream: IOScreenCaptureUnitDelegate {
//    // MARK: IOScreenCaptureUnitDelegate
//    public func session(_ session: any IOScreenCaptureUnit, didOutput pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
//        var timingInfo = CMSampleTimingInfo(
//            duration: .invalid,
//            presentationTimeStamp: presentationTime,
//            decodeTimeStamp: .invalid
//        )
//        var videoFormatDescription: CMVideoFormatDescription?
//        var status = CMVideoFormatDescriptionCreateForImageBuffer(
//            allocator: kCFAllocatorDefault,
//            imageBuffer: pixelBuffer,
//            formatDescriptionOut: &videoFormatDescription
//        )
//        guard status == noErr else {
//            return
//        }
//        var sampleBuffer: CMSampleBuffer?
//        status = CMSampleBufferCreateForImageBuffer(
//            allocator: kCFAllocatorDefault,
//            imageBuffer: pixelBuffer,
//            dataReady: true,
//            makeDataReadyCallback: nil,
//            refcon: nil,
//            formatDescription: videoFormatDescription!,
//            sampleTiming: &timingInfo,
//            sampleBufferOut: &sampleBuffer
//        )
//        guard let sampleBuffer, status == noErr else {
//            return
//        }
//        appendSampleBuffer(sampleBuffer)
//    }
//}

#if os(macOS)
extension NetStream: SCStreamOutput {
    @available(macOS 12.3, *)
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if #available(macOS 13.0, *) {
            switch type {
            case .screen:
                appendSampleBuffer(sampleBuffer)
            default:
                appendSampleBuffer(sampleBuffer)
            }
        } else {
            appendSampleBuffer(sampleBuffer)
        }
    }
}
#endif
