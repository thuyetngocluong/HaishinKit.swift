import AVFoundation
import CoreFoundation
import VideoToolbox
#if canImport(UIKit)
import UIKit
#endif

/**
 * The interface a VideoCodec uses to inform its delegate.
 */
public protocol VideoCodecDelegate: AnyObject {
    /// Tells the receiver to set a formatDescription.
    func videoCodec(_ codec: VideoCodec, didOutput formatDescription: CMFormatDescription?)
    /// Tells the receiver to output an encoded or decoded sampleBuffer.
    func videoCodec(_ codec: VideoCodec, didOutput sampleBuffer: CMSampleBuffer)
    /// Tells the receiver to occured an error.
    func videoCodec(_ codec: VideoCodec, errorOccurred error: VideoCodec.Error)
}

// MARK: -
/**
 * The VideoCodec class provides methods for encode or decode for video.
 */
public final class VideoCodec {
    static let defaultFrameInterval = 0.0

    /**
     * The VideoCodec error domain codes.
     */
    public enum Error: Swift.Error {
        /// The VideoCodec failed to create the VTSession.
        case failedToCreate(status: OSStatus)
        /// The VideoCodec failed to prepare the VTSession.
        case failedToPrepare(status: OSStatus)
        /// The VideoCodec failed to encode or decode a flame.
        case failedToFlame(status: OSStatus)
        /// The VideoCodec failed to set an option.
        case failedToSetOption(status: OSStatus, option: VTSessionOption)
    }

    /// The videoCodec's attributes value.
    public static var defaultAttributes: [NSString: AnyObject]? = [
        kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
        kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue
    ]

    /// Specifies the settings for a VideoCodec.
    public var settings: VideoCodecSettings = .default {
        didSet {
            let invalidateSession = settings.invalidateSession(oldValue)
            if invalidateSession {
                self.invalidateSession = invalidateSession
            } else {
                settings.apply(self, rhs: oldValue)
            }
        }
    }

    /// The running value indicating whether the VideoCodec is running.
    public private(set) var isRunning: Atomic<Bool> = .init(false)

    var lockQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.VideoCodec.lock")
    var needsSync: Atomic<Bool> = .init(true)
    var attributes: [NSString: AnyObject]? {
        guard VideoCodec.defaultAttributes != nil else {
            return nil
        }
        var attributes: [NSString: AnyObject] = [:]
        for (key, value) in VideoCodec.defaultAttributes ?? [:] {
            attributes[key] = value
        }
        attributes[kCVPixelBufferWidthKey] = NSNumber(value: settings.videoSize.width)
        attributes[kCVPixelBufferHeightKey] = NSNumber(value: settings.videoSize.height)
        return attributes
    }
    var frameInterval = VideoCodec.defaultFrameInterval
    var expectedFrameRate = IOMixer.defaultFrameRate
    weak var delegate: (any VideoCodecDelegate)?
    var inputFormat: CMFormatDescription?
    private(set) var outputFormat: CMFormatDescription? {
        didSet {
            guard !CMFormatDescriptionEqual(outputFormat, otherFormatDescription: oldValue) else {
                return
            }
            delegate?.videoCodec(self, didOutput: outputFormat)
        }
    }
    private(set) var session: (any VTSessionConvertible)? {
        didSet {
            oldValue?.invalidate()
            invalidateSession = false
        }
    }
    private var invalidateSession = true
    private var presentationTimeStamp: CMTime = .invalid

    func appendImageBuffer(_ imageBuffer: CVImageBuffer, presentationTimeStamp: CMTime, duration: CMTime) {
        guard !willDropFrame(presentationTimeStamp) else {
            return
        }
        if invalidateSession {
            session = VTSessionMode.compression.makeSession(self)
        }
        _ = session?.encodeFrame(
            imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration
        ) { [unowned self] status, _, sampleBuffer in
            guard let sampleBuffer, status == noErr else {
                delegate?.videoCodec(self, errorOccurred: .failedToFlame(status: status))
                return
            }
            self.presentationTimeStamp = sampleBuffer.presentationTimeStamp
            outputFormat = sampleBuffer.formatDescription
            delegate?.videoCodec(self, didOutput: sampleBuffer)
        }
    }

    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRunning.wrappedValue else {
            return
        }
        if invalidateSession {
            session = VTSessionMode.decompression.makeSession(self)
            needsSync.wrappedValue = true
        }
        if !sampleBuffer.isNotSync {
            needsSync.wrappedValue = false
        }
        _ = session?.decodeFrame(sampleBuffer) { [unowned self] status, _, imageBuffer, presentationTimeStamp, duration in
            guard let imageBuffer, status == noErr else {
                self.delegate?.videoCodec(self, errorOccurred: .failedToFlame(status: status))
                return
            }
            var timingInfo = CMSampleTimingInfo(
                duration: duration,
                presentationTimeStamp: presentationTimeStamp,
                decodeTimeStamp: sampleBuffer.decodeTimeStamp
            )
            var videoFormatDescription: CMVideoFormatDescription?
            var status = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: imageBuffer,
                formatDescriptionOut: &videoFormatDescription
            )
            guard status == noErr else {
                delegate?.videoCodec(self, errorOccurred: .failedToFlame(status: status))
                return
            }
            var sampleBuffer: CMSampleBuffer?
            status = CMSampleBufferCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: imageBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: videoFormatDescription!,
                sampleTiming: &timingInfo,
                sampleBufferOut: &sampleBuffer
            )
            guard let buffer = sampleBuffer, status == noErr else {
                delegate?.videoCodec(self, errorOccurred: .failedToFlame(status: status))
                return
            }
            delegate?.videoCodec(self, didOutput: buffer)
        }
    }

    private func willDropFrame(_ presentationTimeStamp: CMTime) -> Bool {
        guard Self.defaultFrameInterval < frameInterval else {
            return false
        }
        return presentationTimeStamp.seconds - self.presentationTimeStamp.seconds <= frameInterval
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    @objc
    private func applicationWillEnterForeground(_ notification: Notification) {
        invalidateSession = true
    }

    @objc
    private func didAudioSessionInterruption(_ notification: Notification) {
        guard
            let userInfo: [AnyHashable: Any] = notification.userInfo,
            let value: NSNumber = userInfo[AVAudioSessionInterruptionTypeKey] as? NSNumber,
            let type = AVAudioSession.InterruptionType(rawValue: value.uintValue) else {
            return
        }
        switch type {
        case .ended:
            invalidateSession = true
        default:
            break
        }
    }
    #endif
}

extension VideoCodec: Running {
    // MARK: Running
    public func startRunning() {
        lockQueue.async {
            self.isRunning.wrappedValue = true
            #if os(iOS) || os(tvOS) || os(visionOS)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.didAudioSessionInterruption),
                name: AVAudioSession.interruptionNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.applicationWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
            #endif
        }
    }

    public func stopRunning() {
        lockQueue.async {
            self.session = nil
            self.invalidateSession = true
            self.needsSync.wrappedValue = true
            self.outputFormat = nil
            self.presentationTimeStamp = .invalid
            #if os(iOS) || os(tvOS) || os(visionOS)
            NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
            #endif
            self.isRunning.wrappedValue = false
        }
    }
}
