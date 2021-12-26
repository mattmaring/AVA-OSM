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
import AVFoundation
import os.log

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

enum MessageId: UInt8 {
    // Messages from the accessory.
    case accessoryConfigurationData = 0x1
    case accessoryUwbDidStart = 0x2
    case accessoryUwbDidStop = 0x3

    // Messages to the accessory.
    case initialize = 0xA
    case configureAndStart = 0xB
    case stop = 0xC
}

class TrackerViewController: UIViewController, NISessionDelegate, SCNSceneRendererDelegate, ARSCNViewDelegate, ARSessionDelegate, CLLocationManagerDelegate {
    
    // MARK: - `IBOutlet` instances
    @IBOutlet weak var directionDescriptionLabel: UILabel!
    @IBOutlet weak var arrowImage: UIImageView!
    @IBOutlet weak var circleImage: UIImageView!
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var uwb_data: UILabel!
    
    @IBOutlet weak var blurToggle: UISwitch!
    @IBAction func blurToggle(_ sender: Any) {
        if blurToggle.isOn {
            let blur = UIBlurEffect(style: .regular)
            let blurView = UIVisualEffectView(effect: blur)
            blurView.frame = sceneView.bounds
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            sceneView.addSubview(blurView)
        } else {
            for subview in sceneView.subviews {
                if subview is UIVisualEffectView {
                    subview.removeFromSuperview()
                }
            }
        }
    }
    
    // MARK: - ARKit variables
    var boxNode = SCNNode()
    let lookingNode = SCNNode()
    var currentCamera = SCNMatrix4()
    
    @IBOutlet weak var boxToggle: UISwitch!
    @IBAction func boxToggle(_ sender: Any) {
        if boxToggle.isOn {
            boxNode.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        } else {
            boxNode.geometry?.firstMaterial?.diffuse.contents = UIColor.white
        }
    }
    
    @IBOutlet weak var hapticToggle: UISwitch!
    
    // MARK: - Class variables
    var dataChannel = DataCommunicationChannel()
    var session = NISession()
    var configuration : NINearbyAccessoryConfiguration?
    var storedObject : NINearbyObject?
    var accessoryConnected = false
    var uwbConnectionActive = false
    var arrived = false
    var calibrating = true
    var lightTooLow = false
    var locationManager = CLLocationManager()
    var circleImageSize = CGSize()
    
    // A mapping from a discovery token to a name.
    var accessoryMap = [NIDiscoveryToken: String]()
    
    // MARK: - Timer
    var connectionTimer = Timer()
    var hapticFeedbackTimer: Timer?
    var timeInterval = 0.01
    var timerCounter: Float = 0.0
    
    // MARK: - Default values
    let DIST_MAX: Float = 999999.0
    let YAW_MAX: Float = 999.0
    let HEADING_MAX: Double = 999.0
    let CLOSE_RANGE: Float = 0.333
    
    // MARK: - Car location
    //let destination = CLLocation(latitude: 44.564825926200015, longitude: -69.65909124016235)
    let destination = CLLocation(latitude: 44.56320, longitude: -69.66136)
    
    // GPS location storage
    var car_distance: Float = 999999.0
    var car_yaw: Float = 999.0
    
    // uwb location storage
    var uwb_distance : Float = 999999.0
    var uwb_yaw : Float = 999.0
    var uwb_pitch : Float = 999.0
    var last_position = SCNVector3()
    
    // counter for uwb updates
    var iterations : Int = 0
    
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
        
        blurToggle.isOn = true
        boxToggle.isOn = true
        hapticToggle.isOn = true
        
        arrowImage.isHidden = true
        circleImage.isHidden = true
        uwb_data.text = ""
        
        sceneView.session.delegate = self
        
        let doorHandle = ARWWorldAnchor(column3: [0, 0, 0, 1])
        sceneView.session.add(anchor: ARAnchor(anchor: doorHandle))
        
        // Initialize visualizations
        let attributedString1 = NSMutableAttributedString(string: "\n-.--", attributes: attributes1)
        let attributedString2 = NSMutableAttributedString(string: " ft", attributes: attributes2)
        
