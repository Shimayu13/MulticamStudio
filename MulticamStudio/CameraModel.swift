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
    private var videoDevice: AVCaptureDevice?
    private var lastSentAt: TimeInterval = 0
    private let sendInterval: TimeInterval = 1.0 / 12.0 // 約12fpsで送信して帯域を安定化

    var multipeerSession: MultipeerSession?
    @Published var isRecording = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    
    override init() {
        super.init()
        setupCamera()
    }
    
    
    func setupCamera() {
        captureSession.sessionPreset = .medium

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Audio Setup Error: \(error)")
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: device) else { return }

        self.videoDevice = device

        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else { return }

        if captureSession.canAddInput(videoInput) { captureSession.addInput(videoInput) }
        if captureSession.canAddInput(audioInput) { captureSession.addInput(audioInput) }

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }

        if captureSession.canAddOutput(movieOutput) { captureSession.addOutput(movieOutput) }

        // プレビューレイヤーを作成
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        DispatchQueue.main.async {
            self.previewLayer = preview
        }
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

    // ズーム機能
    func setZoom(_ factor: CGFloat) {
        guard let device = videoDevice else { return }

        do {
            try device.lockForConfiguration()
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            let zoom = max(1.0, min(factor, maxZoom))
            device.videoZoomFactor = zoom

            DispatchQueue.main.async {
                self.zoomFactor = zoom
            }
            device.unlockForConfiguration()
        } catch {
            print("Zoom error: \(error)")
        }
    }

    // タップフォーカス機能
    func focus(at point: CGPoint) {
        guard let device = videoDevice else { return }

        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }

            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()
            print("📍 Focus at: \(point)")
        } catch {
            print("Focus error: \(error)")
        }
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
            let now = CACurrentMediaTime()
            guard now - lastSentAt >= sendInterval else { return } // 送信頻度を制御
            lastSentAt = now

            if multipeerSession?.isConnected == true,
               let data = uiImage.jpegData(compressionQuality: 0.2) {
                multipeerSession?.send(data: data)
            }
        }
    }
}
