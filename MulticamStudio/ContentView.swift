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
    
    var body: some View {
        VStack {
            #if targetEnvironment(macCatalyst)
            // ============================
            //  Mac側の画面 (モニター)
            // ============================
            VStack(spacing: 20) {
                Text("📡 Studio Monitor")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if let receivedImage = connection.receivedImage {
                    Image(uiImage: receivedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 500)
                        .cornerRadius(12)
                        .overlay(
                            VStack {
                                HStack {
                                    Spacer()
                                    Text("LIVE")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .padding(6)
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                }
                                Spacer()
                            }
                            .padding()
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 400)
                        
                        VStack {
                            Image(systemName: "video.slash")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("カメラ待機中...")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                HStack {
                    Image(systemName: connection.isConnected ? "wifi" : "wifi.slash")
                    Text(connection.isConnected ? "接続済み: \(connection.connectedPeers.count)台" : "接続待ち...")
                }
                .padding()
                .background(Material.thinMaterial)
                .cornerRadius(10)
            }
            .padding()
            .onAppear {
                connection.startHosting() // Macはホストとして起動
            }
            
            #else
            // ============================
            //  iPhone/iPad側の画面 (カメラ)
            // ============================
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    Spacer()
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .padding()
                    
                    Text("Camera Mode Active")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("レンズを向けてください")
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    HStack {
                        Circle()
                            .fill(connection.isConnected ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(connection.isConnected ? "Monitor Connected" : "Searching Monitor...")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                    .padding(.bottom, 40)
                }
            }
            .onAppear {
                camera.multipeerSession = connection
                camera.start()      // カメラ起動
                connection.startJoining() // 通信参加
            }
            #endif
        }
    }
}

#Preview {
    ContentView()
}
