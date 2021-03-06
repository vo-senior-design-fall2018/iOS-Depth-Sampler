//
//  RealtimeDepthViewController.swift
//
//  Created by Shuichi Tsutsumi on 2018/08/20.
//  Copyright © 2018 Shuichi Tsutsumi. All rights reserved.
//

import UIKit
import MetalKit
import AVFoundation
import ReplayKit


class RealtimeDepthViewController: UIViewController {

    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var mtkView: MTKView!
    @IBOutlet weak var filterSwitch: UISwitch!
    @IBOutlet weak var disparitySwitch: UISwitch!
    @IBOutlet weak var equalizeSwitch: UISwitch!
    @IBOutlet weak var recordButton: UIButton!

    private var videoCapture: VideoCapture!
    private var metalVideoRecorder: MetalVideoRecorder!
    var currentCameraType: CameraType = .back(true)

    private let serialQueue = DispatchQueue(label: "com.shu223.iOS-Depth-Sampler.queue")
    
    //let recorder = RPScreenRecorder.shared()
    private var isRecording = false

    private var renderer: MetalRenderer!
    private var depthImage: CIImage?
    private var currentDrawableSize: CGSize!

    private var videoImage: CIImage?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let device = MTLCreateSystemDefaultDevice()!
        mtkView.device = device
        mtkView.backgroundColor = UIColor.clear
        mtkView.delegate = self
        renderer = MetalRenderer(metalDevice: device, renderDestination: mtkView)
        currentDrawableSize = mtkView.currentDrawable!.layer.drawableSize
        
        videoCapture = VideoCapture(cameraType: currentCameraType,
                                    preferredSpec: nil,
                                    previewContainer: previewView.layer)
        
    
    
        
        videoCapture.syncedDataBufferHandler = { [weak self] videoPixelBuffer, depthData, face in
            guard let self = self else { return }
            
            self.videoImage = CIImage(cvPixelBuffer: videoPixelBuffer)

            var useDisparity: Bool = false
            var applyHistoEq: Bool = false
            DispatchQueue.main.sync(execute: {
                useDisparity = self.disparitySwitch.isOn
                applyHistoEq = self.equalizeSwitch.isOn
            })
            
            self.serialQueue.async {
                guard let depthData = useDisparity ? depthData?.convertToDisparity() : depthData else { return }
                
                guard let ciImage = depthData.depthDataMap.transformedImage(targetSize: self.currentDrawableSize, rotationAngle: 0) else { return }
                self.depthImage = applyHistoEq ? ciImage.applyingFilter("YUCIHistogramEqualization") : ciImage
                
                if(self.isRecording){ //start the loop
                    let context = CIContext()
                    let imaged = context.createCGImage(self.depthImage!, from: self.depthImage!.extent) //depth CGI image
                    let imagen = context.createCGImage(self.videoImage!, from: self.videoImage!.extent) //rgb CGI image
                    let outputd = UIImage(cgImage: imaged!) //convert depth CGI to UIImage
                    let outputn = UIImage(cgImage: imagen!) //convert rgb CGI to UIImage
                    
                    let time = NSDate()
                    let timestamp = time.timeIntervalSince1970
                    let str = NSString(format: "%.6f", timestamp)
                    let filename = str.appending(".png")
                    
                    
                    
                    let row = str.appending(" rgb/") + filename + " " + str.appending(" depth/") + filename + "\n"
                    
                    let path =  NSHomeDirectory().appending("/Documents/")
                    let directoryPathText =  NSHomeDirectory().appending("/Documents/associations.txt")
                    let writePath = NSURL(fileURLWithPath: path)
                    try? FileManager.default.createDirectory(atPath: writePath.path!, withIntermediateDirectories: true)
                    let file = writePath.appendingPathComponent("associations.txt")
                    
                    //create a folder for depth images
                    let directoryPathDepth =  NSHomeDirectory().appending("/Documents/depth/")
                    if !FileManager.default.fileExists(atPath: directoryPathDepth) {
                        do {
                            try FileManager.default.createDirectory(at: NSURL.fileURL(withPath: directoryPathDepth), withIntermediateDirectories: true, attributes: nil)
                        } catch {
                            print(error)
                        }
                    }
                    
                    //create a folder for rgb images
                    let directoryPathRGB =  NSHomeDirectory().appending("/Documents/rgb/")
                    if !FileManager.default.fileExists(atPath: directoryPathRGB) {
                        do {
                            try FileManager.default.createDirectory(at: NSURL.fileURL(withPath: directoryPathRGB), withIntermediateDirectories: true, attributes: nil)
                        } catch {
                            print(error)
                        }
                    }
                    
                    //create path for associations.txt
                    if !FileManager.default.fileExists(atPath: directoryPathText) {
                        do {
                            try "".write(to: file!, atomically: false, encoding: String.Encoding.utf8)
                        } catch {
                            print(error)
                        }
                    }
                    
                    //if the path exists, write to it
                    if FileManager.default.fileExists(atPath: path) {
                        do {
                            let fileHandle = try FileHandle(forWritingTo: file!)
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(row.data(using: .utf8)!)
                        } catch {
                            print("Error writing to file \(error)")
                        }
                    }
                    
                    let filepathd = directoryPathDepth.appending(filename)
                    let filepathn = directoryPathRGB.appending(filename)
                    let urld = NSURL.fileURL(withPath: filepathd)
                    let urln = NSURL.fileURL(withPath: filepathn)
                    do {
                        try outputd.jpegData(compressionQuality: 1.0)?.write(to: urld, options: .atomic)
                        try outputn.jpegData(compressionQuality: 1.0)?.write(to: urln, options: .atomic)
                        debugPrint( String.init(filepathd))
                        debugPrint( String.init(filepathn))
                        
                    } catch {
                        print(error)
                        //print("file cant not be save at path \(filepathd), with error : \(error)");
                        debugPrint(filepathd)
                        debugPrint(filepathn)
                    }
                    
                }
                
            }
        }
        videoCapture.setDepthFilterEnabled(true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let videoCapture = videoCapture else {return}
        videoCapture.startCapture()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let videoCapture = videoCapture else {return}
        videoCapture.resizePreview()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        guard let videoCapture = videoCapture else {return}
        videoCapture.imageBufferHandler = nil
        videoCapture.stopCapture()
        mtkView.delegate = nil
        super.viewWillDisappear(animated)
    }
    
    // MARK: - Actions
    
    @IBAction func cameraSwitchBtnTapped(_ sender: UIButton) {
        switch currentCameraType {
        case .back:
            currentCameraType = .front(true)
        case .front:
            currentCameraType = .back(true)
        }
        videoCapture.changeCamera(with: currentCameraType)
    }
    
    @IBAction func filterSwitched(_ sender: UISwitch) {
        videoCapture.setDepthFilterEnabled(sender.isOn)
    }
    
    
    
    @IBAction func recordButtonTapped(_ sender: UIButton) {
        if(isRecording){
            sender.backgroundColor = .white
            isRecording = false
        }
        else{
            sender.backgroundColor = .red
            isRecording = true
            
        }
    }
    
}

extension RealtimeDepthViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        currentDrawableSize = size
    }
    
    func draw(in view: MTKView) {
        if let image = depthImage {
            renderer.update(with: image)
        }
    }
}

