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
import KalmanFilter

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
    
    @IBAction func cancelAction(_ sender: Any) {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        
        sceneView.session.pause()
        
        connectionTimer.invalidate()
        hapticFeedbackTimer?.invalidate()
        
        // Ask the accessory to stop.
        sendDataToAccessory(Data([MessageId.stop.rawValue]))
        
        dataChannel = DataCommunicationChannel()
        
        // Replace the invalidated session with a new one.
        session = NISession()
        session.delegate = self
        
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func alertAction(_ sender: Any) {
        print("Honk Car Horn!")
    }
    
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
    var searching = true
    var calibrating = false
    var lightTooLow = false
    var locationManager = CLLocationManager()
    var circleImageSize = CGSize()
    let speechSynthesizer = AVSpeechSynthesizer()
    
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
    let CLOSE_RANGE: Float = 1.0
    
    // MARK: - Car location
    var destination = CLLocation(latitude: 44.56320, longitude: -69.66136)
    
    // GPS location storage
    var car_distance: Float = 999999.0
    var car_yaw: Float = 999.0
    
    // uwb location storage
    var uwb_distance : Float = 999999.0
    var uwb_yaw : Float = 999.0
    var uwb_pitch : Float = 999.0
    var last_position = SCNVector3()
    
    var distanceFilter = KalmanFilter(stateEstimatePrior: 0.0, errorCovariancePrior: 1)
    
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
        
        updateVisualization()
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
        if uwbConnectionActive == false {
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
        //updateDirections()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        //updateDirections()
//        if let accessory = storedObject, uwbConnectionActive {
//            updateObject(accessory: accessory)
//        }
    }
    
    // MARK: - Update GPS Directions
    
//    func updateDirections() {
//        // Update distance
//        if let distance = locationManager.location?.distance(from: destination) {
//            car_distance = Float(distance)
//        } else {
//            car_distance = DIST_MAX
//        }
//
//        // Update direction
//        if let coordinate = locationManager.location?.coordinate {
//            car_yaw = haversine(from: destination.coordinate, to: coordinate)
//        } else {
//            car_yaw = YAW_MAX
//        }
//
//        if let heading = locationManager.heading?.trueHeading {
//            if car_yaw < 0.0 {
//                let result = car_yaw + 180.0 - Float(heading)
//                if result < -180.0 {
//                    car_yaw = 360.0 + result
//                } else {
//                    car_yaw = result
//                }
//            } else if car_yaw != YAW_MAX {
//                let result = car_yaw - 180.0 - Float(heading)
//                if result < -180.0 {
//                    car_yaw = 360.0 + result
//                } else {
//                    car_yaw = result
//                }
//            } else {
//                car_yaw = YAW_MAX
//            }
//        } else {
//            car_yaw = YAW_MAX
//        }
//
//        if uwbConnectionActive == false {
//            if car_distance < CLOSE_RANGE {
//                timeInterval = getTimeInterval(distance: car_distance)
//                if ((hapticFeedbackTimer?.isValid) == nil || !hapticFeedbackTimer!.isValid) {
//                    hapticFeedbackTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(closeTap), userInfo: nil, repeats: true)
//                }
//            } else {
//                hapticFeedbackTimer?.invalidate()
//            }
//            updateVisualization(distance: car_distance, yaw: car_yaw)
//            renderingOutput += "\(dateFormat.string(from: Date())), \(car_distance), \(car_yaw)\n"
//            //print("\(dateFormat.string(from: Date())), \(car_distance), \(car_yaw)")
//            if let stringData = renderingOutput.data(using: .utf8) {
//                try? stringData.write(to: renderingPath!)
//            }
//
//            if let location = locationManager.location {
//                let coordinate = location.coordinate
//                coreLocationOutput += "\(dateFormat.string(from: Date())), \(car_distance * 3.280839895), \(car_yaw), \(coordinate.longitude), \(coordinate.latitude), \(location.altitude), \(location.course), \(location.speed), \(location.horizontalAccuracy), \(location.verticalAccuracy), \(location.horizontalAccuracy), \(location.speedAccuracy)\n"
//            }
//            if let stringData = coreLocationOutput.data(using: .utf8) {
//                try? stringData.write(to: coreLocationPath!)
//            }
//        }
//    }
    
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
    
    @objc func pointingTap() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        if hapticToggle.isOn {
            generator.impactOccurred()
        }
    }
    
    @objc func closeTap() {
        timerCounter += 0.01
        if timerCounter >= Float(timeInterval) {
            timerCounter = 0.0
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            if hapticToggle.isOn {
                generator.impactOccurred()
            }
        }
    }
    
    // MARK: - ARSession
    
    func addBox() {
        print("called add box")
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
        
        updateObject()
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
    
    func updateVisualization() {
        if arrived {
            hapticFeedbackTimer?.invalidate()
            circleImage.isHidden = true
            arrowImage.isHidden = true
            directionDescriptionLabel.attributedText = NSMutableAttributedString(string: "Arrived at car", attributes: attributes1)
            return
        } else if lightTooLow {
            hapticFeedbackTimer?.invalidate()
            circleImage.isHidden = true
            arrowImage.isHidden = true
            directionDescriptionLabel.attributedText = NSMutableAttributedString(string: "Light too low", attributes: attributes1)
            return
        } else if calibrating {
            hapticFeedbackTimer?.invalidate()
            circleImage.isHidden = true
            arrowImage.isHidden = true
            directionDescriptionLabel.attributedText = NSMutableAttributedString(string: "Calibrating", attributes: attributes1)
            return
        } else if searching {
            hapticFeedbackTimer?.invalidate()
            circleImage.isHidden = true
            arrowImage.isHidden = true
            directionDescriptionLabel.attributedText = NSMutableAttributedString(string: "Searching for car", attributes: attributes1)
            return
        }
        
        if uwb_distance < DIST_MAX {
            var format = "%0.0f"
            if uwb_distance < CLOSE_RANGE {
                format = "%0.1f"
            }
            let distanceFill = String(format: format, uwb_distance * 3.280839895)
            if uwb_distance < CLOSE_RANGE {
                let attributedString1 = NSMutableAttributedString(string: "\(distanceFill) ", attributes: attributes1)
                let attributedString2 = NSMutableAttributedString(string: "ft\n", attributes: attributes2)
                let attributedString3 = NSMutableAttributedString(string: "nearby", attributes: attributes1)
                
                attributedString1.append(attributedString2)
                attributedString1.append(attributedString3)
                
                directionDescriptionLabel.attributedText = attributedString1
                
                circleImage.isHidden = false
                let scale = CGFloat(uwb_distance / CLOSE_RANGE / 2.0 + 0.5)
                circleImage.bounds.size = CGSize(width: scale * circleImageSize.width, height: scale * circleImageSize.height)
            } else {
                if uwb_yaw < YAW_MAX {
                    let desc = directionNaturalLanguage(degrees: uwb_yaw)
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
        
        if uwb_yaw < YAW_MAX && circleImage.isHidden {
            arrowImage.isHidden = false
            arrowImage.transform = arrowImage.transform.rotated(by: (CGFloat(uwb_yaw) - atan2(arrowImage.transform.b, arrowImage.transform.a).radiansToDegrees).degreesToRadians)
        } else {
            arrowImage.isHidden = true
        }
    }
    
    // MARK: AVSpeechSynthesizer
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speechSynthesizer.stopSpeaking(at: .word)
    }
    
    // MARK: - NISessionDelegate
    
    func azimuth(from direction: simd_float3) -> Float {
        return asin(direction.x)
    }

    // Provides the elevation from the argument 3D directional.
    func elevation(from direction: simd_float3) -> Float {
        return atan2(direction.z, direction.y) + .pi / 2
    }
    
    func session(_ session: NISession, didGenerateShareableConfigurationData shareableConfigurationData: Data, for object: NINearbyObject) {
        guard object.discoveryToken == configuration?.accessoryDiscoveryToken else { return }

        // Prepare to send a message to the accessory.
        var msg = Data([MessageId.configureAndStart.rawValue])
        msg.append(shareableConfigurationData)

        //let str = msg.map { String(format: "0x%02x, ", $0) }.joined()

        // Send the message to the accessory.
        sendDataToAccessory(msg)
        
        calibrating = true
        searching = false
    }
    
    func isValidDirection(direction: simd_float3) -> Bool {
        return abs(azimuth(from: direction).radiansToDegrees) < 22.5 && abs(elevation(from: direction).radiansToDegrees) < 60.0
    }
    
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let accessory = nearbyObjects.first else { return }
        
        if !accessoryConnected { return }
        
        storedObject = accessory
        
        updateObject()
    }
    
    // MARK: - Update NINearbyObject
    
    func cubeMoved() -> Bool {
        return boxNode.transform.m41 != 0.0 || boxNode.transform.m42 != 0.0 || boxNode.transform.m43 != 0.0
    }
    
    func distance3D() -> Float {
        return sqrt(pow(currentCamera.m41 - boxNode.position.x, 2) + pow(currentCamera.m42 - boxNode.position.y, 2) + pow(currentCamera.m43 - boxNode.position.z, 2))
    }

    func updateObject() {
        if let accessory = storedObject, accessoryConnected /*&& !arrived*/ && !lightTooLow && uwbConnectionActive {
//            if iterations < 5 {
//                if let _ = accessory.distance, let direction = accessory.direction, isValidDirection(direction: direction) {
//                    iterations += 1
//                } else {
//                    let string = "calibrating sensor, please rotate in-place to capture direction information"
//                    let utterance = AVSpeechUtterance(string: string)
//                    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
//                    speechSynthesizer.speak(utterance)
//                }
//            } else if iterations == 5 {
//                speechSynthesizer.stopSpeaking(at: .immediate)
//                iterations += 1
//                calibrating = false
//                speechSynthesizer.stopSpeaking(at: .word)
//            }
            if let distance = accessory.distance, let direction = accessory.direction, isValidDirection(direction: direction) {
                calibrating = false
            }
            
            if !calibrating {
                if let distance = accessory.distance {
                    if distance == 0.0 {
                        if uwb_distance < 0.03 {
                            uwb_distance = distance
                        }
                    } else if let _ = accessory.direction {
                        uwb_distance = distance
                    } else {
                        uwb_distance = distance3D()
                    }
                    if uwb_distance == 0.0 {
                        arrived = true
                        //sendDataToAccessory(Data([MessageId.stop.rawValue]))
                        // Don't stop sending data until confirmation of arrival is made (use cancel or confirmation of arrival button)
                    } else {
                        arrived = false
                    }
                } else if cubeMoved() {
                    uwb_distance = distance3D()
                }
                
                // check if distance update is valid, cancel tracking if so
                
                // need to check if direction flips while distance stays same
                
                if let direction = accessory.direction, isValidDirection(direction: direction) {
                    let azimuth = azimuth(from: direction)
                    let elevation = elevation(from: direction)
                    
                    guard let camera = sceneView.session.currentFrame?.camera else { return }
                    boxNode.simdEulerAngles = direction
                    
                    let pov = SCNVector3(x: camera.eulerAngles.x, y: camera.eulerAngles.y, z: camera.eulerAngles.z)
                    let pitch = pov.x + elevation
                    let yaw = -pov.y + azimuth
                    
                    let y = uwb_distance * sin(pitch)
                    let _uwb_distance = sqrt(uwb_distance * uwb_distance - y * y)
                    let x = _uwb_distance * sin(yaw)
                    let z = -_uwb_distance * cos(yaw)
                    
                    //boxNode.position = SCNVector3(0, 0, 2)
                    boxNode.position = SCNVector3(currentCamera.m41 + x, currentCamera.m42 + y, currentCamera.m43 + z)
                    
                    sceneView.scene.rootNode.addChildNode(boxNode)
                    
                    uwb_yaw = azimuth.radiansToDegrees
                    uwb_pitch = elevation.radiansToDegrees
                } else if cubeMoved() {
                    guard let camera = sceneView.session.currentFrame?.camera else { return }
                    guard let position = sceneView.pointOfView?.position else { return }
                    //print(position, camera.eulerAngles.y)

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
                    
                    // Position = (-2, -1); Node = (1, 1)
                    // ∆X = 3; ∆Y = 2
                    // Angle = atan(∆Y/∆X)
                    //       = atan(2/3)
                    //         = 33.7º
                    // Should be 33.7º + 90.0º = 123.7º
                    
                    // Position = (1, 1); Node = (-2, -1)
                    // ∆X = -3; ∆Y = -2
                    // Angle = atan(∆Y/∆X)
                    //       = atan(2/3)
                    //         = 33.7º
                    // Should be 33.7º - 90.0º = -56.3º
                    
                    // error dection
                    
                    
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
                        // Catch divide by zero errors
                        if position.z < boxNode.position.z {
                            move_angle = .pi
                        } else {
                            move_angle = 0.0
                        }
                    }
                    
                    var yaw = move_angle + camera.eulerAngles.y
                    if yaw <= -.pi {
                        yaw += 2 * .pi
                    } else if yaw > .pi {
                        yaw -= 2 * .pi
                    }
                    uwb_yaw = yaw.radiansToDegrees
                }
                
                if uwb_distance < CLOSE_RANGE {
                    timeInterval = getTimeInterval(distance: uwb_distance)
                    if ((hapticFeedbackTimer?.isValid) == nil || !hapticFeedbackTimer!.isValid) {
                        hapticFeedbackTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(closeTap), userInfo: nil, repeats: true)
                    }
                } else {
                    hapticFeedbackTimer?.invalidate()
                }
            }
        }
        
        updateVisualization()
//        renderingOutput += "\(dateFormat.string(from: Date())), \(uwb_distance * 3.280839895), \(uwb_yaw)\n"
//        if let stringData = renderingOutput.data(using: .utf8) {
//            try? stringData.write(to: renderingPath!)
//        }
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
        print("trying again")
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
        let accessAlert = UIAlertController(title: "Access Required", message: "NIAccessory requires access to Nearby Interactions for this sample app. Use this string to explain to users which functionality will be enabled if they change Nearby Interactions access in Settings.", preferredStyle: .alert)
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

// MARK: - Utilities.
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


