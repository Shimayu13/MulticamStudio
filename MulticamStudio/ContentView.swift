//
//  ContentView.swift
//  MulticamStudio
//
//  Created by Yuki Shimazu on 2025/11/20.
//

import AVFoundation
import MultipeerConnectivity
import SwiftUI

struct ContentView: View {
    @StateObject var connection = MultipeerSession()
    @StateObject var camera = CameraModel()
    
    // 録画状態管理（Mac側用）
    @State private var isRemoteRecording = false

    private var hasFrontCamera: Bool {
        camera.availableLenses.contains { $0.position == .front }
    }

    private var hasBackCamera: Bool {
        camera.availableLenses.contains { $0.position == .back }
    }

    private var visibleLenses: [CameraLens] {
        let position = camera.isFrontCamera ? AVCaptureDevice.Position.front : .back
        return camera.availableLenses.filter { $0.position == position }.sorted { $0.zoomFactor < $1.zoomFactor }
    }
    
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240), spacing: 16)]
    }
    
    var body: some View {
        VStack {
            #if targetEnvironment(macCatalyst)
            // ============================
            //  Mac側の画面 (モニター & コントローラー)
            // ============================
            VStack(spacing: 20) {
                Text("📡 Studio Monitor")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // 映像表示エリア（複数ピア対応）
                ZStack(alignment: .topLeading) {
                    Group {
                        if connection.peerFrames.isEmpty {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black)
                                .frame(height: 500)
                                .overlay(Text("No Signal").foregroundColor(.white))
                        } else {
                            ScrollView {
                                LazyVGrid(columns: gridColumns, spacing: 16) {
                                    ForEach(connection.peerFrames) { frame in
                                        // 個別のビューに分離して独立更新を実現
                                        PeerFrameItemView(frame: frame)
                                    }
                                }
                            }
                        }
                    }
                    
                    // 録画中マーク
                    if isRemoteRecording {
                        HStack {
                            Circle().fill(Color.red).frame(width: 15, height: 15)
                            Text("REC").foregroundColor(.red).fontWeight(.bold)
                            Spacer()
                        }
                        .padding()
                    }
                }
                
                HStack {
                    Image(systemName: connection.isConnected ? "wifi" : "wifi.slash")
                    Text(connection.isConnected ? "接続済み: \(connection.connectedPeers.count)台" : "接続待ち...")
                        .font(.subheadline)
                    Spacer()
                }
                .padding()
                .background(Material.thinMaterial)
                .cornerRadius(12)
                
                // 操作ボタンエリア
                HStack(spacing: 40) {
                    Button(action: {
                        if isRemoteRecording {
                            connection.sendCommand("STOP_REC")
                            isRemoteRecording = false
                        } else {
                            connection.sendCommand("START_REC")
                            isRemoteRecording = true
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(isRemoteRecording ? Color.gray : Color.red)
                                .frame(width: 80, height: 80)
                            
                            if isRemoteRecording {
                                Rectangle().fill(Color.white).frame(width: 30, height: 30)
                            } else {
                                Circle().fill(Color.white).frame(width: 70, height: 70)
                                Circle().fill(Color.red).frame(width: 60, height: 60)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    VStack(alignment: .leading) {
                        Text("Remote Control")
                            .font(.headline)
                        Text(isRemoteRecording ? "Recording..." : "Ready")
                            .foregroundColor(isRemoteRecording ? .red : .gray)
                    }
                }
                .padding()
                .background(Material.thinMaterial)
                .cornerRadius(16)
            }
            .padding()
            .onAppear { connection.startHosting() }
            
            #else
            // ============================
            //  iPhone/iPad側の画面 (カメラ)
            // ============================
            GeometryReader { proxy in
                let rotation = camera.contentRotationDegrees
                let baseSize = proxy.size
                let isQuarterTurn = abs(Int(rotation)) == 90
                let rotatedSize = isQuarterTurn ? CGSize(width: baseSize.height, height: baseSize.width) : baseSize
                let scale = min(1, min(baseSize.width / rotatedSize.width, baseSize.height / rotatedSize.height))
                let scaledSize = CGSize(width: rotatedSize.width * scale, height: rotatedSize.height * scale)
                let sideShift = max(0, (baseSize.width - scaledSize.width) / 2)
                let rotationInt = Int(rotation.rounded())
                let offsetX: CGFloat = rotationInt == 90 ? sideShift : (rotationInt == -90 ? -sideShift : 0)

                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)

                    // カメラプレビュー
                    if let previewLayer = camera.previewLayer {
                        CameraPreviewView(previewLayer: previewLayer)
                            .edgesIgnoringSafeArea(.all)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / camera.zoomFactor
                                        let newZoom = camera.zoomFactor * delta
                                        camera.setZoom(newZoom)
                                    }
                            )
                            .onTapGesture { location in
                                let screenSize = UIScreen.main.bounds.size
                                let point = CGPoint(
                                    x: location.x / screenSize.width,
                                    y: location.y / screenSize.height
                                )
                                camera.focus(at: point)
                            }
                    }
                }
                .overlay(
                    VStack {
                        // 上部: ズーム・録画インジケーター
                        HStack {
                            Text(String(format: "%.1fx", camera.zoomFactor))
                                .font(.caption)
                                .padding(8)
                                .background(Material.ultraThin)
                                .cornerRadius(8)
                                .padding()

                            Spacer()

                            if camera.isRecording {
                                HStack {
                                    Circle().fill(Color.red).frame(width: 12, height: 12)
                                    Text("REC")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                }
                                .padding(8)
                                .background(Material.ultraThin)
                                .cornerRadius(8)
                                .padding()
                            }
                        }

                        Spacer()

                        // 下部: カメラコントロール
                        VStack(spacing: 12) {
                            // ズームスライダー
                            HStack(spacing: 12) {
                                Text(zoomText(camera.minZoom))
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                Slider(
                                    value: Binding(
                                        get: { camera.zoomFactor },
                                        set: { camera.setZoom($0) }
                                    ),
                                    in: camera.minZoom...camera.maxZoom
                                )
                                .accentColor(.yellow)
                                Text(zoomText(camera.maxZoom))
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Material.ultraThin)
                            .cornerRadius(20)
                            .padding(.horizontal, 16)

                            // レンズ切り替えボタン（前面カメラ含む全てのレンズ）
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    if hasFrontCamera && hasBackCamera {
                                        Button(action: {
                                            camera.toggleCameraPosition()
                                        }) {
                                            VStack(spacing: 4) {
                                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                                    .font(.system(size: 16, weight: .bold))
                                                Text(camera.isFrontCamera ? "背面" : "前面")
                                                    .font(.system(size: 10))
                                            }
                                            .foregroundColor(.white)
                                            .frame(width: 56, height: 56)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                        }
                                    }

                                    ForEach(visibleLenses) { lens in
                                        Button(action: {
                                            camera.switchToLens(lens)
                                        }) {
                                            VStack(spacing: 4) {
                                                Text(lensLabel(lens))
                                                    .font(.system(size: 14, weight: .bold))
                                                Text(lens.name)
                                                    .font(.system(size: 10))
                                            }
                                            .foregroundColor(camera.currentLens == lens ? .black : .white)
                                            .frame(width: 56, height: 56)
                                            .background(camera.currentLens == lens ? Color.yellow : Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }

                            // 接続状態
                            HStack {
                                Circle()
                                    .fill(connection.isConnected ? Color.green : Color.yellow)
                                    .frame(width: 8, height: 8)
                                Text(connection.isConnected ? "Connected" : "Connecting...")
                                    .font(.caption)
                            }
                            .padding(8)
                            .background(Material.ultraThin)
                            .cornerRadius(8)
                        }
                        .padding(.bottom, 40)
                    }
                    .frame(width: baseSize.width, height: baseSize.height, alignment: .bottom)
                    .rotationEffect(.degrees(rotation))
                    .scaleEffect(scale)
                    .offset(x: offsetX, y: 0)
                    .animation(.easeInOut(duration: 0.15), value: rotation)
                )
            }
            .ignoresSafeArea()
            .onAppear {
                camera.multipeerSession = connection
                camera.start()
                connection.startJoining()

                NotificationCenter.default.addObserver(forName: NSNotification.Name("ReceivedCommand"), object: nil, queue: .main) { notification in
                    if let command = notification.userInfo?["command"] as? String {
                        if command == "START_REC" {
                            camera.startRecording()
                        } else if command == "STOP_REC" {
                            camera.stopRecording()
                        }
                    }
                }
            }
            #endif
        }
    }
}

// レンズのラベルを生成
private func lensLabel(_ lens: CameraLens) -> String {
    if lens.zoomFactor < 1.0 || lens.zoomFactor.rounded() != lens.zoomFactor {
        return String(format: "%.1fx", lens.zoomFactor)
    } else {
        return "\(Int(lens.zoomFactor))x"
    }
}

private func zoomText(_ value: CGFloat) -> String {
    if value < 1.0 || value.rounded() != value {
        return String(format: "%.1fx", value)
    }
    return "\(Int(value))x"
}

// 個別のピアフレームを表示するビュー
// @ObservedObjectで監視することで、このピアの画像更新時だけ再描画される
struct PeerFrameItemView: View {
    @ObservedObject var frame: PeerFrame

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: frame.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 400)
                .cornerRadius(12)

            HStack {
                Text(frame.name)
                    .font(.caption)
                    .padding(6)
                    .background(Material.ultraThin)
                    .cornerRadius(6)
                Spacer()
                Text("LIVE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(6)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
            .padding(8)
        }
    }
}

#Preview {
    ContentView()
}
