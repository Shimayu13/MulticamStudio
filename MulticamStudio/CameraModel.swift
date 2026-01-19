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

// 利用可能なカメラレンズ情報
struct CameraLens: Identifiable, Equatable {
    let id: String
    let device: AVCaptureDevice
    let name: String
    let position: AVCaptureDevice.Position
    let zoomFactor: CGFloat // 基準倍率（0.5x, 1x, 2x など）

    static func == (lhs: CameraLens, rhs: CameraLens) -> Bool {
        lhs.id == rhs.id
    }
}

class CameraModel: NSObject, ObservableObject {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoDevice: AVCaptureDevice?
    private var audioInput: AVCaptureDeviceInput?
    private var lastSentAt: TimeInterval = 0
    private let sendInterval: TimeInterval = 1.0 / 12.0

    var multipeerSession: MultipeerSession?
    @Published var isRecording = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var previewLayer: AVCaptureVideoPreviewLayer?

    // カメラ切り替え用
    @Published var availableLenses: [CameraLens] = []
    @Published var currentLens: CameraLens?
    @Published var isFrontCamera = false

    // ズームプリセット（現在のカメラで利用可能な倍率）
    @Published var zoomPresets: [CGFloat] = [1.0]
    @Published var minZoom: CGFloat = 1.0
    @Published var maxZoom: CGFloat = 10.0

    override init() {
        super.init()
        discoverCameras()
        setupCamera()
        setupOrientationObserver()
    }

    // 利用可能なカメラを検出
    private func discoverCameras() {
        var lenses: [CameraLens] = []

        // 背面カメラを検出
        let backDeviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInUltraWideCamera,  // 0.5x
            .builtInWideAngleCamera,   // 1x
            .builtInTelephotoCamera    // 2x or 3x or 5x
        ]

