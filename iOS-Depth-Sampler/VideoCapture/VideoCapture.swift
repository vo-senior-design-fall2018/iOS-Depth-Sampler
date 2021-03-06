//
//  VideoCapture.swift
//
//  Created by Shuichi Tsutsumi on 4/3/16.
//  Copyright © 2016 Shuichi Tsutsumi. All rights reserved.
//

import AVFoundation
import Foundation
import UIKit


struct VideoSpec {
    var fps: Int32?
    var size: CGSize?
}

typealias ImageBufferHandler = (CVPixelBuffer, CMTime, CVPixelBuffer?) -> Void
typealias SynchronizedDataBufferHandler = (CVPixelBuffer, AVDepthData?, AVMetadataObject?) -> Void

extension AVCaptureDevice {
    func printDepthFormats() {
        formats.forEach { (format) in
            let depthFormats = format.supportedDepthDataFormats
            if depthFormats.count > 0 {
                print("format: \(format), supported depth formats: \(depthFormats)")
            }
        }
    }
}

class VideoCapture: NSObject {

    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice!
    private var videoConnection: AVCaptureConnection!
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let fileOutput = AVCaptureMovieFileOutput()
    //private var outputFileURL: URL
    
    private let dataOutputQueue = DispatchQueue(label: "com.shu223.dataOutputQueue")

    var imageBufferHandler: ImageBufferHandler?
    var syncedDataBufferHandler: SynchronizedDataBufferHandler?

    // プロパティで保持しておかないとdelegate呼ばれない
    // AVCaptureDepthDataOutputはプロパティで保持しなくても大丈夫（CaptureSessionにaddOutputするからだと思う）
    private var dataOutputSynchronizer: AVCaptureDataOutputSynchronizer!
    
    // プロパティに保持しておかなくてもOKだが、AVCaptureSynchronizedDataCollectionからデータを取り出す際にあると便利
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    
    init(cameraType: CameraType, preferredSpec: VideoSpec?, previewContainer: CALayer?)
    {
        super.init()
        
        captureSession.beginConfiguration()
        
        // inputPriorityだと深度とれない
        captureSession.sessionPreset = AVCaptureSession.Preset.photo
        
        setupCaptureVideoDevice(with: cameraType)
        
        
        
        // setup preview
        if let previewContainer = previewContainer {
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = previewContainer.bounds
            previewLayer.contentsGravity = CALayerContentsGravity.resizeAspectFill
            previewLayer.videoGravity = .resizeAspectFill
            previewContainer.insertSublayer(previewLayer, at: 0)
            self.previewLayer = previewLayer
        }
        
        // setup outputs
        do {
            // video output
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
            guard captureSession.canAddOutput(videoDataOutput) else { fatalError() }
            captureSession.addOutput(videoDataOutput)
            videoConnection = videoDataOutput.connection(with: .video)

            // depth output
            guard captureSession.canAddOutput(depthDataOutput) else { fatalError() }
            captureSession.addOutput(depthDataOutput)
            depthDataOutput.setDelegate(self, callbackQueue: dataOutputQueue)
            depthDataOutput.isFilteringEnabled = false
            guard let connection = depthDataOutput.connection(with: .depthData) else { fatalError() }
            connection.isEnabled = true
            
            // metadata output
            guard captureSession.canAddOutput(metadataOutput) else { fatalError() }
            captureSession.addOutput(metadataOutput)
            if metadataOutput.availableMetadataObjectTypes.contains(.face) {
                metadataOutput.metadataObjectTypes = [.face]
            }

            
            // synchronize outputs
            dataOutputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput, metadataOutput])
            dataOutputSynchronizer.setDelegate(self, queue: dataOutputQueue)
        }
        
        setupConnections(with: cameraType)
        
        captureSession.commitConfiguration()
    }
    
    private func setupCaptureVideoDevice(with cameraType: CameraType) {
        
        videoDevice = cameraType.captureDevice()
        print("selected video device: \(String(describing: videoDevice))")
        
        videoDevice.selectDepthFormat()

        captureSession.inputs.forEach { (captureInput) in
            captureSession.removeInput(captureInput)
        }
        let videoDeviceInput = try! AVCaptureDeviceInput(device: videoDevice)
        guard captureSession.canAddInput(videoDeviceInput) else { fatalError() }
        captureSession.addInput(videoDeviceInput)
    }
    
    private func setupConnections(with cameraType: CameraType) {
        videoConnection = videoDataOutput.connection(with: .video)!
        let depthConnection = depthDataOutput.connection(with: .depthData)
        switch cameraType {
        case .front:
            videoConnection.isVideoMirrored = true
            depthConnection?.isVideoMirrored = true
        default:
            break
        }
        videoConnection.videoOrientation = .portrait
        depthConnection?.videoOrientation = .portrait
    }
    
    func startCapture() {
        print("\(self.classForCoder)/" + #function)
        if captureSession.isRunning {
            print("already running")
            return
        }
        captureSession.startRunning()
    }
    
    func stopCapture() {
        print("\(self.classForCoder)/" + #function)
        if !captureSession.isRunning {
            print("already stopped")
            return
        }
        captureSession.stopRunning()
    }
    
    func resizePreview() {
        if let previewLayer = previewLayer {
            guard let superlayer = previewLayer.superlayer else {return}
            previewLayer.frame = superlayer.bounds
        }
    }
    
    func changeCamera(with cameraType: CameraType) {
        let wasRunning = captureSession.isRunning
        if wasRunning {
            captureSession.stopRunning()
        }
        captureSession.beginConfiguration()

        setupCaptureVideoDevice(with: cameraType)
        setupConnections(with: cameraType)
        
        captureSession.commitConfiguration()
        
        if wasRunning {
            captureSession.startRunning()
        }
    }

    func setDepthFilterEnabled(_ enabled: Bool) {
        depthDataOutput.isFilteringEnabled = enabled
    }
    
    
    func startVideoRecording(){
        
        print("start video Recording function in VideoCapture")
        captureSession.addOutput(fileOutput)
        captureSession.startRunning()
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileUrl = paths[0].appendingPathComponent("output.mov")
        print(fileUrl)
        try? FileManager.default.removeItem(at: fileUrl)
        fileOutput.startRecording(to: fileUrl, recordingDelegate: self)

        
    }
    func stopVideoRecording(){
        print("stop video Recording function in VideoCapture")
        self.fileOutput.stopRecording()
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        //print("capture output : finish recording to \(outputFileURL)”)
        UISaveVideoAtPathToSavedPhotosAlbum(outputFileURL.relativePath!, nil, nil, nil)
    }
    func captureOutput(captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAtURL fileURL: NSURL!, fromConnections connections: [AnyObject]!) {
        print("capture output: started recording to \(fileURL)")
    }
}

extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        print("\(self.classForCoder)/" + #function)
    }
    
    // synchronizer使ってる場合は呼ばれない
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let imageBufferHandler = imageBufferHandler, connection == videoConnection
        {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { fatalError() }

            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            imageBufferHandler(imageBuffer, timestamp, nil)
        }
    }
}

