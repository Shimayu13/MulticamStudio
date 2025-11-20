//
//  MultipeerSession.swift
//  MulticamStudio
//
//  Created by Yuki Shimazu on 2025/11/20.
//

import MultipeerConnectivity
import SwiftUI
import Combine // ← これを追加！

class MultipeerSession: NSObject, ObservableObject {
    // ... 以下は変更なし ...
    private let serviceType = "multicamstudio"
    private let myPeerId: MCPeerID = {
        #if targetEnvironment(macCatalyst)
        let hostName = ProcessInfo.processInfo.hostName
        let displayName = hostName.isEmpty ? "Mac Studio" : hostName
        return MCPeerID(displayName: displayName)
        #else
        return MCPeerID(displayName: UIDevice.current.name)
        #endif
    }()
    private let serviceAdvertiser: MCNearbyServiceAdvertiser
    private let serviceBrowser: MCNearbyServiceBrowser
    private let session: MCSession
    private var invitedPeers = Set<MCPeerID>()

    @Published var receivedImage: UIImage? = nil
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isConnected: Bool = false

    override init() {
        // 接続速度を改善するため、none に設定
        self.session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        self.serviceBrowser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)

        super.init()

        self.session.delegate = self
        self.serviceAdvertiser.delegate = self
        self.serviceBrowser.delegate = self

        print("🆔 Initialized MultipeerSession with Peer ID: \(myPeerId.displayName)")
    }
    
    func startHosting() {
        print("🔵 Mac: Starting hosting")
        print("   Service Type: \(serviceType)")
        print("   Peer ID: \(myPeerId.displayName)")

        // 先にブラウジングを開始
        serviceBrowser.startBrowsingForPeers()
        // 少し遅延させてからアドバタイズを開始
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.serviceAdvertiser.startAdvertisingPeer()
        }
    }

    func startJoining() {
        print("📱 iPhone: Starting joining")
        print("   Service Type: \(serviceType)")
        print("   Peer ID: \(myPeerId.displayName)")

        // 先にアドバタイズを開始
        serviceAdvertiser.startAdvertisingPeer()
        // 少し遅延させてからブラウジングを開始
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.serviceBrowser.startBrowsingForPeers()
        }
    }
    
    func send(data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .unreliable)
        } catch {
            print("Error sending data: \(error.localizedDescription)")
        }
    }
}
// ... extension部分は変更なし ...
extension MultipeerSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            self.isConnected = !self.connectedPeers.isEmpty

            switch state {
            case .connected:
                print("🟢 Connected to: \(peerID.displayName)")
                self.invitedPeers.remove(peerID)
            case .connecting:
                print("🟡 Connecting to: \(peerID.displayName)")
            case .notConnected:
                print("🔴 Disconnected from: \(peerID.displayName)")
                self.invitedPeers.remove(peerID)
            @unknown default:
                break
            }
        }
    }
    
    // 受信時の処理を改造
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // 1. まず画像として変換を試みる
        if let image = UIImage(data: data) {
            DispatchQueue.main.async {
                self.receivedImage = image
            }
            return // 画像だったらここで終了
        }
        
        // 2. 画像じゃなければ、文字（コマンド）として解読を試みる
        if let command = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                // コマンド受信時の通知を送る（ContentViewで受け取るため）
                NotificationCenter.default.post(name: NSNotification.Name("ReceivedCommand"), object: nil, userInfo: ["command": command])
                print("📩 コマンド受信: \(command)")
            }
        }
    }
    
    // 文字（コマンド）を送る専用メソッド
        func sendCommand(_ text: String) {
            guard !session.connectedPeers.isEmpty else { return }
            if let data = text.data(using: .utf8) {
                do {
                    // コマンドは重要なので .reliable (確実に届くモード) で送る
                    try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                } catch {
                    print("Error sending command: \(error.localizedDescription)")
                }
            }
        }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📨 Received invitation from: \(peerID.displayName)")
        invitationHandler(true, self.session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❗️ Failed to start advertising: \(error.localizedDescription)")
    }
}

extension MultipeerSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("✅ Found peer: \(peerID.displayName)")

        // 既に接続済みの場合はスキップ
        guard !session.connectedPeers.contains(peerID) else {
            print("⏭️ Already connected to: \(peerID.displayName)")
            return
        }

        // 招待済みでも一定時間経過後は再試行
        if !invitedPeers.contains(peerID) {
            invitedPeers.insert(peerID)
            print("📤 Inviting peer: \(peerID.displayName)")
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("❌ Lost peer: \(peerID.displayName)")
        invitedPeers.remove(peerID)
    }
}
