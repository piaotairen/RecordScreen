//
//  ScreenRecorder.swift
//  RecordScreen
//
//  Created by Cobb on 2017/12/22.
//  Copyright © 2017年 Cobb. All rights reserved.
//

import UIKit
import AVFoundation

class ScreenRecorder: NSObject {
    // MARK: 截屏Property
    var videoWriter: AVAssetWriter?
    
    var videoWriterInput: AVAssetWriterInput?
    
    var avAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    /// 正在录制中
    var isRecording = false
    
    var displayLink: CADisplayLink?
    
    var firstTimeStamp: CFTimeInterval = 0
    
    let renderQueue = DispatchQueue(label: "com.liveclaw.record.render")
    
    let appendPixelBufferQueue = DispatchQueue(label: "com.liveclaw.record.append")
    
    let frameRenderingSemaphore = DispatchSemaphore(value: 1)
    
    let pixelAppendSemaphore = DispatchSemaphore(value: 1)
    
    var viewSize: CGSize = CGSize.zero
    
    var scale: CGFloat = 0
    
    var rgbColorSpace: CGColorSpace?
    
    var outputBufferPool: CVPixelBufferPool?
    
    /// 输出路径
    var outputPath: String?
    
    // MARK: - Life Cycle
    
    /// 获取实例
    static let `default`: ScreenRecorder? = {
        let manager = ScreenRecorder()
        manager.customSetUp()
        return manager
    }()
    
    override init() {
        super.init()
    }
    
    deinit {
        cleanUpWriter()
    }
    
    // MARK: - Private
    
    /// 自定义配置
    private func customSetUp() {
        if let windowSize = UIApplication.shared.delegate?.window??.bounds.size {
            viewSize = windowSize
        }
        scale = UIScreen.main.scale
        /// 此写法注意是否正确
        DispatchQueue.global(qos: .userInteractive).setTarget(queue: renderQueue)
    }
    
    /// 配置录制环境
    ///
    /// - Returns: 是否配置成功
    private func setUpWriter() -> Bool {
        rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let size = CGSize(width: viewSize.width * scale, height: viewSize.height * scale)
        
        /// kCVPixelFormatType_32ARGB，用起来颜色没有问题。
        var bufferAttr: [String : Any] = [:]
        bufferAttr[kCVPixelBufferPixelFormatTypeKey as String] = kCVPixelFormatType_32BGRA
        bufferAttr[kCVPixelBufferWidthKey as String] = size.width
        bufferAttr[kCVPixelBufferHeightKey as String] = size.height
        bufferAttr[kCVPixelBufferBytesPerRowAlignmentKey as String] = size.width * scale * 4
        bufferAttr[kCVPixelBufferCGBitmapContextCompatibilityKey as String] = true
        
        outputBufferPool = nil
        CVPixelBufferPoolCreate(nil, nil, bufferAttr as CFDictionary, &outputBufferPool)
        
        /// configure videoWriter
        let filePath = tempFilePath()
        outputPath = filePath
        removeFilePath(filePath: filePath)
        let fileUrl = URL(fileURLWithPath: filePath)
        try? videoWriter = AVAssetWriter(outputURL: fileUrl, fileType: .mov)
        
        /// Configure videoWriterInput
        let pixelNumber = viewSize.width * viewSize.height * scale
        let videoCompressionProps = [AVVideoAverageBitRateKey: pixelNumber * 11.4]
        let videoSettings = [AVVideoCodecKey: AVVideoCodecH264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height, AVVideoCompressionPropertiesKey: videoCompressionProps] as [String : Any]
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = true
        videoWriterInput?.transform = transformForDeviceOrientation()
        
        avAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput!, sourcePixelBufferAttributes: nil)
        