        attributedString1.append(attributedString2)
        
        directionDescriptionLabel.attributedText = attributedString1
        
        // Set a delegate for session updates from the framework.
        session.delegate = self
        
        // Prepare the data communication channel.
        dataChannel.accessoryConnectedHandler = accessoryConnected
        dataChannel.accessoryDisconnectedHandler = accessoryDisconnected
        dataChannel.accessoryDataHandler = accessorySharedData
        dataChannel.start()
        
        connectionTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(restoreSession), userInfo: nil, repeats: true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let configuration = ARWorldTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.worldAlignment = .gravityAndHeading
        
        configuration.planeDetection = [.horizontal, .vertical]
        
        sceneView.session.run(configuration)
        
        addBox()
        
        //sceneView.debugOptions = [ARSCNDebugOptions.showWorldOrigin]
        
        if blurToggle.isOn {
            let blur = UIBlurEffect(style: .regular)
            let blurView = UIVisualEffectView(effect: blur)
            blurView.frame = sceneView.bounds
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            sceneView.addSubview(blurView)
        }
    }
    
    @objc func restoreSession() {
        if arrived == false && uwbConnectionActive == false {
            sendDataToAccessory(Data([MessageId.initialize.rawValue]))
        } else {
            connectionTimer.invalidate()
        }
    }
    
    // MARK: - Data channel methods

    func accessorySharedData(data: Data, accessoryName: String) {
        // The accessory begins each message with an identifier byte.
        // Ensure the message length is within a valid range.
        if data.count < 1 { return }

        // Assign the first byte which is the message identifier.
        guard let messageId = MessageId(rawValue: data.first!) else {
            fatalError("\(data.first!) is not a valid MessageId.")
        }

        // Handle the data portion of the message based on the message identifier.
        switch messageId {
        case .accessoryConfigurationData:
            // Access the message data by skipping the message identifier.
            assert(data.count > 1)
            let message = data.advanced(by: 1)
            setupAccessory(message, name: accessoryName)
        case .accessoryUwbDidStart:
            uwbConnectionActive = true
        case .accessoryUwbDidStop:
            uwbConnectionActive = false
        case .configureAndStart:
            fatalError("Accessory should not send 'configureAndStart'.")
        case .initialize:
            fatalError("Accessory should not send 'initialize'.")
        case .stop:
            fatalError("Accessory should not send 'stop'.")
        }
    }

    func accessoryConnected(name: String) {
        accessoryConnected = true
    }

    func accessoryDisconnected() {
        accessoryConnected = false
    }

    // MARK: - Accessory messages handling

    func setupAccessory(_ configData: Data, name: String) {
        do {
            configuration = try NINearbyAccessoryConfiguration(data: configData)
        } catch {
            return
        }

        // Cache the token to correlate updates with this accessory.
        cacheToken(configuration!.accessoryDiscoveryToken, accessoryName: name)
        session.run(configuration!)
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
    
    // MARK: - CoreLocation
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        updateDirections()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        updateDirections()
        if let accessory = storedObject, uwbConnectionActive {
            updateObject(accessory: accessory)
        }
    }
    
    // MARK: - Update GPS Directions
    
    func updateDirections() {
        // Update distance
        if let distance = locationManager.location?.distance(from: destination) {
            car_distance = Float(distance)
        } else {
            car_distance = DIST_MAX
        }
        
        // Update direction
        if let coordinate = locationManager.location?.coordinate {
            car_yaw = haversine(from: destination.coordinate, to: coordinate)
        } else {
            car_yaw = YAW_MAX
        }
        
        if let heading = locationManager.heading?.trueHeading {
            if car_yaw < 0.0 {
                let result = car_yaw + 180.0 - Float(heading)
                if result < -180.0 {
                    car_yaw = 360.0 + result
                } else {
                    car_yaw = result
                }
            } else if car_yaw != YAW_MAX {
                let result = car_yaw - 180.0 - Float(heading)
                if result < -180.0 {
                    car_yaw = 360.0 + result
                } else {
                    car_yaw = result
                }
            } else {
                car_yaw = YAW_MAX
            }
        } else {
            car_yaw = YAW_MAX
        }
        
        if uwbConnectionActive == false {
            if car_distance < CLOSE_RANGE {
                timeInterval = getTimeInterval(distance: car_distance)
                if ((hapticFeedbackTimer?.isValid) == nil || !hapticFeedbackTimer!.isValid) {
                    hapticFeedbackTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(closeTap), userInfo: nil, repeats: true)
                }
            } else {
                hapticFeedbackTimer?.invalidate()
            }
            updateVisualization(distance: car_distance, yaw: car_yaw)
            renderingOutput += "\(dateFormat.string(from: Date())), \(car_distance), \(car_yaw)\n"
            //print("\(dateFormat.string(from: Date())), \(car_distance), \(car_yaw)")
            if let stringData = renderingOutput.data(using: .utf8) {
                try? stringData.write(to: renderingPath!)
            }
            
            if let location = locationManager.location {
                let coordinate = location.coordinate
                coreLocationOutput += "\(dateFormat.string(from: Date())), \(car_distance * 3.280839895), \(car_yaw), \(coordinate.longitude), \(coordinate.latitude), \(location.altitude), \(location.course), \(location.speed), \(location.horizontalAccuracy), \(location.verticalAccuracy), \(location.horizontalAccuracy), \(location.speedAccuracy)\n"
            }
            if let stringData = coreLocationOutput.data(using: .utf8) {
                try? stringData.write(to: coreLocationPath!)
            }
        }
    }
    
    // MARK: - Haptic Feedback
    
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
    
    @objc func closeTap() {
        timerCounter += 0.01
        if timerCounter >= Float(timeInterval) {
            timerCounter = 0.0
            var generator : UIImpactFeedbackGenerator
            generator = UIImpactFeedbackGenerator(style: .heavy)
//            switch timeInterval {
//            case TimeInterval(0.01):
//                generator = UIImpactFeedbackGenerator(style: .heavy)
//            case TimeInterval(0.02):
//                generator = UIImpactFeedbackGenerator(style: .heavy)
//            case TimeInterval(0.03):
//                generator = UIImpactFeedbackGenerator(style: .heavy)
//            case TimeInterval(0.04):
//                generator = UIImpactFeedbackGenerator(style: .medium)
//            case TimeInterval(0.05):
//                generator = UIImpactFeedbackGenerator(style: .medium)
//            case TimeInterval(0.06):
//                generator = UIImpactFeedbackGenerator(style: .medium)
//            case TimeInterval(0.07):
//                generator = UIImpactFeedbackGenerator(style: .light)
//            case TimeInterval(0.08):
//                generator = UIImpactFeedbackGenerator(style: .light)
//            default:
//                generator = UIImpactFeedbackGenerator(style: .light)
//            }
//
            if hapticToggle.isOn {
                generator.impactOccurred()
            }
        }
    }
    
    // MARK: - ARSession
    
    func addBox() {
        boxNode.geometry = SCNBox(width: 0.05, height: 0.05, length: 0.05, chamferRadius: 0)
        boxNode.position = SCNVector3(0, 0, 0)
        if boxToggle.isOn {
            boxNode.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        } else {
            boxNode.geometry?.firstMaterial?.diffuse.contents = UIColor.white
        }
        sceneView.scene.rootNode.addChildNode(boxNode)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if let lightIntensity = frame.lightEstimate?.ambientIntensity, lightIntensity < 100.0 { //1000 is normal
            lightTooLow = true
        } else {
            lightTooLow = false
        }
        currentCamera = SCNMatrix4(frame.camera.transform)
    }
    
    func updatePositionAndOrientationOf(_ node: SCNNode, withPosition position: SCNVector3, relativeTo referenceNode: SCNNode) {
        let referenceNodeTransform = matrix_float4x4(referenceNode.transform)

        // Setup a translation matrix with the desired position
        var translationMatrix = matrix_identity_float4x4
        translationMatrix.columns.3.x = position.x
        translationMatrix.columns.3.y = position.y
        translationMatrix.columns.3.z = position.z

        // Combine the configured translation matrix with the referenceNode's transform to get the desired position AND orientation
        let updatedTransform = matrix_multiply(referenceNodeTransform, translationMatrix)
        node.transform = SCNMatrix4(updatedTransform)
    }
    
    func calculateAngleBetween3Positions(pos1:SCNVector3, pos2:SCNVector3, pos3:SCNVector3) -> Float {
        let v1 = SCNVector3(x: pos2.x-pos1.x, y: pos2.y-pos1.y, z: pos2.z-pos1.z)
        let v2 = SCNVector3(x: pos3.x-pos1.x, y: pos3.y-pos1.y, z: pos3.z-pos1.z)

        let v1Magnitude = sqrt(v1.x * v1.x + v1.y * v1.y + v1.z * v1.z)
        let v1Normal = SCNVector3(x: v1.x/v1Magnitude, y: v1.y/v1Magnitude, z: v1.z/v1Magnitude)
      
        let v2Magnitude = sqrt(v2.x * v2.x + v2.y * v2.y + v2.z * v2.z)
        let v2Normal = SCNVector3(x: v2.x/v2Magnitude, y: v2.y/v2Magnitude, z: v2.z/v2Magnitude)

        let result = v1Normal.x * v2Normal.x + v1Normal.y * v2Normal.y + v1Normal.z * v2Normal.z
        let angle = acos(result)

        return angle
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
    
    func updateVisualization(distance: Float, yaw: Float) {
        if arrived {
            hapticFeedbackTimer?.invalidate()
            circleImage.isHidden = true
            arrowImage.isHidden = true
            directionDescriptionLabel.attributedText = NSMutableAttributedString(string: "Arrived", attributes: attributes1)
            return
        }
        
        if lightTooLow {
            hapticFeedbackTimer?.invalidate()
            circleImage.isHidden = true
            arrowImage.isHidden = true
            directionDescriptionLabel.attributedText = NSMutableAttributedString(string: "Light too low", attributes: attributes1)
            return
        }
        
        if calibrating {
            hapticFeedbackTimer?.invalidate()
            circleImage.isHidden = true
            arrowImage.isHidden = true
            directionDescriptionLabel.attributedText = NSMutableAttributedString(string: "Calibrating", attributes: attributes1)
            return
        }
        
        if distance != DIST_MAX {
            var format = "%0.0f"
            if distance < CLOSE_RANGE {
                format = "%0.1f"
            }
            let distanceFill = String(format: format, distance * 3.280839895)
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
                if yaw != YAW_MAX {
                    let desc = directionNaturalLanguage(degrees: yaw)
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
        
        if yaw != YAW_MAX && circleImage.isHidden {
            arrowImage.isHidden = false
            arrowImage.transform = arrowImage.transform.rotated(by: (CGFloat(yaw) - atan2(arrowImage.transform.b, arrowImage.transform.a).radiansToDegrees).degreesToRadians)
        } else {
            arrowImage.isHidden = true
        }
    }
    
    func get3DPosition(pov: SCNVector3, azimuth: Float, elevation: Float, distance: Float) -> SCNVector3 {
        // SCNVector3(uwb_distance * sin(pov.eulerAngles.y + azimuth), uwb_distance * sin(pov.eulerAngles.x + elevation), -uwb_distance * cos(pov.eulerAngles.y + azimuth))
        
        let pitch = pov.x + elevation
        let yaw = -pov.y + azimuth
        
        //uwb_data.text = "\(round(-pov.y.radiansToDegrees)) | \(round(azimuth.radiansToDegrees)) | \(round(yaw.radiansToDegrees))"
        //print(pov.x.radiansToDegrees, elevation.radiansToDegrees, pitch.radiansToDegrees)
        
        let y = uwb_distance * sin(pitch)
        let _uwb_distance = sqrt(uwb_distance * uwb_distance - y * y)
        let x = _uwb_distance * sin(yaw)
        let z = -_uwb_distance * cos(yaw)
        
        return SCNVector3(x, y, z)
    }
    
    // MARK: - NISessionDelegate
    
    func azimuth(from direction: simd_float3) -> Float {
        return asin(direction.x)
    }

    // Provides the elevation from the argument 3D directional.
    func elevation(from direction: simd_float3) -> Float {
        return atan2(direction.z, direction.y) + .pi / 2
    }
    
    // // Initialization
    // let process_uncertainty: Float = 0.15
    // let predicted_estimate: Float = 10.0 // 10m or 29.5276ft, change this value later based on GPS/etc
    // let standard_deviation: Float = 0.5
    // let error_variance = standard_deviation * standard_deviation //0.25
    //
    // // Prediction
    // let current_estimate: Float = 10.0 // 10m or 29.5276ft, change this value later based on GPS/etc
    // let variance = error_variance + process_uncertainty //0.40
    //
    // // First Iteration
    // let measurement_value = nearbyObjectUpdate.distance!
    // let measurement_uncertainty = error_variance
    // let kalman_gain = variance / (variance + measurement_uncertainty) // 0.61538
    // let distance = current_estimate + kalman_gain * (measurement_value - current_estimate)
    // let count = nearbyObjects.count
    // let dist = nearbyObjectUpdate.distance!
    // let prev = nearbyObjects[count - 2].distance!
    // let variance = (dist - prev) / prev
    // distance = prev + variance * (dist - prev)
    
    func session(_ session: NISession, didGenerateShareableConfigurationData shareableConfigurationData: Data, for object: NINearbyObject) {
        guard object.discoveryToken == configuration?.accessoryDiscoveryToken else { return }

        // Prepare to send a message to the accessory.
        var msg = Data([MessageId.configureAndStart.rawValue])
        msg.append(shareableConfigurationData)

        //let str = msg.map { String(format: "0x%02x, ", $0) }.joined()

        // Send the message to the accessory.
        sendDataToAccessory(msg)
    }
    
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let accessory = nearbyObjects.first else { return }
        
        if !accessoryConnected { return }
        
        //if arrived { return }
        
        if lightTooLow { return }
                
        storedObject = accessory
        
        iterations += 1
        if iterations < 10 {
            calibrating = true
        } else {
            calibrating = false
        }
        
        updateObject(accessory: accessory)
    }
    
    // MARK: - Update NINearbyObject
    
    func updateObject(accessory: NINearbyObject) {
        if let distance = accessory.distance {
            uwb_distance = distance
            if uwb_distance == 0.0 {
                arrived = true
                //sendDataToAccessory(Data([MessageId.stop.rawValue]))
            } else {
                arrived = false
            }
        } else if !uwbConnectionActive {
            uwb_distance = DIST_MAX
        }
        
        if let direction = accessory.direction, uwb_distance > CLOSE_RANGE && abs(azimuth(from: direction).radiansToDegrees) < 20.0 && abs(elevation(from: direction).radiansToDegrees) < 20.0 {
            let azimuth = azimuth(from: direction)
            let elevation = elevation(from: direction)
            
            guard let camera = sceneView.session.currentFrame?.camera else { return }
            guard let pov = sceneView.pointOfView else { return }
            last_position = pov.position
            
            boxNode.simdEulerAngles = direction
            boxNode.position = SCNVector3(0, 0, -2)
            //boxNode.position = get3DPosition(pov: SCNVector3(x: camera.eulerAngles.x, y: camera.eulerAngles.y, z: camera.eulerAngles.z), azimuth: azimuth, elevation: elevation, distance: uwb_distance)
            
            //print(pov.eulerAngles.y.radiansToDegrees, -azimuth.radiansToDegrees, boxNode.position)
            sceneView.scene.rootNode.addChildNode(boxNode)
            
            uwb_yaw = azimuth.radiansToDegrees
            uwb_pitch = elevation.radiansToDegrees
            //print(uwb_distance, uwb_yaw, uwb_pitch)
            
//            nearbyInteractionOutput += "\(dateFormat.string(from: Date())), \(uwb_distance * 3.280839895), \(uwb_yaw), \(uwb_pitch)\n"
//            if let stringData = nearbyInteractionOutput.data(using: .utf8) {
//                try? stringData.write(to: nearbyInteractionPath!)
//            }
        } else if boxNode.transform.m41 != 0.0 || boxNode.transform.m42 != 0.0 || boxNode.transform.m43 != 0.0 {
            guard let camera = sceneView.session.currentFrame?.camera else { return }
            guard let position = sceneView.pointOfView?.position else { return }

            //uwb_data.text = "\(position.x) | \(boxNode.position.x)"
            
            /* Digram - 2D direction field
                            (N | z-)
                               |
                               |
                         IV    |    I
                               |
            (W | x-) ——————————+—————————— (E | x+)
                               |
                        III    |    II
                               |
                               |
                            (S | z+)
             */
            
            // Example cases
            // Position = (-2, -1)
            // Node = (1, 1)
            
            // Check direction scenarios
            var move_angle : Float
            if position.x < boxNode.position.x {
                let dz = boxNode.position.z - position.z
                let dx = boxNode.position.x - position.x
                move_angle = atan(dz / dx) + .pi / 2.0
            } else if position.x > boxNode.position.x {
                let dz = boxNode.position.z - position.z
                let dx = boxNode.position.x - position.x
                move_angle = atan(dz / dx) - .pi / 2.0
            } else {
                if position.z < boxNode.position.z {
                    move_angle = .pi
                } else if position.z > boxNode.position.z {
                    move_angle = 0.0
                } else {
                    move_angle = 0.0 // Filler value
                }
            }
            
//            // Need to examine this
//            var angle : Float
//            if dist < 0 {
//                angle = atan(-deltax / dist)
//            } else if dist > 0 {
//                angle = atan(deltax / dist)
//            } else {
//                angle = 0.0
//            }
//
//            var move_angle : Float
//            if boxNode.position.z < 0 {
//                move_angle = atan(boxNode.position.x / boxNode.position.z)
//            } else if boxNode.position.z > 0 {
//                if boxNode.position.x < 0 {
//                    move_angle = .pi + atan(boxNode.position.x / boxNode.position.z)
//                } else if boxNode.position.x > 0 {
//                    move_angle = -.pi + atan(boxNode.position.x / boxNode.position.z)
//                } else {
//                    move_angle = .pi
//                }
//            } else {
//                // Handle divide by 0
//                if boxNode.position.x < 0 {
//                    move_angle = .pi / 2.0
//                } else if boxNode.position.x > 0 {
//                    move_angle = -.pi / 2.0
//                } else {
//                    move_angle = 0.0
//                }
//            }
            
            var yaw = move_angle.radiansToDegrees + camera.eulerAngles.y.radiansToDegrees
            if yaw <= -180.0 {
                yaw += 360.0
            } else if yaw > 180.0 {
                yaw -= 360.0
            }
            uwb_yaw = yaw
            //uwb_data.text = "\(move_angle.radiansToDegrees) | \(camera.eulerAngles.y.radiansToDegrees)"

//            nearbyInteractionOutput += "\(dateFormat.string(from: Date())), \(uwb_distance * 3.280839895), \(uwb_yaw), \(uwb_pitch)\n"
//            if let stringData = nearbyInteractionOutput.data(using: .utf8) {
//                try? stringData.write(to: nearbyInteractionPath!)
//            }
        } else if !uwbConnectionActive {
            uwb_yaw = YAW_MAX
//            nearbyInteractionOutput += "\(dateFormat.string(from: Date())), \(uwb_distance * 3.280839895), nil, nil\n"
//            if let stringData = nearbyInteractionOutput.data(using: .utf8) {
//                try? stringData.write(to: nearbyInteractionPath!)
//            }
        }
        
        if uwbConnectionActive == true {
            if uwb_distance == DIST_MAX && uwb_yaw == YAW_MAX {
                if car_distance < CLOSE_RANGE {
                    timeInterval = getTimeInterval(distance: car_distance)
                    if ((hapticFeedbackTimer?.isValid) == nil || !hapticFeedbackTimer!.isValid) {
                        hapticFeedbackTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(closeTap), userInfo: nil, repeats: true)
                    }
                } else {
                    hapticFeedbackTimer?.invalidate()
                }
                updateVisualization(distance: car_distance, yaw: car_yaw)
                renderingOutput += "\(dateFormat.string(from: Date())), \(car_distance * 3.280839895), \(car_yaw)\n"
                //print("\(dateFormat.string(from: Date())), \(car_distance * 3.280839895), \(car_yaw)")
                if let stringData = renderingOutput.data(using: .utf8) {
                    try? stringData.write(to: renderingPath!)
                }
            } else if uwb_yaw == YAW_MAX {
                if uwb_distance < CLOSE_RANGE {
                    timeInterval = getTimeInterval(distance: uwb_distance)
                    if ((hapticFeedbackTimer?.isValid) == nil || !hapticFeedbackTimer!.isValid) {
                        hapticFeedbackTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(closeTap), userInfo: nil, repeats: true)
                    }
                } else {
                    hapticFeedbackTimer?.invalidate()
                }
                updateVisualization(distance: uwb_distance, yaw: car_yaw)
                renderingOutput += "\(dateFormat.string(from: Date())), \(uwb_distance * 3.280839895), \(car_yaw)\n"
                //print("\(dateFormat.string(from: Date())), \(uwb_distance * 3.280839895), \(car_yaw)")
                if let stringData = renderingOutput.data(using: .utf8) {
                    try? stringData.write(to: renderingPath!)
                }
            } else {
                if uwb_distance < CLOSE_RANGE {
                    timeInterval = getTimeInterval(distance: uwb_distance)
                    if ((hapticFeedbackTimer?.isValid) == nil || !hapticFeedbackTimer!.isValid) {
                        hapticFeedbackTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(closeTap), userInfo: nil, repeats: true)
                    }
                } else {
                    hapticFeedbackTimer?.invalidate()
                }
                updateVisualization(distance: uwb_distance, yaw: uwb_yaw)
                renderingOutput += "\(dateFormat.string(from: Date())), \(uwb_distance * 3.280839895), \(uwb_yaw)\n"
                //print("\(dateFormat.string(from: Date())), \(uwb_distance * 3.280839895), \(uwb_yaw)")
                if let stringData = renderingOutput.data(using: .utf8) {
                    try? stringData.write(to: renderingPath!)
                }
            }
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
//        guard let peerToken = peerDiscoveryToken else {
//            fatalError("don't have peer token")
//        }
//
//        let peerObj = nearbyObjects.first { (obj) -> Bool in
//            return obj.discoveryToken == peerToken
//        }
//
//        if peerObj == nil {
//            return
//        }
//
//        switch reason {
//        case .peerEnded:
//            peerDiscoveryToken = nil
//            session.invalidate()
//            initiateSession()
//        case .timeout:
//            if let config = session.configuration {
//                session.run(config)
//            }
//        default:
//            fatalError("Unknown and unhandled NINearbyObject.RemovalReason")
//        }
        // Retry the session only if the peer timed out.
        guard reason == .timeout else { return }

        // The session runs with one accessory.
        guard let accessory = nearbyObjects.first else { return }

        // Clear the app's accessory state.
        accessoryMap.removeValue(forKey: accessory.discoveryToken)

        // Consult helper function to decide whether or not to retry.
        if shouldRetry(accessory) {
            sendDataToAccessory(Data([MessageId.stop.rawValue]))
            sendDataToAccessory(Data([MessageId.initialize.rawValue]))
        }
    }
    
    func sessionWasSuspended(_ session: NISession) {
        sendDataToAccessory(Data([MessageId.stop.rawValue]))
    }

    func sessionSuspensionEnded(_ session: NISession) {
        sendDataToAccessory(Data([MessageId.initialize.rawValue]))
    }

