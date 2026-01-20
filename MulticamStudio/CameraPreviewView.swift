//
//  CameraPreviewView.swift
//  MulticamStudio
//
//  Created by Claude on 2025/11/26.
//

import SwiftUI
import AVFoundation

// プレビューレイヤーを確実にリサイズするためのカスタムUIView
class PreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        // レイアウト変更時にアニメーションなしで即座に更新
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer = previewLayer
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // layoutSubviewsで自動的に更新される
    }
}
