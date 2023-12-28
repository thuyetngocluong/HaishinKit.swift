//
//  Server.swift
//  HaishinKit
//
//  Created by Zoro4rk on 21/12/2023.
//

import Foundation
import AVFoundation
import VideoToolbox


 public class Server123: NSObject {
    public let lockQueue: DispatchQueue = .init(label: "Server.lock")
     let videoCodec = VideoCodec()
     lazy var session = VTSessionMode.compression.makeSession(videoCodec)!
    private lazy var tsWriter = TSFileWriter()
    public private(set) lazy var mixer: IOMixer = {
        let mixer = IOMixer()
//        mixer.delegate = self
        return mixer
    }()
    
//    let server = GCDWebServer()
    
    public override init() {
        super.init()
       
    }
//    
//    private
//    func _setupServer() {
////        server.delegate = self
////        server.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self) { [weak self] request in
////            guard let self = self else { return GCDWebServerDataResponse(text: "OK") }
////            print("LNT THREAD", Thread.current)
////            let fileName = request.url.lastPathComponent
////            switch true {
////            case fileName == "playlist.m3u8":
////                let playlist = tsWriter.playlist
////                print("LNT playlist", playlist)
////                return GCDWebServerDataResponse(text: playlist)
////            case fileName.contains(".ts"):
////                if let data = self.tsWriter.getDataByFileName(fileName) {
////                    print("LNT fileName", data)
////
////                    return GCDWebServerDataResponse(data: data, contentType: "video/mp2t")
////                }
////                return GCDWebServerDataResponse(text: "OK")
////            default:
////                return GCDWebServerDataResponse(text: "OK")
////            }
////        }
////        
////        server.start(withPort: 2505, bonjourName: nil)
//    }
//    
    public func start() {
        lockQueue.async {
            self.tsWriter.expectedMedias.insert(.video)
//            self.startRecording()
            self.mixer.startEncoding(self.tsWriter)
            self.mixer.startRunning()
            self.tsWriter.startRunning()
        }
    }
    
    public func attachCamera(_ device: AVCaptureDevice?, onError: ((_ error: any Error) -> Void)? = nil) {
        lockQueue.async {
            do {
                try self.mixer.videoIO.attachCamera(device)
            } catch {
                onError?(error)
            }
        }
    }
    
    public func startRecording(_ settings: [AVMediaType: [String: Any]] = IORecorder.defaultOutputSettings) {
        mixer.recorder.outputSettings = settings
        mixer.recorder.startRunning()
    }

    /// Stop recording.
    public func stopRecording() {
        mixer.recorder.stopRunning()
    }
    
    public func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                   options: [NSObject: AnyObject]? = nil) {
        switch sampleBuffer.formatDescription?._mediaType {
        case kCMMediaType_Audio:
//            mixer.audioIO.lockQueue.async {
//                self.mixer.audioIO.appendSampleBuffer(sampleBuffer)
//            }
            break
        case kCMMediaType_Video:
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                session.encodeFrame(imageBuffer,
                                    presentationTimeStamp: sampleBuffer.presentationTimeStamp,
                                    duration: sampleBuffer.duration) { [unowned self] status, _, sampleBuffer in
                    guard let sampleBuffer, status == noErr else {
                        return
                    }
                    self.tsWriter.videoCodec(videoCodec, didOutput: sampleBuffer)
                }
            }
        default:
            break
        }
    }
    
    
     
//     var timingInfo = CMSampleTimingInfo(
//         duration: .invalid,
//         presentationTimeStamp: presentationTime,
//         decodeTimeStamp: .invalid
//     )
//     var videoFormatDescription: CMVideoFormatDescription?
//     var status = CMVideoFormatDescriptionCreateForImageBuffer(
//         allocator: kCFAllocatorDefault,
//         imageBuffer: pixelBuffer,
//         formatDescriptionOut: &videoFormatDescription
//     )
//     guard status == noErr else {
//         return
//     }
//     var sampleBuffer: CMSampleBuffer?
//     status = CMSampleBufferCreateForImageBuffer(
//         allocator: kCFAllocatorDefault,
//         imageBuffer: pixelBuffer,
//         dataReady: true,
//         makeDataReadyCallback: nil,
//         refcon: nil,
//         formatDescription: videoFormatDescription!,
//         sampleTiming: &timingInfo,
//         sampleBufferOut: &sampleBuffer
//     )
//     guard let sampleBuffer, status == noErr else {
//         return
//     }
//     appendSampleBuffer(sampleBuffer)
}
//
