//
//  VideoCapture.swift
//  RecordScreen
//
//  Created by Cobb on 2017/12/19.
//  Copyright © 2017年 Cobb. All rights reserved.
//

import UIKit
import AVFoundation

protocol VideoCaptureDelegate: NSObjectProtocol {
    func recordingFinished(filePath: String)
    
    func recordingFailed(error: Error?)
}

class VideoCapture: NSObject {
    // MARK: - Property
    var videoWriter: AVAssetWriter?
    
    var videoWriterInput: AVAssetWriterInput?
    
    var avAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    /// 正在录制中
    var isRecording = false
    
    /// 正在将帧写入文件
    var isWriting = false
    
    /// 暂停
    var isPause = false
    
    /// 录制的开始时间
    var startTime: Date?
    
    /// 暂停时间
    var spaceTime: Double = 0.0
    
    /// 录制文件名
    let fileName = "recordOutput.mov"
    
    /// 按帧率写屏的定时器
    var writeTimer: Timer?
    
    /// 绘制layer的context
    var context: CGContext?
    
    /// 要绘制的目标layer
    var captureLayer: CALayer?
    
    /// 帧率 （默认10）
    var frameRate: Int = 10
    
    /// 输出路径
    var outputPath: String?
    
    /// 代理
    weak var delegate: VideoCaptureDelegate?
    
    let statusLock = NSLock()
    
    // MARK: - Life Cycle
    
    /// 获取实例
    static let `default`: VideoCapture? = {
        let manager = VideoCapture()
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
        frameRate = 10
    }
    
    /// 配置录制环境
    ///
    /// - Returns: 是否配置成功
    private func setUpWriter() -> Bool {
        let tmpSize = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        let size = CGSize(width: tmpSize.width * scale, height: tmpSize.height * scale)
        let filePath = tempFilePath()
        outputPath = filePath
        removeFilePath(filePath: filePath)
        
        /// configure videoWriter
        let fileUrl = URL(fileURLWithPath: filePath)
        try? videoWriter = AVAssetWriter(outputURL: fileUrl, fileType: .mov)
        
        /// Configure videoWriterInput
        /// 视频尺寸*比率，10.1相当于AVCaptureSessionPresetHigh，数值越大，显示越精细
        let videoCompressionProps = [AVVideoAverageBitRateKey: size.width * size.height]
        let videoSettings = [AVVideoCodecKey: AVVideoCodecH264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height, AVVideoCompressionPropertiesKey: videoCompressionProps] as [String : Any]
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = true
        
        /// 之前配置的下边注释掉的context使用的是kCVPixelFormatType_32ARGB，用起来颜色没有问题。但是用UIGraphicsBeginImageContextWithOptions([[UIApplication sharedApplication].delegate window].bounds.size, YES, 0) 配置的context使用kCVPixelFormatType_32ARGB的话颜色会变成粉色，替换成kCVPixelFormatType_32BGRA之后，颜色正常。。
        var bufferAttr: [String : Any] = [:]
        bufferAttr[kCVPixelBufferPixelFormatTypeKey as String] = kCVPixelFormatType_32BGRA
        /// 这个位置包括下面的两个，必须写成(int)size.width/16*16,因为这个的大小必须是16的倍数，否则图像会发生拉扯、挤压、旋转。。。。不知道为啥
        bufferAttr[kCVPixelBufferWidthKey as String] = size.width
        bufferAttr[kCVPixelBufferHeightKey as String] = size.height
        bufferAttr[kCVPixelBufferCGBitmapContextCompatibilityKey as String] = true
        avAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput!, sourcePixelBufferAttributes: bufferAttr)
        
        /// add input
        videoWriter?.add(videoWriterInput!)
        videoWriter?.startWriting()
        videoWriter?.startSession(atSourceTime: CMTimeMake(0, 1000))
        