        /// add input
        videoWriter?.add(videoWriterInput!)
        videoWriter?.startWriting()
        videoWriter?.startSession(atSourceTime: CMTimeMake(0, 1000))
        return true
    }
    
    /// 屏幕旋转
    private func transformForDeviceOrientation() -> CGAffineTransform {
        var videoTransform = CGAffineTransform.identity
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            videoTransform = CGAffineTransform(rotationAngle: CGFloat(-(Float.pi / 2)))
        case .landscapeRight:
            videoTransform = CGAffineTransform(rotationAngle: CGFloat((Float.pi / 2)))
        case .portraitUpsideDown:
            videoTransform = CGAffineTransform(rotationAngle: CGFloat(Float.pi))
        default:
            videoTransform = CGAffineTransform.identity
        }
        return videoTransform
    }
    
    /// 清理录制环境
    private func cleanUpWriter() {
        avAdaptor = nil
        videoWriterInput = nil
        videoWriter = nil
        firstTimeStamp = 0
    }
    
    /// 完成录制工作
    private func completeRecordSession() {
        renderQueue.async {
            self.appendPixelBufferQueue.sync {
                self.videoWriterInput?.markAsFinished()
                self.videoWriter?.finishWriting(completionHandler: { [weak self] in
                    if let strongSelf = self, let writeStatus = strongSelf.videoWriter?.status  {
                        strongSelf.cleanUpWriter()
                        switch writeStatus {
                        case .completed:
                            print("Completed recording")
                            strongSelf.recordingFinished(videoPath: strongSelf.outputPath!)
                        case .failed, .cancelled, .writing, .unknown:
                            print("recordingFailed")
                            strongSelf.recordingFailed(error: strongSelf.videoWriter?.error)
                        }
                    }
                })
            }
        }
    }
    
    /// 关闭录制工作
    private func closeRecordSession() {
        renderQueue.async {
            self.appendPixelBufferQueue.sync {
                self.videoWriterInput?.markAsFinished()
                self.videoWriter?.finishWriting(completionHandler: { [weak self] in
                    if let strongSelf = self, let writeStatus = strongSelf.videoWriter?.status  {
                        strongSelf.cleanUpWriter()
                        switch writeStatus {
                        case .completed:
                            print("Completed recording")
                        case .failed, .cancelled, .writing, .unknown:
                            print("recordingFailed")
                        }
                    }
                })
            }
        }
    }
    
    /// 录制完成调用
    private func recordingFinished(videoPath: String) {
        let time = Date().timeIntervalSince1970
        let fileName = String(format: "%ld.mp4", arguments: [Int(time)])
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "/recordVideo/\(fileName)"
        if FileManager.default.fileExists(atPath: videoPath) {
            try? FileManager.default.moveItem(at: URL(string: videoPath)!, to: URL(string: path)!)
        }
        if FileManager.default.fileExists(atPath: (self.outputPath)!) {
            try? FileManager.default.removeItem(at: URL(string: (self.outputPath)!)!)
        }
    }
    
    /// 录制失败调用
    private func recordingFailed(error: Error?) {
        
    }
    
    // MARK: - 截屏方式
    
    @objc private func writeVideoFrame() {
        if frameRenderingSemaphore.wait(timeout: .now()) != .timedOut { return }
        renderQueue.async {
            if let input = self.videoWriterInput, input.isReadyForMoreMediaData, let link = self.displayLink {
                if self.firstTimeStamp == 0 {
                    self.firstTimeStamp = link.timestamp
                }
                let elapsed = link.timestamp - self.firstTimeStamp
                let time = CMTimeMakeWithSeconds(elapsed, 1000)
                
                var pixelBuffer: CVPixelBuffer?
                /// inout 参数传递 注意写法
                let bitmapContext = self.createPixelBufferAndBitmapContext(pixelBuffer: &pixelBuffer)
                
                /// draw each window into the context (other windows include UIKeyboard, UIAlert)
                /// FIX: UIKeyboard is currently only rendered correctly in portrait orientation
                DispatchQueue.main.sync {
                    UIGraphicsPushContext(bitmapContext)
                    let window = UIApplication.shared.delegate?.window
                    let rectArea = CGRect(x: 0, y: 0, width: self.viewSize.width, height: self.viewSize.height)
                    window??.drawHierarchy(in: rectArea, afterScreenUpdates: false)
                    UIGraphicsPopContext()
                }
                
                /// append pixelBuffer on a async dispatch_queue, the next frame is rendered whilst this one appends
                /// must not overwhelm the queue with pixelBuffers, therefore:
                /// check if _append_pixelBuffer_queue is ready
                /// if it’s not ready, release pixelBuffer and bitmapContext
                if self.pixelAppendSemaphore.wait(timeout: .now()) == .timedOut {
                    self.appendPixelBufferQueue.async {
                        if let curAVAdaptor = self.avAdaptor, let buffter = pixelBuffer {
                            let success = curAVAdaptor.append(buffter, withPresentationTime: time)
                            if  !success {
                                /// Warning: Unable to write buffer to video
                            }
                            CVPixelBufferUnlockBaseAddress(buffter, CVPixelBufferLockFlags(rawValue: 0))
                            self.pixelAppendSemaphore.signal()
                        }
                    }
                } else {
                    if let buffter = pixelBuffer {
                        CVPixelBufferUnlockBaseAddress(buffter, CVPixelBufferLockFlags(rawValue: 0))
                    }
                }
                self.frameRenderingSemaphore.signal()
            }
        }
    }
    
    private func  createPixelBufferAndBitmapContext(pixelBuffer: UnsafeMutablePointer<CVPixelBuffer?>) -> CGContext {
        CVPixelBufferPoolCreatePixelBuffer(nil, outputBufferPool!, pixelBuffer)
        CVPixelBufferLockBaseAddress(pixelBuffer.pointee!, CVPixelBufferLockFlags(rawValue: 0))
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        let bitmapContext = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer.pointee!),
                                      width: CVPixelBufferGetWidth(pixelBuffer.pointee!),
                                      height: CVPixelBufferGetHeight(pixelBuffer.pointee!),
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer.pointee!), space: rgbColorSpace!,
                                      bitmapInfo: bitmapInfo.rawValue)
        bitmapContext?.scaleBy(x: scale, y: scale)
        let flipVertical = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: viewSize.height)
        bitmapContext!.concatenate(flipVertical)
        return bitmapContext!
    }
    
    
    // MARK: - File
    
    /// 视频的存放地址（如非必要 最好是放在caches里面）
    private func tempFilePath() -> String {
        let fileManager = FileManager.default
        let finalPath = NSHomeDirectory() + "/Documents/recordVideo/"
        if !fileManager.fileExists(atPath: finalPath) {
            try? fileManager.createDirectory(at: URL(fileURLWithPath: finalPath), withIntermediateDirectories: true, attributes: nil)
        }
        let currentTime = Int(NSDate().timeIntervalSince1970)
        let outputPath = finalPath + "\(currentTime).mp4"
        print(outputPath)
        removeFilePath(filePath: outputPath)
        return outputPath
    }
    
    /// 删除视频地址
    private func removeFilePath(filePath: String) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: filePath) {
            try? fileManager.removeItem(atPath: filePath)
        }
    }
    
    // MARK: - Public
    
    /// 开始录制
    ///
    /// - Returns: 是否开始
    @discardableResult
    func startRecord() -> Bool {
        var start = false
        if !isRecording {
            start = setUpWriter()
            if start {
                isRecording = true
                displayLink = CADisplayLink(target: self, selector: #selector(ScreenRecorder.writeVideoFrame))
                displayLink?.add(to: RunLoop.main, forMode: .commonModes)
            }
        }
        return start
    }
    
    /// 停止录制
    func stopRecord() {
        if isRecording {
            isRecording = false
            displayLink?.remove(from: RunLoop.main, forMode: .commonModes)
            completeRecordSession()
        }
    }
    
    /// 关闭录制
    func closeRecord() {
        if isRecording {
            isRecording = false
            displayLink?.remove(from: RunLoop.main, forMode: .commonModes)
            closeRecordSession()
        }
    }
    
}
