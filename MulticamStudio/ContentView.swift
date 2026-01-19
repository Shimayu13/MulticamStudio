//
//  ContentView.swift
//  MulticamStudio
//
//  Created by Yuki Shimazu on 2025/11/20.
//

import MultipeerConnectivity
import SwiftUI

struct ContentView: View {
    @StateObject var connection = MultipeerSession()
    @StateObject var camera = CameraModel()
    
    // 録画状態管理（Mac側用）
    @State private var isRemoteRecording = false
    
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
                            // タップ位置を0-1の範囲に正規化
                            let screenSize = UIScreen.main.bounds.size
                            let point = CGPoint(
                                x: location.x / screenSize.width,
                                y: location.y / screenSize.height
                            )
                            camera.focus(at: point)
                        }
                }

                // オーバーレイUI
                VStack {
                    HStack {
                        // ズームインジケーター
                        Text(String(format: "%.1fx", camera.zoomFactor))
                            .font(.caption)
                            .padding(8)
                            .background(Material.ultraThin)
                            .cornerRadius(8)
                            .padding()

                        Spacer()

                        // 録画インジケーター
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
                    .padding(.bottom, 40)
                }

                // タップフォーカスのビジュアルフィードバック（オプション）
                // 必要に応じて追加可能
            }
            .onAppear {
                camera.multipeerSession = connection
                camera.start()
                connection.startJoining()

                // コマンド受信の監視
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