extension VideoCapture: AVCaptureDepthDataOutputDelegate {
    
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didDrop depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection, reason: AVCaptureOutput.DataDroppedReason) {
        print("\(self.classForCoder)/\(#function)")
    }
    
    // synchronizer使ってる場合は呼ばれない
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        print("\(self.classForCoder)/\(#function)")
    }
}

extension VideoCapture: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // Handle output
    }
}

extension VideoCapture: AVCaptureDataOutputSynchronizerDelegate {
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        guard let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else { return }
        guard !syncedVideoData.sampleBufferWasDropped else {
            print("dropped video:\(syncedVideoData)")
            return
        }
        let videoSampleBuffer = syncedVideoData.sampleBuffer

        let syncedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData
        var depthData = syncedDepthData?.depthData
        if let syncedDepthData = syncedDepthData, syncedDepthData.depthDataWasDropped {
            print("dropped depth:\(syncedDepthData)")
            depthData = nil
        }

        // 顔のある位置のしきい値を求める
        let syncedMetaData = synchronizedDataCollection.synchronizedData(for: metadataOutput) as? AVCaptureSynchronizedMetadataObjectData
        var face: AVMetadataObject? = nil
        if let firstFace = syncedMetaData?.metadataObjects.first {
            face = videoDataOutput.transformedMetadataObject(for: firstFace, connection: videoConnection)
        }
        guard let imagePixelBuffer = CMSampleBufferGetImageBuffer(videoSampleBuffer) else { fatalError() }

        syncedDataBufferHandler?(imagePixelBuffer, depthData, face)
    }
}

extension AVCaptureDevice {
    func set(frameRate: Double) {
        guard let range = activeFormat.videoSupportedFrameRateRanges.first,
            range.minFrameRate...range.maxFrameRate ~= frameRate
            else {
                print("Requested FPS is not supported by the device's activeFormat !")
                return
        }
        
        do { try lockForConfiguration()
            activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(frameRate))
            activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(frameRate))
            unlockForConfiguration()
        } catch {
            print("LockForConfiguration failed with error: \(error.localizedDescription)")
        }
    }
}

