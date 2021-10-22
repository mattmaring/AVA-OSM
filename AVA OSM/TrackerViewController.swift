//
//  TrackerViewController.swift
//  AVA OSM
//
//  Created by Matt Maring on 7/20/21.
//

import UIKit
import NearbyInteraction
import MultipeerConnectivity
import CoreLocation
import ARKit
import SceneKit
import simd
import MapKit

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

class TrackerViewController: UIViewController, NISessionDelegate, ARSCNViewDelegate, ARSessionDelegate, CLLocationManagerDelegate {
    
    // MARK: - `IBOutlet` instances
    @IBOutlet weak var directionDescriptionLabel: UILabel!
    @IBOutlet weak var arrowImage: UIImageView!
    @IBOutlet weak var circleImage: UIImageView!
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
    var locationManager = CLLocationManager()
    var circleImageSize = CGSize()
    
    // MARK: - Data storage
    var distances: [Distance] = []
    var directions: [Direction] = []
    
    // MARK: - Timer
    var hapticFeedbackTimer: Timer?
    var timeInterval = 0.01
    var timerCounter: Float = 0.0
    
    // MARK: - Default values
    let DIST_MAX: Float = 999999.0
    let DIR_MAX: Float = 999.0
    let CLOSE_RANGE: Float = 0.333
    
    // MARK: - Car location
    let destination = CLLocation(latitude: 44.564825926200015, longitude: -69.65909124016235) // Example location of vehicle in Davis Parking Lot
    var car_distance: Float = 999999.0
    var car_direction: Float = 999.0
    
    // MARK: - Text formmatting
    let attributes1 = [NSAttributedString.Key.font : UIFont.systemFont(ofSize: 50, weight: UIFont.Weight.bold), NSAttributedString.Key.foregroundColor : UIColor.label] //primary
    let attributes2 = [NSAttributedString.Key.font : UIFont.systemFont(ofSize: 50, weight: UIFont.Weight.semibold), NSAttributedString.Key.foregroundColor : UIColor.secondaryLabel] //secondary
    
    // MARK: - Logging
    let dateFormat = DateFormatter()
    var coreLocationOutput = "timestamp, distance (ft), direction (deg), longitude, latitude, altitude, course, speed, horizontalAccuracy, verticalAccuracy, horizontalAccuracy, speedAccuracy\n"
    var coreLocationPath = URL(string: "")
    var nearbyInteractionOutput = "timestamp, distance (ft), yaw (deg), pitch (deg)\n"
    var nearbyInteractionPath = URL(string: "")
    var renderingOutput = "timestamp, distance (ft), direction (deg)\n"
    var renderingPath = URL(string: "")
    var visualizationOutput = ""
    var visualizationPath = URL(string: "")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        dateFormat.dateFormat = "y-MM-dd H:m:ss.SSSS"
        let dateString = dateFormat.string(from: Date())
        coreLocationPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("\(dateString) CoreLocation.csv")
        nearbyInteractionPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("\(dateString) NearbyInteraction.csv")
        renderingPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("\(dateString) Rendering.csv")
        visualizationPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("\(dateString) Visualization.csv")
        
        circleImageSize = circleImage.bounds.size
        hapticFeedbackTimer?.invalidate()
        
        // Request permission to access location
        locationManager.requestAlwaysAuthorization()
        if (CLLocationManager.locationServicesEnabled()) {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            //locationManager.headingFilter = 5.0
            locationManager.distanceFilter = Double(CLOSE_RANGE)
            locationManager.startUpdatingLocation()
            
            // simulator doesn't support heading data
            if (CLLocationManager.headingAvailable()) {
                locationManager.startUpdatingHeading()
            }
        }
        
        if Debug.sharedInstance.modeText == "User" {
            addBox()
        }
        
        arrowImage.isHidden = true
        circleImage.isHidden = true
        
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
        
        if Debug.sharedInstance.modeText == "User" {
            //sceneView.debugOptions = [ARSCNDebugOptions.showWorldOrigin]
        }
        
