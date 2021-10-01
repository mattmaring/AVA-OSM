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
        arrowImage.isHidden = true
        
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
        
        sceneView.debugOptions = [ARSCNDebugOptions.showWorldOrigin]
        
//        let blur = UIBlurEffect(style: .regular)
//        let blurView = UIVisualEffectView(effect: blur)
//        blurView.frame = sceneView.bounds
//        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//        sceneView.addSubview(blurView)
    }
    
    func addBox() {
        boxNode.geometry = SCNBox(width: 0.05, height: 0.05, length: 0.05, chamferRadius: 0)
        boxNode.position = SCNVector3(0, 0, 0)
        boxNode.geometry?.firstMaterial?.diffuse.contents = UIColor.white
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
    
    func directionNaturalLanguage(degrees: Float) -> (String, String) {
        if degrees > -165.0 && degrees < -135.0 {
            return ("back", "left")
        } else if degrees >= -135.0 && degrees <= -45.0 {
            return ("to your", "left")
        } else if degrees > -45.0 && degrees < -15.0 {
            return ("slightly", "left")
        } else if degrees >= -15.0 && degrees <= 15.0 {
            return ("straight", "ahead")
        } else if degrees > 15.0 && degrees < 45.0 {
            return ("slightly", "right")
        } else if degrees >= 45.0 && degrees <= 135.0 {
            return ("to your", "right")
        } else if degrees > 135.0 && degrees < 165.0 {
            return ("back", "right")
        } else {
            return ("straight", "behind")
        }
    }
    
    func updateVisualization(distance: Float, direction: Float) {
        if distance != -1.0 {
            let distanceFill = String(format: "%0.1f", distance * 3.280839895)
            if direction != -999.0 {
                let desc = directionNaturalLanguage(degrees: direction)
                let attributedString1 = NSMutableAttributedString(string: "\(distanceFill) ", attributes: attributes1)
                let attributedString2 = NSMutableAttributedString(string: "ft\n\(desc.0)", attributes: attributes2)
                let attributedString3 = NSMutableAttributedString(string: " \(desc.1)", attributes: attributes1)
                
                attributedString1.append(attributedString2)
                attributedString1.append(attributedString3)
                
                directionDescriptionLabel.attributedText = attributedString1
            } else {
                let attributedString1 = NSMutableAttributedString(string: "\(distanceFill) ", attributes: attributes1)
                let attributedString2 = NSMutableAttributedString(string: "ft", attributes: attributes2)
                
                attributedString1.append(attributedString2)
                
                directionDescriptionLabel.attributedText = attributedString1
            }
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
        if nearbyObjects.count > 0 {
            distance = nearbyObjectUpdate.distance!
//            // Initialization
//            let process_uncertainty: Float = 0.15
//            let predicted_estimate: Float = 10.0 // 10m or 29.5276ft, change this value later based on GPS/etc
//            let standard_deviation: Float = 0.5
//            let error_variance = standard_deviation * standard_deviation //0.25
//
//            // Prediction
//            let current_estimate: Float = 10.0 // 10m or 29.5276ft, change this value later based on GPS/etc
//            let variance = error_variance + process_uncertainty //0.40
//
//            // First Iteration
//            let measurement_value = nearbyObjectUpdate.distance!
//            let measurement_uncertainty = error_variance
//            let kalman_gain = variance / (variance + measurement_uncertainty) // 0.61538
//            let distance = current_estimate + kalman_gain * (measurement_value - current_estimate)
//        } else if nearbyObjects.count > 1 {
//            let count = nearbyObjects.count
//            let dist = nearbyObjectUpdate.distance!
//            let prev = nearbyObjects[count - 2].distance!
//            let variance = (dist - prev) / prev
//            distance = prev + variance * (dist - prev)
        } else {
            distance = -1.0
        }
        
        var direction : Float
        if let dir = nearbyObjects.first?.direction, distance != -1.0 {
            directions.append(Direction(direction: dir, timestamp: Date()))
            sceneView.session.setWorldOrigin(relativeTransform: simd_float4x4(currentCamera))
            let yaw = nearbyObjects.first!.direction.map(azimuth(from:))!
            let pitch = -nearbyObjects.first!.direction.map(elevation(from:))!
            print(distance * 3.280839895, yaw.radiansToDegrees, pitch.radiansToDegrees)
            direction = yaw.radiansToDegrees
            boxNode.position = SCNVector3(sin(pitch) * distance, sin(yaw) * distance, -distance)
            sceneView.scene.rootNode.addChildNode(boxNode)
        } else {
            let transform = sceneView.session.currentFrame?.camera.transform
            
            print(boxNode.position, transform?.columns.3)
            direction = -999.0 //boxNode.eulerAngles
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

