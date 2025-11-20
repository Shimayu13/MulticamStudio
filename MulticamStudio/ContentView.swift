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
                
                // 映像表示エリア
                ZStack {
                    if let receivedImage = connection.receivedImage {
                        Image(uiImage: receivedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 500)
                            .cornerRadius(12)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black)
                            .frame(height: 500)
                            .overlay(Text("No Signal").foregroundColor(.white))
                    }
                    
                    // 録画中マーク
                    if isRemoteRecording {
                        VStack {
                            HStack {
                                Circle().fill(Color.red).frame(width: 15, height: 15)
                                Text("REC").foregroundColor(.red).fontWeight(.bold)
                                Spacer()
                            }
                            .padding()
                            Spacer()
                        }
                    }
                }
                
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
                
                VStack {
                    Spacer()
                    if camera.isRecording {
                        Text("🔴 REC")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.red)
                            .padding()
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                }
                
                VStack {
                    Spacer()
                    Text(connection.isConnected ? "Connected" : "Connecting...")
                        .foregroundColor(connection.isConnected ? .green : .yellow)
                        .padding(.bottom, 40)
                }
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

#Preview {
    ContentView()
}