        let blur = UIBlurEffect(style: .regular)
        let blurView = UIVisualEffectView(effect: blur)
        blurView.frame = sceneView.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.addSubview(blurView)
    }
    
    // See Haversine formula for calculating bearing between two points:
    // https://en.wikipedia.org/wiki/Haversine_formula
    // https://www.igismap.com/formula-to-find-bearing-or-heading-angle-between-two-points-latitude-longitude/
    func haversine(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Float {
        let deg2rad = Double.pi / 180.0
        let phi1 = from.latitude * deg2rad
        let lambda1 = from.longitude * deg2rad
        let phi2 = to.latitude * deg2rad
        let lambda2 = to.longitude * deg2rad
        let deltaLon = lambda2 - lambda1
        let result = atan2(sin(deltaLon) * cos(phi2), cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLon))
        return Float(result * 180.0 / Double.pi)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if Debug.sharedInstance.modeText == "User" {
            updateDirections()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if Debug.sharedInstance.modeText == "User" {
            updateDirections()
        }
    }
    
    func updateDirections() {
        // Update distance
        if let distance = locationManager.location?.distance(from: destination) {
            car_distance = Float(distance)
        } else {
            car_distance = DIST_MAX
        }
        
        // Update direction
        if let coordinate = locationManager.location?.coordinate {
            car_direction = haversine(from: destination.coordinate, to: coordinate)
        } else {
            car_direction = DIR_MAX
        }
        
        let heading = car_direction
        if let direction = locationManager.heading?.trueHeading {
            if heading < 0.0 {
                let result = heading + 180.0 - Float(direction)
                if result < -180.0 {
                    car_direction = 360.0 + result
                } else {
                    car_direction = result
                }
            } else if heading != DIR_MAX {
                let result = heading - 180.0 - Float(direction)
                if result < -180.0 {
                    car_direction = 360.0 + result
                } else {
                    car_direction = result
                }
            } else {
                car_direction = DIR_MAX
            }
        } else {
            car_direction = DIR_MAX
        }
        if let location = locationManager.location {
            let coordinate = location.coordinate
            coreLocationOutput += "\(dateFormat.string(from: Date())), \(car_distance * 3.280839895), \(car_direction), \(coordinate.longitude), \(coordinate.latitude), \(location.altitude), \(location.course), \(location.speed), \(location.horizontalAccuracy), \(location.verticalAccuracy), \(location.horizontalAccuracy), \(location.speedAccuracy)\n"
        }
        if let stringData = coreLocationOutput.data(using: .utf8) {
            try? stringData.write(to: coreLocationPath!)
        }
        
        if connectedPeer == nil {
            if car_distance < CLOSE_RANGE {
                timeInterval = getTimeInterval(distance: car_distance)
                if ((hapticFeedbackTimer?.isValid) == nil || !hapticFeedbackTimer!.isValid) {
                    hapticFeedbackTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(closeTap), userInfo: nil, repeats: true)
                }
            } else {
                hapticFeedbackTimer?.invalidate()
            }
            updateVisualization(distance: car_distance, direction: car_direction)
            renderingOutput += "\(dateFormat.string(from: Date())), \(car_distance), \(car_direction)\n"
            if let stringData = renderingOutput.data(using: .utf8) {
                try? stringData.write(to: renderingPath!)
            }
        }
    }
    
    func getTimeInterval(distance: Float) -> TimeInterval {
        if distance < CLOSE_RANGE / 8.0 {
            return TimeInterval(0.01)
        } else if distance < 2.0 * CLOSE_RANGE / 8.0 {
            return TimeInterval(0.02)
        } else if distance < 3.0 * CLOSE_RANGE / 8.0 {
            return TimeInterval(0.03)
        } else if distance < 4.0 * CLOSE_RANGE / 8.0 {
            return TimeInterval(0.04)
        } else if distance < 5.0 * CLOSE_RANGE / 8.0 {
            return TimeInterval(0.05)
        } else if distance < 6.0 * CLOSE_RANGE / 8.0 {
            return TimeInterval(0.06)
        } else if distance < 7.0 * CLOSE_RANGE / 8.0 {
            return TimeInterval(0.07)
        } else {
            return TimeInterval(0.08)
        }
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
        if distance != DIST_MAX {
            let distanceFill = String(format: "%0.1f", distance * 3.280839895)
            if distance < CLOSE_RANGE {
                let attributedString1 = NSMutableAttributedString(string: "\(distanceFill) ", attributes: attributes1)
                let attributedString2 = NSMutableAttributedString(string: "ft\n", attributes: attributes2)
                let attributedString3 = NSMutableAttributedString(string: "nearby", attributes: attributes1)
                
                attributedString1.append(attributedString2)
                attributedString1.append(attributedString3)
                
                directionDescriptionLabel.attributedText = attributedString1
                
                circleImage.isHidden = false
                let scale = CGFloat(distance / CLOSE_RANGE / 2.0 + 0.5)
                circleImage.bounds.size = CGSize(width: scale * circleImageSize.width, height: scale * circleImageSize.height)
            } else {
                if direction != DIR_MAX {
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
                circleImage.isHidden = true
            }
        } else {
            let attributedString1 = NSMutableAttributedString(string: "\n-.--", attributes: attributes1)
            let attributedString2 = NSMutableAttributedString(string: " ft", attributes: attributes2)
            
            attributedString1.append(attributedString2)
            
            directionDescriptionLabel.attributedText = attributedString1
            circleImage.isHidden = true
        }
        
        if direction != DIR_MAX && circleImage.isHidden {
            arrowImage.isHidden = false
            arrowImage.transform = arrowImage.transform.rotated(by: (CGFloat(direction) - atan2(arrowImage.transform.b, arrowImage.transform.a).radiansToDegrees).degreesToRadians)
        } else {
            arrowImage.isHidden = true
        }
    }
    
    @objc func closeTap() {
        timerCounter += 0.01
        if timerCounter >= Float(timeInterval) {
            timerCounter = 0.0
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        }
    }
    
    // MARK: - NISessionDelegate
    
    func azimuth(from direction: simd_float3) -> Float {
        return asin(direction.x)
    }

    // Provides the elevation from the argument 3D directional.
    func elevation(from direction: simd_float3) -> Float {
        return atan2(direction.z, direction.y) + .pi / 2
    }
    
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let peerToken = peerDiscoveryToken else {
            return
        }

        let peerObj = nearbyObjects.first { (obj) -> Bool in
            return obj.discoveryToken == peerToken
        }

        guard let nearbyObjectUpdate = peerObj else {
            return
        }
        
        var distance: Float = MAXFLOAT
        if nearbyObjects.count > 0 {
            distance = max(0.0, nearbyObjectUpdate.distance!)
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
            distance = DIST_MAX
        }
        
        var direction : Float
        if distance != DIST_MAX {
            if let dir = nearbyObjects.first?.direction {
                directions.append(Direction(direction: dir, timestamp: Date()))
                sceneView.session.setWorldOrigin(relativeTransform: simd_float4x4(currentCamera))
                let yaw = nearbyObjects.first!.direction.map(azimuth(from:))!
                let pitch = -nearbyObjects.first!.direction.map(elevation(from:))!
                nearbyInteractionOutput += "\(dateFormat.string(from: Date())), \(distance * 3.280839895), \(yaw.radiansToDegrees), \(pitch.radiansToDegrees)\n"
                if let stringData = nearbyInteractionOutput.data(using: .utf8) {
                    try? stringData.write(to: nearbyInteractionPath!)
                }
                
                direction = yaw.radiansToDegrees
                if Debug.sharedInstance.modeText == "User" {
                    boxNode.position = SCNVector3(sin(pitch) * distance, sin(yaw) * distance, -distance)
                    sceneView.scene.rootNode.addChildNode(boxNode)
                }
            } else {
                if boxNode.transform.m41 != 0.0 || boxNode.transform.m42 != 0.0 || boxNode.transform.m43 != 0.0 {
                    let transform = sceneView.session.currentFrame?.camera.transform
                    let deltax = boxNode.transform.m41 - (transform?.columns.3[0])!
                    let deltay = boxNode.transform.m42 - (transform?.columns.3[1])!
                    let deltaz = boxNode.transform.m43 - (transform?.columns.3[2])!
                    let unitvector = simd_float3(deltax / distance, deltay / distance, deltaz / distance)
                    let yaw = asin(unitvector.x)
                    let pitch = -atan2(unitvector.z, unitvector.y) + .pi / 2
                    direction = yaw.radiansToDegrees
                    nearbyInteractionOutput += "\(dateFormat.string(from: Date())), \(distance * 3.280839895), \(yaw), \(pitch)\n"
                    if let stringData = nearbyInteractionOutput.data(using: .utf8) {
                        try? stringData.write(to: nearbyInteractionPath!)
                    }
                } else {
                    direction = DIR_MAX
                    nearbyInteractionOutput += "\(dateFormat.string(from: Date())), \(distance * 3.280839895), using GPS direction backup, using GPS direction backup\n"
                    if let stringData = nearbyInteractionOutput.data(using: .utf8) {
                        try? stringData.write(to: nearbyInteractionPath!)
                    }
                }
            }
        } else {
            direction = DIR_MAX
            nearbyInteractionOutput += "\(dateFormat.string(from: Date())), \(distance * 3.280839895), nil, nil\n"
            if let stringData = nearbyInteractionOutput.data(using: .utf8) {
                try? stringData.write(to: nearbyInteractionPath!)
            }
        }
        
        if connectedPeer != nil {
            if distance == DIST_MAX && direction == DIR_MAX {
                if car_distance < CLOSE_RANGE {
                    timeInterval = getTimeInterval(distance: car_distance)
                    if ((hapticFeedbackTimer?.isValid) == nil || !hapticFeedbackTimer!.isValid) {
                        hapticFeedbackTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(closeTap), userInfo: nil, repeats: true)
                    }
                } else {
                    hapticFeedbackTimer?.invalidate()
                }
                updateVisualization(distance: car_distance, direction: car_direction)
                renderingOutput += "\(dateFormat.string(from: Date())), \(car_distance * 3.280839895), \(car_direction)\n"
                if let stringData = renderingOutput.data(using: .utf8) {
                    try? stringData.write(to: renderingPath!)
                }
            } else if direction == DIR_MAX {
                if distance < CLOSE_RANGE {
                    timeInterval = getTimeInterval(distance: distance)
                    if ((hapticFeedbackTimer?.isValid) == nil || !hapticFeedbackTimer!.isValid) {
                        hapticFeedbackTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(closeTap), userInfo: nil, repeats: true)
                    }
                } else {
                    hapticFeedbackTimer?.invalidate()
                }
                updateVisualization(distance: distance, direction: car_direction)
                renderingOutput += "\(dateFormat.string(from: Date())), \(distance * 3.280839895), \(car_direction)\n"
                if let stringData = renderingOutput.data(using: .utf8) {
                    try? stringData.write(to: renderingPath!)
                }
            } else {
                if distance < CLOSE_RANGE {
                    timeInterval = getTimeInterval(distance: distance)
                    if ((hapticFeedbackTimer?.isValid) == nil || !hapticFeedbackTimer!.isValid) {
                        hapticFeedbackTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(closeTap), userInfo: nil, repeats: true)
                    }
                } else {
                    hapticFeedbackTimer?.invalidate()
                }
                updateVisualization(distance: distance, direction: direction)
                renderingOutput += "\(dateFormat.string(from: Date())), \(distance * 3.280839895), \(direction)\n"
                if let stringData = renderingOutput.data(using: .utf8) {
                    try? stringData.write(to: renderingPath!)
                }
            }
        }
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

