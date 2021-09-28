//
//  TrackerViewController.swift
//  AVA OSM
//
//  Created by Matt Maring on 7/20/21.
//

import UIKit
import NearbyInteraction
import MultipeerConnectivity
import ARKit

struct Distance {
    var distance: Float
    var timestamp: Date
}

struct Direction {
    var direction: Float
    var timestamp: Date
}

class TrackerViewController: UIViewController, NISessionDelegate, ARSCNViewDelegate, ARSessionDelegate {
    
    // MARK: - `IBOutlet` instances
    @IBOutlet weak var directionDescriptionLabel: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!
    
    // MARK: - Class variables
    var session: NISession?
    var sharedTokenWithPeer = false
    var mpcSession: MPCSession?
    var connectedPeer: MCPeerID?
    var peerDiscoveryToken: NIDiscoveryToken?
    var peerDisplayName: String?
    
    // MARK: - Data storage
    var distances: [Distance] = []
    var directions: [Direction] = []
    
    // MARK: - Text formmatting
    let attributes1 = [NSAttributedString.Key.font : UIFont.systemFont(ofSize: 50, weight: UIFont.Weight.bold), NSAttributedString.Key.foregroundColor : UIColor.label] //primary
    let attributes2 = [NSAttributedString.Key.font : UIFont.systemFont(ofSize: 50, weight: UIFont.Weight.semibold), NSAttributedString.Key.foregroundColor : UIColor.secondaryLabel] //secondary
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.session.delegate = self
        
        // Initialize visualizations
        let attributedString1 = NSMutableAttributedString(string: "\n-.--", attributes: attributes1)
        let attributedString2 = NSMutableAttributedString(string: " ft", attributes: attributes2)
        
        attributedString1.append(attributedString2)
        
        directionDescriptionLabel.attributedText = attributedString1
        