        let backDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: backDeviceTypes,
            mediaType: .video,
            position: .back
        )

        let wideBackDevice = backDiscovery.devices.first { $0.deviceType == .builtInWideAngleCamera }
        let wideBackFOV = wideBackDevice?.activeFormat.videoFieldOfView

        for device in backDiscovery.devices {
            let (name, zoom) = cameraNameAndZoom(for: device, wideFOV: wideBackFOV)
            lenses.append(CameraLens(
                id: device.uniqueID,
                device: device,
                name: name,
                position: .back,
                zoomFactor: zoom
            ))
        }

        // 前面カメラを検出
        if let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            lenses.append(CameraLens(
                id: frontDevice.uniqueID,
                device: frontDevice,
                name: "前面",
                position: .front,
                zoomFactor: 1.0
            ))
        }

        availableLenses = lenses.sorted { $0.zoomFactor < $1.zoomFactor }
        print("📷 検出されたカメラ: \(availableLenses.map { "\($0.name) (\($0.zoomFactor)x)" })")
    }

    private func cameraNameAndZoom(for device: AVCaptureDevice, wideFOV: Float?) -> (String, CGFloat) {
        switch device.deviceType {
        case .builtInUltraWideCamera:
            return ("超広角", estimatedZoomFactor(for: device, wideFOV: wideFOV))
        case .builtInWideAngleCamera:
            return ("広角", 1.0)
        case .builtInTelephotoCamera:
            // 望遠の倍率はデバイスによって異なるためFOVから推定
            return ("望遠", estimatedZoomFactor(for: device, wideFOV: wideFOV))
        default:
            return ("カメラ", estimatedZoomFactor(for: device, wideFOV: wideFOV))
        }
    }

    private func estimatedZoomFactor(for device: AVCaptureDevice, wideFOV: Float?) -> CGFloat {
        guard let wideFOV = wideFOV else { return 1.0 }
        let deviceFOV = device.activeFormat.videoFieldOfView
        guard deviceFOV > 0 else { return 1.0 }
        let rawZoom = CGFloat(wideFOV / deviceFOV)
        return snappedZoomFactor(rawZoom)
    }

    private func snappedZoomFactor(_ value: CGFloat) -> CGFloat {
        let candidates: [CGFloat] = [0.5, 1.0, 2.0, 3.0, 5.0]
        let threshold: CGFloat = 0.2
        if let nearest = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
           abs(nearest - value) <= threshold {
            return nearest
        }
        return (value * 10).rounded() / 10
    }

    func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Audio Setup Error: \(error)")
        }

        // デフォルトで広角背面カメラを使用
        let defaultLens = availableLenses.first { $0.position == .back && $0.zoomFactor == 1.0 }
            ?? availableLenses.first { $0.position == .back }
            ?? availableLenses.first

        guard let lens = defaultLens,
              let videoInput = try? AVCaptureDeviceInput(device: lens.device) else {
            captureSession.commitConfiguration()
            return
        }

        self.videoDevice = lens.device
        self.currentLens = lens
        self.isFrontCamera = lens.position == .front
        updateZoomPresets(for: lens.device)

        // オーディオ入力
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: audioDevice) {
            self.audioInput = input
            if captureSession.canAddInput(input) { captureSession.addInput(input) }
        }

        if captureSession.canAddInput(videoInput) { captureSession.addInput(videoInput) }

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }
        if captureSession.canAddOutput(movieOutput) { captureSession.addOutput(movieOutput) }

        captureSession.commitConfiguration()

        // 接続の向きを設定
        updateVideoOrientation()

        // プレビューレイヤーを作成
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        DispatchQueue.main.async {
            self.previewLayer = preview
        }
    }

    // デバイスの向き変更を監視
    private func setupOrientationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }

    @objc private func orientationDidChange() {
        updateVideoOrientation()
    }

    // 現在のインターフェース向きを取得
    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return .portrait
        }
        return scene.interfaceOrientation
    }

    private func videoOrientation(from deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch deviceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return nil
        }
    }

    private func videoOrientation(from interfaceOrientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch interfaceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .portrait
        }
    }

    // ビデオ出力の向きを更新
    func updateVideoOrientation() {
        let deviceOrientation = UIDevice.current.orientation
        let videoOrientation = videoOrientation(from: deviceOrientation)
            ?? videoOrientation(from: currentInterfaceOrientation())

        // videoOutputの接続を更新
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = videoOrientation
            }
        }

        // movieOutputの接続も更新
        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = videoOrientation
            }
        }

        if let connection = previewLayer?.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = videoOrientation
        }

        print("📐 向き更新: \(videoOrientation.rawValue)")
    }

    // カメラを切り替え
    func switchToLens(_ lens: CameraLens) {
        guard lens != currentLens else { return }

        captureSession.beginConfiguration()

        // 既存のビデオ入力を削除
        for input in captureSession.inputs {
            if let deviceInput = input as? AVCaptureDeviceInput,
               deviceInput.device.hasMediaType(.video) {
                captureSession.removeInput(deviceInput)
            }
        }

        // 新しいカメラを追加
        guard let videoInput = try? AVCaptureDeviceInput(device: lens.device) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
            self.videoDevice = lens.device
            self.currentLens = lens
            self.isFrontCamera = lens.position == .front
            updateZoomPresets(for: lens.device)

            DispatchQueue.main.async {
                self.zoomFactor = 1.0
            }
        }

        captureSession.commitConfiguration()
        updateVideoOrientation()
        setZoom(1.0)

        print("📷 カメラ切り替え: \(lens.name)")
    }

    // 前面/背面カメラを切り替え
    func toggleCameraPosition() {
        let targetPosition: AVCaptureDevice.Position = isFrontCamera ? .back : .front
        if let lens = availableLenses.first(where: { $0.position == targetPosition && $0.zoomFactor == 1.0 })
            ?? availableLenses.first(where: { $0.position == targetPosition }) {
            switchToLens(lens)
        }
    }

    // ズームプリセットを更新
    private func updateZoomPresets(for device: AVCaptureDevice) {
        var presets: [CGFloat] = [1.0]

        let maxZoomFactor = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        self.minZoom = 1.0
        self.maxZoom = maxZoomFactor

        // 利用可能な倍率を追加
        if maxZoomFactor >= 2.0 { presets.append(2.0) }
        if maxZoomFactor >= 5.0 { presets.append(5.0) }

        DispatchQueue.main.async {
            self.zoomPresets = presets.sorted()
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