//    func sessionSuspensionEnded(_ session: NISession) {
//        if let config = self.session?.configuration {
//            session.run(config)
//        } else {
//            initiateSession()
//        }
//    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
//        if case NIError.userDidNotAllow = error {
//            if #available(iOS 15.0, *) {
//                let accessAlert = UIAlertController(title: "Access Required", message: "AVA OSM requires access to Nearby Interactions to provide accurate navigation to the vehicle.", preferredStyle: .alert)
//                accessAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
//                accessAlert.addAction(UIAlertAction(title: "Go to Settings", style: .default, handler: {_ in
//                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
//                        UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
//                    }
//                }))
//                present(accessAlert, animated: true, completion: nil)
//            } else {
//                let accessAlert = UIAlertController(title: "Access Required", message: "Nearby Interactions access required. Restart AVA OSM to allow access.", preferredStyle: .alert)
//                accessAlert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
//                present(accessAlert, animated: true, completion: nil)
//            }
//            return
//        }
//        initiateSession()
        switch error {
        case NIError.invalidConfiguration:
            print("The accessory configuration data is invalid. Please debug it and try again.")
        case NIError.userDidNotAllow:
            handleUserDidNotAllow()
        default:
            handleSessionInvalidation()
        }
    }
    
    // MARK: - Communication Handlers
    
    func sendDataToAccessory(_ data: Data) {
        do {
            try dataChannel.sendData(data)
        } catch {
            print("Failed to send data to accessory: \(error)")
        }
    }

    func handleSessionInvalidation() {
        print("Session invalidated. Restarting.")
        // Ask the accessory to stop.
        sendDataToAccessory(Data([MessageId.stop.rawValue]))

        // Replace the invalidated session with a new one.
        self.session = NISession()
        self.session.delegate = self

        // Ask the accessory to restart.
        sendDataToAccessory(Data([MessageId.initialize.rawValue]))
    }

    func shouldRetry(_ accessory: NINearbyObject) -> Bool {
        if accessoryConnected {
            return true
        }
        return false
    }

    func cacheToken(_ token: NIDiscoveryToken, accessoryName: String) {
        accessoryMap[token] = accessoryName
    }

    func handleUserDidNotAllow() {
        // Create an alert to request the user go to Settings.
        let accessAlert = UIAlertController(title: "Access Required",
                                            message: """
                                            NIAccessory requires access to Nearby Interactions for this sample app.
                                            Use this string to explain to users which functionality will be enabled if they change
                                            Nearby Interactions access in Settings.
                                            """,
                                            preferredStyle: .alert)
        accessAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        accessAlert.addAction(UIAlertAction(title: "Go to Settings", style: .default, handler: {_ in
            // Navigate the user to the app's settings.
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
            }
        }))

        // Preset the access alert.
        present(accessAlert, animated: true, completion: nil)
    }
}

