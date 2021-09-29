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
import SceneKit
import simd

struct Distance {
    var distance: Float
    var timestamp: Date
}

struct Direction {
    var direction: SIMD3<Float>
    var timestamp: Date
}

extension FloatingPoint {
    // Converts degrees to radians.
    var degreesToRadians: Self { self * .pi / 180 }
    // Converts radians to degrees.
    var radiansToDegrees: Self { self * 180 / .pi }
}

class TrackerViewController: UIViewController, NISessionDelegate, ARSCNViewDelegate, ARSessionDelegate {
    
    // MARK: - `IBOutlet` instances
    @IBOutlet weak var directionDescriptionLabel: UILabel!
    @IBOutlet weak var arrowImage: UIImageView!
    @IBOutlet weak var sceneView: ARSCNView!
    
    // MARK: - ARKit variables
    var boxNode = SCNNode()
    var currentCamera = SCNMatrix4()
    
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
        
        addBox()
        
        sceneView.session.delegate = self
        
        let doorHandle = ARWWorldAnchor(column3: [0, 0, 0, 1])
        sceneView.session.add(anchor: ARAnchor(anchor: doorHandle))
        
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
        
        //sceneView.debugOptions = [ARSCNDebugOptions.showWorldOrigin]
        
//        let blur = UIBlurEffect(style: .regular)
//        let blurView = UIVisualEffectView(effect: blur)
//        blurView.frame = sceneView.bounds
//        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//        sceneView.addSubview(blurView)
    }
    
    func addBox() {
        boxNode.geometry = SCNBox(width: 0.05, height: 0.05, length: 0.05, chamferRadius: 0)
        boxNode.position = SCNVector3(0, 0, 0)
        sceneView.scene.rootNode.addChildNode(boxNode)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        currentCamera = SCNMatrix4(frame.camera.transform)
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
    
    func updateVisualization(distance: Float, direction: Float) {
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
        
        if direction != -999.0 {
            arrowImage.isHidden = false
            arrowImage.transform = arrowImage.transform.rotated(by: (CGFloat(direction) - atan2(arrowImage.transform.b, arrowImage.transform.a).radiansToDegrees).degreesToRadians)
        } else {
            arrowImage.isHidden = true
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
    
    func azimuth(from direction: simd_float3) -> Float {
        return asin(direction.x)
    }

    // Provides the elevation from the argument 3D directional.
    func elevation(from direction: simd_float3) -> Float {
        return atan2(direction.z, direction.y) + .pi / 2
    }

    
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
        
        var distance: Float = MAXFLOAT
        /*if nearbyObjects.count >= 100 {
            var dist: Float = 0.0
            for i in (nearbyObjects.count - 100)..<nearbyObjects.count {
                dist += nearbyObjects[i].distance!
            }
            distance = dist / 100.0
        } else */if nearbyObjects.count > 0 {
            distance = nearbyObjectUpdate.distance!
        } else {
            distance = -1.0
        }
        
        var direction : Float = -999.0
        if let dir = nearbyObjects.first?.direction, distance != -1.0 {
            directions.append(Direction(direction: dir, timestamp: Date()))
            sceneView.session.setWorldOrigin(relativeTransform: simd_float4x4(currentCamera))
            let yaw = -nearbyObjects.first!.direction.map(azimuth(from:))!
            let pitch = nearbyObjects.first!.direction.map(elevation(from:))!
            print(Date(), distance * 3.280839895, yaw.radiansToDegrees, pitch.radiansToDegrees)
            direction = -yaw.radiansToDegrees
            let transform = SCNMatrix4(m11: sin(yaw)*cos(pitch), m12: -sin(yaw), m13: cos(yaw)*sin(pitch), m14: 0, m21: sin(yaw)*cos(pitch), m22: cos(yaw), m23: sin(yaw)*cos(pitch), m24: 0, m31: -sin(pitch), m32: 0, m33: cos(pitch), m34: 0, m41: 0, m42: 0, m43: 0, m44: 1)
            let vector = float4(SCNVector4(0, 0, -distance, 1)) * float4x4(transform)
            boxNode.position = SCNVector3(vector.x / vector.w * distance, vector.y / vector.w * distance, vector.z / vector.w * distance)
            //boxNode.position = SCNVector3(cos(yaw) * distance, sin(yaw) * distance, -distance)
            sceneView.scene.rootNode.addChildNode(boxNode)
        } else {
            direction = -999.0
        }

        updateVisualization(distance: distance, direction: direction)
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

