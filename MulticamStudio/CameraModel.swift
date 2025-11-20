//
//  CameraModel.swift
//  MulticamStudio
//
//  Created by Yuki Shimazu on 2025/11/20.
//

import AVFoundation
import UIKit
import Combine
import Photos

class CameraModel: NSObject, ObservableObject {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    
    var multipeerSession: MultipeerSession?
    @Published var isRecording = false
    
    override init() {
        super.init()
        setupCamera()
    }
    
    func setupCamera() {
        captureSession.sessionPreset = .high
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Audio Setup Error: \(error)")
        }

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else { return }

        if captureSession.canAddInput(videoInput) { captureSession.addInput(videoInput) }
        if captureSession.canAddInput(audioInput) { captureSession.addInput(audioInput) }
        
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }
        
        if captureSession.canAddOutput(movieOutput) { captureSession.addOutput(movieOutput) }
    }
    
    func start() {
        DispatchQueue.global(qos: .background).async {
            if !self.captureSession.isRunning { self.captureSession.startRunning() }
        }
    }
    
    func stop() {
        captureSession.stopRunning()
    }
    
    func startRecording() {
        guard !movieOutput.isRecording else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        DispatchQueue.main.async { self.isRecording = true }
        print("🎥 録画開始")
    }
    
    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        DispatchQueue.main.async { self.isRecording = false }
        print("⏹️ 録画停止")
    }
}

extension CameraModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error recording: \(error)")
            return
        }
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
                }) { success, error in
                    if success { print("💾 保存完了！") }
                }
            }
        }
    }
}

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            if let data = uiImage.jpegData(compressionQuality: 0.2) {
                multipeerSession?.send(data: data)
            }
        }
    }
}
