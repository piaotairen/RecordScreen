//
//  ViewController.swift
//  RecordScreen
//
//  Created by Cobb on 2017/12/19.
//  Copyright © 2017年 Cobb. All rights reserved.
//

import UIKit
import AVFoundation
import ReplayKit

class ViewController: UIViewController {
    // MARK: - Property
    /// 时间视图
    @IBOutlet weak var timeLabel: UILabel!
    
    /// 动画视图
    @IBOutlet weak var animateLabel: UILabel!
    
    /// 正在录制中
    var isRecording = false
    
    /// 正在暂停中
    var isPause = false
    
    /// 视频捕获类
    let videoCapture = VideoCapture.default
    
    /// 音频捕获类
    let audioCapture = AudioCapture.default
    
    /// 输出路径
    var outputPath: String?
    
    /// 录制Timer
    var recordTimer: Timer?
    
    /// 计时
    var timeCount: Int = 0
    
    /// 视频名
    let videoName = "videoName"
    
    // MARK: - Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.enterBackground), name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isRecording = false
        isPause = false
    }
    
    // MARK: - Private
    
    @objc private func enterBackground() {
        if isRecording {
            stopAndSaveVideo()
        }
    }
    
    /// 根据文件名创建文件路径
    ///
    /// - Parameter fileName: 文件名
    private func createFileByName(fileName: String, type: String) -> String {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "\(fileName).\(type)"
    }
    
    /// 删除视频地址
    private func removeFilePath(filePath: String) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: filePath) {
            try? fileManager.removeItem(atPath: filePath)
        }
    }
    
    /// 开始视频录制 稍后进行音频录制
    private func startVideoRecord() {
        videoCapture?.frameRate = 35
        videoCapture?.delegate = self
        audioCapture?.audioRecord?.delegate = self
        audioCapture?.delegate = self
        videoCapture?.startRecord()
        let path = createFileByName(fileName: videoName, type: "wav")
        removeFilePath(filePath: path)
        perform(#selector(ViewController.startAudioRecord), with: nil, afterDelay: 0.1)
    }
    
    /// 停止录制并保存
    private func stopAndSaveVideo() {
        isRecording = false
        isPause = false
        videoCapture?.stopRecord()
        timeCount = 0
        timeLabel.text = "00:00:00"
        if recordTimer != nil {
            recordTimer?.invalidate()
            recordTimer = nil
        }
    }
    
    /// 更新录制时间
    @objc private func recordTimeUpdate() {
        timeCount = timeCount + 1
        timeLabel.text = String(format: "%02d:%02d:%02d", arguments: [timeCount / 3600, (timeCount / 60) % 60, timeCount % 60])
    }
    
    /// 合并音视频
    ///
    /// - Parameters:
    ///   - videoPath: 视频路径
    ///   - audio: 音频路径
    private func mergeVideo(_ videoPath: String, withAudio audioPath: String) {
        let audioURL = URL(string: audioPath)
        let videoUrl = URL(string: videoPath)
        let audioAsset = AVURLAsset(url: audioURL!, options: nil)
        let videoAsset = AVURLAsset(url: videoUrl!, options: nil)
        
        /// 混合音频
        let mixComposition = AVMutableComposition()
        let compositionAudioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        try? compositionAudioTrack?.insertTimeRange(CMTimeRangeMake(kCMTimeZero, audioAsset.duration), of: audioAsset.tracks(withMediaType: .audio)[0], at: kCMTimeZero)
        
        /// 混合视频
        let compositionVideoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try? compositionVideoTrack?.insertTimeRange(CMTimeRangeMake(kCMTimeZero, videoAsset.duration), of: videoAsset.tracks(withMediaType: .video)[0], at: kCMTimeZero)
        let assetExport = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetPassthrough)
        
        /// 保存混合后的文件的过程
        let compositionVideoName = "export2.mov"
        let exportPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "\(compositionVideoName)"
        removeFilePath(filePath: exportPath)
        let  exportUrl = URL(string: exportPath)
        
        assetExport?.outputFileType = AVFileType(rawValue: "com.apple.quicktime-movie")
        assetExport?.outputURL = exportUrl
        assetExport?.shouldOptimizeForNetworkUse = true
        assetExport?.exportAsynchronously(completionHandler: { [weak self] in
            /// your completion code here
            self?.mergedidFinish(videoPath: exportPath)
        })
    }
    
    /// 合并完成调用
    private func mergedidFinish(videoPath: String) {
        let time = Date().timeIntervalSince1970
        let fileName = String(format: "%ld.mp4", arguments: [Int(time)])
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "/recordVideo/\(fileName)"
        if FileManager.default.fileExists(atPath: videoPath) {
            try? FileManager.default.moveItem(at: URL(string: videoPath)!, to: URL(string: path)!)
        }
        if FileManager.default.fileExists(atPath: (videoCapture?.outputPath)!) {
            try? FileManager.default.removeItem(at: URL(string: (videoCapture?.outputPath)!)!)
        }
    }
    
    // MARK: - 点击事件
    
    /// 展示动画
    @IBAction private func showAnimate(_ sender: Any) {
        let sprintAni = CASpringAnimation(keyPath: "position.y")
        sprintAni.damping = 10
        sprintAni.mass = 5
        sprintAni.stiffness = 50
        sprintAni.initialVelocity = 3
        sprintAni.duration = 2
        sprintAni.toValue = 400
        sprintAni.fillMode = kCAFillModeForwards
        sprintAni.isRemovedOnCompletion = false
        sprintAni.repeatCount = .infinity
        animateLabel.layer.add(sprintAni, forKey: "anykey")
    }
    
    /// 进入视频列表
    @IBAction private func enterListViewController(_ sender: Any) {
        stopAndSaveVideo()
    }
    
    /// 准备录制
    @IBAction private func startRecord(_ sender: Any) {
        guard !isRecording else {
            return
        }
        isRecording = true
        startVideoRecord()
        recordTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(ViewController.recordTimeUpdate), userInfo: nil, repeats: true)
        RunLoop.main.add(recordTimer!, forMode: .commonModes)
    }
    
    /// 暂停或继续
    @IBAction private func pauseRecord(_ sender: Any) {
        if isRecording {
            /// 暂停
            isRecording = false
            isPause = true
            videoCapture?.pauseRecord()
            audioCapture?.pauseRecord()
            if recordTimer != nil {
                recordTimer?.invalidate()
                recordTimer = nil
            }
        } else {
            /// 继续
            isRecording = true
            isPause = false
            videoCapture?.resumeRecord()
            audioCapture?.resumeRecord()
            recordTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(ViewController.recordTimeUpdate), userInfo: nil, repeats: true)
            RunLoop.main.add(recordTimer!, forMode: .commonModes)
        }
    }
    
    /// 结束录制
    @IBAction private func endRecord(_ sender: Any) {
        stopAndSaveVideo()
    }
    
    // MARK: - 音频处理
    
    /// 音频录制
    @objc private func startAudioRecord() {
        audioCapture?.beginRecord(byFileName: videoName)
    }
    
    // MARK: - 视频处理
    
    
    // MARK: - ReplayKit
    
    /// 使用 ReplayKit 开始录制
    @IBAction private func startRecordWithReplayKit() {
        /// 判断系统是否支持
        if RPScreenRecorder.shared().isAvailable {
            RPScreenRecorder.shared().startRecording(handler: { (error) in
                /// 处理发生的错误，如设用户权限原因无法开始录制等
                print(error?.localizedDescription as Any)
            })
        } else {
            /// 录制回放功能不可用
        }
    }
    
    /// 使用 ReplayKit 结束录制
    @IBAction private func endRecordWithReplayKit() {
        RPScreenRecorder.shared().stopRecording { (previewController, error) in
            if previewController != nil {
                previewController?.previewControllerDelegate = self
                self.present(previewController!, animated: true, completion: nil)
            } else {
                /// 处理发生的错误，如磁盘空间不足而停止等
                print(error?.localizedDescription as Any)
            }
        }
    }
}

extension ViewController: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        
    }
}

extension ViewController: AudioCaptureDelegate {
    func wavComplete() {
        if audioCapture != nil {
            let path = createFileByName(fileName: videoName, type: "wav")
            /// 视频录制结束,为视频加上音乐
            mergeVideo(outputPath!, withAudio: path)
        }
    }
}

extension ViewController: VideoCaptureDelegate {
    func recordingFinished(filePath: String) {
        outputPath = filePath
        if audioCapture != nil {
            audioCapture?.endRecord()
        }
    }
    
    func recordingFailed(error: Error?) {
        
    }
}

extension ViewController: RPPreviewViewControllerDelegate {
    func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        /// 返回之前界面
        previewController.dismiss(animated: true, completion: nil)
    }
    
    func previewController(_ previewController: RPPreviewViewController, didFinishWithActivityTypes activityTypes: Set<String>) {
        /// 返回之前界面
        previewController.dismiss(animated: true, completion: nil)
        print(activityTypes)
    }
}