// MARK: - Utils.
var distArray: Array<Float> = Array(repeating: 0, count: 10)
let zeroVector = simd_make_float3(0, 0, 0)
var diretArray: Array<simd_float3> = Array(repeating: zeroVector, count: 10)
var avgDistIndex = 0
var avgDiretIndex = 0

// Provides the azimuth from an argument 3D directional.
func azimuth(_ direction: simd_float3) -> Float {
    return asin(direction.x)
}

// Provides the elevation from the argument 3D directional.
func elevation(_ direction: simd_float3) -> Float {
    return atan2(direction.z, direction.y) + .pi / 2
}

func includeDistance(_ value: Float) {

    distArray[avgDistIndex] = value

    if avgDistIndex < (distArray.count - 1) {
        avgDistIndex += 1
    }
    else {
        avgDistIndex = 0
    }
}

func getAvgDistance() -> Float {
    var sumValue: Float

    sumValue = 0

    for value in distArray {
        sumValue += value
    }

    return Float(sumValue)/Float(distArray.count)
}

func includeDirection(_ value: simd_float3) {

    diretArray[avgDiretIndex] = value

    if avgDiretIndex < (diretArray.count - 1) {
        avgDiretIndex += 1
    }
    else {
        avgDiretIndex = 0
    }
}

func getAvgDirection() -> simd_float3 {
    var sumValue: simd_float3

    sumValue = zeroVector

    for value in diretArray {
        sumValue += value
    }

    return simd_float3(sumValue)/Float(diretArray.count)
}


