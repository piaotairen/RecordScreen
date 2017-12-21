//
//  RecordListViewController.swift
//  RecordScreen
//
//  Created by Cobb on 2017/12/19.
//  Copyright © 2017年 Cobb. All rights reserved.
//

import UIKit
import AVKit

class RecordListViewController: UIViewController {
    
    @IBOutlet weak var recordTableView: UITableView!
    
    /// 数据源
    var dataArray: [RecordVideoModel] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadRecordListData()
        recordTableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }
    
    func loadRecordListData() {
        let (filepaths, fileNames) = getAllMp4Path()
        for i in 0..<filepaths.count {
            let recordModel = RecordVideoModel()
            recordModel.videoPath = filepaths[i]
            recordModel.videoName = fileNames[i]
            dataArray.append(recordModel)
        }
        recordTableView.reloadData()
    }
    
    func getAllMp4Path() -> (filePaths: [String], fileNames: [String]) {
        let filePath = NSHomeDirectory() + "/Documents/recordVideo/"
        let fileManager = FileManager.default
        let directoryEnumerator = fileManager.enumerator(atPath: filePath)
        var filePathArray: [String] = []
        var fileNameArray: [String] = []
        while let file = directoryEnumerator?.nextObject() as? String {
            if file.hasSuffix(".mp4") {
                filePathArray.append(filePath + file)
                fileNameArray.append(file)
            }
        }
        return (filePathArray, fileNameArray)
    }
    
}

extension RecordListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44.0
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let player = AVPlayer(url: URL(fileURLWithPath: dataArray[indexPath.row].videoPath))
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        present(playerViewController, animated: true, completion: nil)
    }
}

extension RecordListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = recordTableView.dequeueReusableCell(withIdentifier: "cell")
        cell?.textLabel?.text = dataArray[indexPath.row].videoName
        return cell!
    }
}