        initiateSession()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)
        
        let blur = UIBlurEffect(style: .regular)
        let blurView = UIVisualEffectView(effect: blur)
        blurView.frame = sceneView.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.addSubview(blurView)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        print(frame.camera.transform)
    }
    
    func initiateSession() {
        session = NISession()
        session?.delegate = self
        sharedTokenWithPeer = false
        
        if connectedPeer != nil && mpcSession != nil {
            if let myToken = session?.discoveryToken {
                if !sharedTokenWithPeer {
                    shareDiscoveryToken(token: myToken)
                }
                guard let peerToken = peerDiscoveryToken else {
                    return
                }
                let config = NINearbyPeerConfiguration(peerToken: peerToken)
                session?.run(config)
            } else {
                fatalError("Unable to get self discovery token, is this session invalidated?")
            }
        } else {
            startupMPC()
        }
    }
    
    // MARK: - Discovery token sharing and receiving using MPC

    func startupMPC() {
        if mpcSession == nil {
            mpcSession = MPCSession(service: "avaosm", identity: "cvg.AVA-OSM", maxPeers: 1)
            mpcSession?.peerConnectedHandler = connectedToPeer
            mpcSession?.peerDataHandler = dataReceivedHandler
            mpcSession?.peerDisconnectedHandler = disconnectedFromPeer
        }
        mpcSession?.invalidate()
        mpcSession?.start()
    }
    
    func shareDiscoveryToken(token: NIDiscoveryToken) {
        guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            fatalError("Unexpectedly failed to encode discovery token.")
        }
        mpcSession?.sendDataToAllPeers(data: encodedData)
        sharedTokenWithPeer = true
    }
    
    func peerDidShareDiscoveryToken(peer: MCPeerID, token: NIDiscoveryToken) {
        if connectedPeer != peer {
            fatalError("Received token from unexpected peer.")
        }
        // Create a configuration.
        peerDiscoveryToken = token

        let config = NINearbyPeerConfiguration(peerToken: token)

        // Run the session.
        session?.run(config)
    }
    
    func connectedToPeer(peer: MCPeerID) {
        guard let myToken = session?.discoveryToken else {
            fatalError("Unexpectedly failed to initialize nearby interaction session.")
        }

        if connectedPeer != nil {
            fatalError("Already connected to a peer.")
        }

        if !sharedTokenWithPeer {
            shareDiscoveryToken(token: myToken)
        }

        connectedPeer = peer
        peerDisplayName = peer.displayName
    }

    func disconnectedFromPeer(peer: MCPeerID) {
        if connectedPeer == peer {
            connectedPeer = nil
            sharedTokenWithPeer = false
        }
    }

    func dataReceivedHandler(data: Data, peer: MCPeerID) {
        guard let discoveryToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
            fatalError("Unexpectedly failed to decode discovery token.")
        }
        peerDidShareDiscoveryToken(peer: peer, token: discoveryToken)
    }
    
    // MARK: - Visualizations
    
    func updateVisualization(distance: Float) {
        if distance != -1.0 {
            let distanceFill = String(format: "%0.1f", distance * 3.280839895)
            
            let attributedString1 = NSMutableAttributedString(string: "\(distanceFill) ", attributes: attributes1)
            let attributedString2 = NSMutableAttributedString(string: "ft\nstraight", attributes: attributes2)
            let attributedString3 = NSMutableAttributedString(string: " ahead", attributes: attributes1)
            
            attributedString1.append(attributedString2)
            attributedString1.append(attributedString3)
            
            directionDescriptionLabel.attributedText = attributedString1
        } else {
            let attributedString1 = NSMutableAttributedString(string: "\n-.--", attributes: attributes1)
            let attributedString2 = NSMutableAttributedString(string: " ft", attributes: attributes2)
            
            attributedString1.append(attributedString2)
            
            directionDescriptionLabel.attributedText = attributedString1
        }
        
//        if peer.direction != nil {
//            detailDirectionXLabel.text = String(format: "%0.2f", peer.direction!.x)
//            detailDirectionYLabel.text = String(format: "%0.2f", peer.direction!.y)
//            detailDirectionZLabel.text = String(format: "%0.2f", peer.direction!.z)
//        } else {
//            detailDirectionXLabel.text = "-.--"
//            detailDirectionYLabel.text = "-.--"
//            detailDirectionZLabel.text = "-.--"
//        }
    }
    
    // MARK: - `NISessionDelegate`
    
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let peerToken = peerDiscoveryToken else {
            fatalError("don't have peer token")
        }

        let peerObj = nearbyObjects.first { (obj) -> Bool in
            return obj.discoveryToken == peerToken
        }

        guard let nearbyObjectUpdate = peerObj else {
            return
        }
        
        if let dist = nearbyObjects.first?.distance {
            //print(dist)
        }
        
        var distance: Float = MAXFLOAT
        if nearbyObjects.count > 10 {
            for i in 0..<100 {
                if let dist = nearbyObjects[i].distance, dist < distance {
                    distance = dist
                }
            }
            if distance == MAXFLOAT {
                distance = -1.0
            }
        } else if nearbyObjects.count > 0 {
            distance = nearbyObjectUpdate.distance!
        } else {
            distance = -1.0
        }

        updateVisualization(distance: distance)
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let peerToken = peerDiscoveryToken else {
            fatalError("don't have peer token")
        }
        
        let peerObj = nearbyObjects.first { (obj) -> Bool in
            return obj.discoveryToken == peerToken
        }

        if peerObj == nil {
            return
        }

        switch reason {
        case .peerEnded:
            peerDiscoveryToken = nil
            session.invalidate()
            initiateSession()
        case .timeout:
            if let config = session.configuration {
                session.run(config)
            }
        default:
            fatalError("Unknown and unhandled NINearbyObject.RemovalReason")
        }
    }

//    func sessionWasSuspended(_ session: NISession) {
//        print("Session suspended")
//    }

    func sessionSuspensionEnded(_ session: NISession) {
        if let config = self.session?.configuration {
            session.run(config)
        } else {
            initiateSession()
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        if case NIError.userDidNotAllow = error {
            if #available(iOS 15.0, *) {
                let accessAlert = UIAlertController(title: "Access Required", message: "AVA OSM requires access to Nearby Interactions to provide accurate navigation to the vehicle.", preferredStyle: .alert)
                accessAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                accessAlert.addAction(UIAlertAction(title: "Go to Settings", style: .default, handler: {_ in
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
                    }
                }))
                present(accessAlert, animated: true, completion: nil)
            } else {
                let accessAlert = UIAlertController(title: "Access Required", message: "Nearby Interactions access required. Restart AVA OSM to allow access.", preferredStyle: .alert)
                accessAlert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                present(accessAlert, animated: true, completion: nil)
            }
            return
        }
        initiateSession()
    }
}

