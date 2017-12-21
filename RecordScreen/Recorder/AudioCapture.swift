//
//  AudioCapture.swift
//  RecordScreen
//
//  Created by Cobb on 2017/12/19.
//  Copyright © 2017年 Cobb. All rights reserved.
//

import UIKit
import AVFoundation

protocol AudioCaptureDelegate: NSObjectProtocol {
    func wavComplete()
}

class AudioCapture: NSObject {
    // MARK: - Property
    /// 音频录制
    var audioRecord: AVAudioRecorder?
    
    /// 录音文件路径
    var audioFilePath: String?
    
    /// 是否暂停
    var isPause = false
    
    /// 代理
    weak var delegate: AudioCaptureDelegate?
    
    /// 录制或暂停通知 （是否系统通知）
    let recordOrPauseNotification = NSNotification.Name(rawValue: "recordOrPause")
    
    // MARK: - Life Cycle
    
    /// 获取实例
    static let `default`: AudioCapture? = {
        let manager = AudioCapture()
        return manager
    }()
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: recordOrPauseNotification, object: nil)
    }
    
    // MARK: - Private
    
    /// 录制或暂停通知
    @objc private func recordOrPause(sender: NSNotification) {
        let record = sender.object as! String
        if Int(record) == 0 {
            pauseRecord()
        } else {
            startRecord()
        }
    }
    
    /// 根据文件名创建文件路径
    ///
    /// - Parameter type: 文件类型
    private func createAudioFile(type: String) -> String {
        let fileManager = FileManager.default
        let finalPath = NSHomeDirectory() + "/Documents/recordAudio/"
        if !fileManager.fileExists(atPath: finalPath) {
            try? fileManager.createDirectory(at: URL(fileURLWithPath: finalPath), withIntermediateDirectories: true, attributes: nil)
        }
        let currentTime = Int(NSDate().timeIntervalSince1970)
        let outputPath = finalPath + "\(currentTime).\(type)"
        return outputPath
    }
    
    /// 获取音频录制设置
    private func getAudioRecorderSettings() -> [String: Any] {
        return [AVSampleRateKey: 8000.0, /// 采样率
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, /// 采样位数 默认 16
            AVNumberOfChannelsKey: 1 /// 通道的数目
            ] as [String: Any]
    }
    
    /// 开始录制
    private func startRecord() {
        audioRecord?.record()
        isPause = false
    }
    
    // MARK: - Public
    
    /// 开始录制
    ///
    /// - Parameter file: 录制文件名
    func beginRecord(byFileName file: String) {
        NotificationCenter.default.addObserver(self, selector: #selector(AudioCapture.recordOrPause), name: recordOrPauseNotification, object: nil)
        /// 设置录音路径
        audioFilePath = createAudioFile(type: "wav")
        /// 初始化录音
        let finalFile = audioFilePath?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        let temp = try? AVAudioRecorder(url: URL(string: finalFile!)!, settings: getAudioRecorderSettings())
        audioRecord = temp
        audioRecord?.isMeteringEnabled = true
        audioRecord?.prepareToRecord()
        /// 开始录音
        try? AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord)
        try? AVAudioSession.sharedInstance().setActive(true)
        audioRecord?.record()
    }
    
    /// 结束录制
    func endRecord() {
        if let recorder = audioRecord {
            if recorder.isRecording || (!recorder.isRecording && isPause) {
                audioRecord?.stop()
                audioRecord = nil
            }
        }
        delegate?.wavComplete()
        NotificationCenter.default.removeObserver(self, name: recordOrPauseNotification, object: nil)
    }
    
    /// 暂停录制
    func pauseRecord() {
        if let recorder = audioRecord, recorder.isRecording {
            audioRecord?.pause()
        }
        isPause = true
    }
    
    /// 重启录制
    func resumeRecord() {
        startRecord()
    }
}
