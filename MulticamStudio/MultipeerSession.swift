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
    private let serviceType = "studio"
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
        self.session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .optional)
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        self.serviceBrowser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)

        super.init()

        self.session.delegate = self
        self.serviceAdvertiser.delegate = self
        self.serviceBrowser.delegate = self

        print("🆔 Initialized MultipeerSession with Peer ID: \(myPeerId.displayName)")
    }
    
    func startHosting() {
        print("🔵 Mac: Starting hosting - browsing for peers and advertising")
        serviceBrowser.startBrowsingForPeers()
        serviceAdvertiser.startAdvertisingPeer()
    }

    func startJoining() {
        print("📱 iPhone: Starting joining - advertising and browsing")
        serviceAdvertiser.startAdvertisingPeer()
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
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let image = UIImage(data: data) {
            DispatchQueue.main.async {
                self.receivedImage = image
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

        // 既に接続済みまたは招待済みの場合はスキップ
        guard !session.connectedPeers.contains(peerID) && !invitedPeers.contains(peerID) else {
            print("⏭️ Skipping invitation - already connected or invited: \(peerID.displayName)")
            return
        }

        invitedPeers.insert(peerID)
        print("📤 Inviting peer: \(peerID.displayName)")
        browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 30)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("❌ Lost peer: \(peerID.displayName)")
        invitedPeers.remove(peerID)
    }
}
