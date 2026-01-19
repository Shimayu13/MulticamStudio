//
//  MultipeerSession.swift
//  MulticamStudio
//
//  Created by Yuki Shimazu on 2025/11/20.
//

import MultipeerConnectivity
import SwiftUI
import Combine

// 各ピアのフレームを独立して管理するクラス
// ObservableObjectにすることで、個別のピアの更新が他のピアに影響しない
class PeerFrame: ObservableObject, Identifiable {
    let id: String
    let name: String
    @Published var image: UIImage

    init(id: String, name: String, image: UIImage) {
        self.id = id
        self.name = name
        self.image = image
    }
}

class MultipeerSession: NSObject, ObservableObject {
    // サービス名は15文字以内・小文字英数字・ハイフンのみ
    private let serviceType = "mstdcam" // 7文字の安全なサービス名
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

    // 辞書で各ピアのフレームを管理（MCPeerIDをキーにして確実に区別）
    private var peerFrameDict: [MCPeerID: PeerFrame] = [:]
    // 配列は新規ピア追加時のみ更新（ForEach用）
    @Published var peerFrames: [PeerFrame] = []
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
        assert(serviceType.count <= 15, "serviceType must be <= 15 chars")
    }
    
    // Mac側: 広告のみ（ホスト）に徹する
    func startHosting() {
        print("🔵 Mac: Starting hosting (advertise only)")
        print("   Service Type: \(serviceType)")
        print("   Peer ID: \(myPeerId.displayName)")

        serviceBrowser.stopBrowsingForPeers()
        serviceAdvertiser.startAdvertisingPeer()
    }

    // iPhone/iPad側: ブラウズのみ（クライアント）に徹する
    func startJoining() {
        print("📱 iPhone: Starting joining (browse only)")
        print("   Service Type: \(serviceType)")
        print("   Peer ID: \(myPeerId.displayName)")

        serviceAdvertiser.stopAdvertisingPeer()
        invitedPeers.removeAll()
        serviceBrowser.startBrowsingForPeers()
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
                print("🟢 Connected to: \(peerID.displayName) (hash: \(peerID.hash))")
                print("   接続中のピア数: \(session.connectedPeers.count)")
                self.invitedPeers.remove(peerID)
            case .connecting:
                print("🟡 Connecting to: \(peerID.displayName)")
            case .notConnected:
                print("🔴 Disconnected from: \(peerID.displayName)")
                self.invitedPeers.remove(peerID)
                // 辞書と配列の両方から削除（MCPeerIDのハッシュ値でIDを生成）
                let frameId = "\(peerID.displayName)_\(peerID.hash)"
                self.peerFrameDict.removeValue(forKey: peerID)
                self.peerFrames.removeAll { $0.id == frameId }
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
                self.upsertFrame(for: peerID, image: image)
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

// MARK: - Helpers
private extension MultipeerSession {
    func upsertFrame(for peer: MCPeerID, image: UIImage) {
        // MCPeerIDをキーにして確実にピアを区別
        // 同じdisplayNameでも異なるMCPeerIDオブジェクトは別々に扱われる
        if let existingFrame = peerFrameDict[peer] {
            // 既存のピアの場合: PeerFrame内部で画像を更新（配列は変更しない）
            existingFrame.image = image
        } else {
            // 新しいピアの場合: 一意のIDを生成して辞書と配列に追加
            let uniqueId = "\(peer.displayName)_\(peer.hash)"
            let frame = PeerFrame(id: uniqueId, name: peer.displayName, image: image)
            peerFrameDict[peer] = frame
            peerFrames.append(frame)
            print("📺 新しいカメラを追加: \(peer.displayName) (ID: \(uniqueId))")
            print("   現在のカメラ数: \(peerFrames.count)")
        }
    }
}