        /// create context
        if context == nil {
            UIGraphicsBeginImageContextWithOptions((UIApplication.shared.delegate?.window??.bounds.size)!, true, 0)
            context = UIGraphicsGetCurrentContext()
        }
        if context == nil {
            print("Context not created!")
            return false
        }
        return true
    }
    
    /// 清理录制环境
    private func cleanUpWriter() {
        avAdaptor = nil
        videoWriterInput = nil
        videoWriter = nil
        startTime = nil
    }
    
    /// 完成录制工作
    private func completeRecordSession() {
        videoWriterInput?.markAsFinished()
        videoWriter?.finishWriting(completionHandler: { [weak self] in
            if let strongSelf = self, let writeStatus = strongSelf.videoWriter?.status  {
                switch writeStatus {
                case .completed:
                    print("Completed recording")
                    strongSelf.delegate?.recordingFinished(filePath: strongSelf.outputPath!)
                case .failed, .cancelled, .writing, .unknown:
                    print("recordingFailed")
                    strongSelf.delegate?.recordingFailed(error: strongSelf.videoWriter?.error)
                }
            }
        })
    }
    
    /// 录制每一帧
    private func drawFrame() {
        if isPause {
            spaceTime = spaceTime + 1.0 / Double(frameRate)
            return
        }
        if !isWriting {
            performSelector(onMainThread: #selector(VideoCapture.createFrame), with: nil, waitUntilDone: false)
        }
    }
    
    @objc private func createFrame() {
        if !isWriting, let currentContext = context {
            isWriting = true
            let width = CGFloat(currentContext.width)
            let height = CGFloat(currentContext.height)
            let clearRect = CGRect(x: 0, y: 0, width: width, height: height)
            currentContext.clear(clearRect)
            UIApplication.shared.delegate?.window??.layer.render(in: currentContext)
            UIApplication.shared.delegate?.window??.layer.contents = nil
            let contextImage = currentContext.makeImage()
            if isRecording, let writeImage = contextImage {
                let millisElapsed = NSDate().timeIntervalSince(startTime!) * 1000.0 - spaceTime * 1000.0
                let writeTime = CMTime(value: CMTimeValue(millisElapsed), timescale: CMTimeScale(1000.0))
                writeVideoFrameAtTime(time: writeTime, contextImage: writeImage)
            }
            isWriting = false
        }
    }
    
    private func writeVideoFrameAtTime(time: CMTime, contextImage newImage:CGImage)  {
        guard let writeInput = videoWriterInput, writeInput.isReadyForMoreMediaData else {
            return
        }
        statusLock.lock()
        var pixelBuffer: CVPixelBuffer? = nil
        let contextImage = newImage.copy()
        let imageData = contextImage?.dataProvider?.data
        
        // 在此我做了进入后台就结束录屏的操作，但是这不是最好的方案，因为在进入后台之后 avAdaptor.pixelBufferPool 会被自动释放，再次进入之后就会崩溃
        //有2种思路，1、进入后台就结束录制，唤醒了继续录制，然后录制的视频融合成一个视频
        //2、解决进入后台之后 avAdaptor.pixelBufferPool 会被自动释放的问题，但是avAdaptor.pixelBufferPool 是只读的，欢迎大牛帮忙 fix it.
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, (avAdaptor?.pixelBufferPool)!, &pixelBuffer)
        if status != 0 {
            /// could not get a buffer from the pool
        }
        /// set image data into pixel buffer
        /// UnsafeMutablePointer的转换做了修改  稍后检测影响
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0) )
        let destPixels = CVPixelBufferGetBaseAddress(pixelBuffer!)
        let opaquePtr = OpaquePointer(destPixels)
        let contextPtr = UnsafeMutablePointer<UInt8>(opaquePtr)
        CFDataGetBytes(imageData, CFRangeMake(0, CFDataGetLength(imageData)), contextPtr)
        ///XXX:  will work if the pixel buffer is contiguous and has the same bytesPerRow as the input data
        if status == 0 {
            let success = avAdaptor?.append(pixelBuffer!, withPresentationTime: time)
            if let result = success, !result {
                print("Warning:  Unable to write buffer to video")
            }
        }
        /// clean up
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        statusLock.unlock()
    }
    
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
                startTime = Date()
                spaceTime = 0.0
                isRecording = true
                isWriting = false
                writeTimer = Timer .scheduledTimer(withTimeInterval: 1.0 / Double(frameRate), repeats: true, block: { [weak self] (timer) in
                    if let strongSelf = self {
                        strongSelf.drawFrame()
                    }
                })
                if writeTimer != nil {
                    RunLoop.current.add(writeTimer!, forMode: .commonModes)
                }
            }
        }
        return start
    }
    
    /// 停止录制
    func stopRecord() {
        isPause = false
        isRecording = false
        writeTimer?.invalidate()
        writeTimer = nil
        completeRecordSession()
        cleanUpWriter()
    }
    
    /// 暂停录制
    func pauseRecord() {
        statusLock.lock()
        if isRecording {
            isPause = true
            isRecording = false
        }
        statusLock.unlock()
    }
    
    /// 重新开始录制
    func resumeRecord() {
        statusLock.lock()
        if isPause {
            isRecording = true
            isPause = false
        }
        statusLock.unlock()
    }
}
