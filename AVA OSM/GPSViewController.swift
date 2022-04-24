//
//  GPSViewController.swift
//  AVA OSM
//
//  Created by Matt Maring on 3/10/22.
//

import UIKit
import CoreLocation
import simd
import MapKit
import SceneKit
import AVFoundation
import os.log
import ARKit

class GPSViewController: UIViewController, CLLocationManagerDelegate, ARSCNViewDelegate, ARSessionDelegate {
    
    // MARK: - `IBOutlet` instances
    @IBOutlet weak var directionDescriptionLabel: UILabel!
    @IBOutlet weak var arrowImage: UIImageView!
    @IBOutlet weak var circleImage: UIImageView!
    @IBOutlet weak var sceneView: ARSCNView!
    
    @IBAction func cancelAction(_ sender: Any) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func alertAction(_ sender: Any) {
        print("Honk Car Horn!")
    }
    
    // MARK: - Class variables
    var arrived = false
    var locationManager = CLLocationManager()
    var circleImageSize = CGSize()
    
    // MARK: - Speech
    var speechSynthesizer = AVSpeechSynthesizer()
    var speechArray = ["searching for car",
                       "light too low",
                       "calibrating sensor, please rotate in-place to capture direction information",
                       "connected",
                       "disconnected",
                       ""]
    var activeState : Int? = Optional.none
    var prevText : String? = Optional.none
    
    // MARK: - Variables
    // Timers
    weak var hapticFeedbackTimer: Timer?
    weak var audioTimer: Timer?
    var timeInterval = 0.01
    var timerCounter: Float = 0.0
    
    // Default values
    let CLOSE_RANGE : Float = 2.0 / 3.0
    var thresholdValue : Float = 90.0
    
    // GPS location storage
    var car_distance : Float? = Optional.none
    var car_yaw : Float? = Optional.none
    var destination = CLLocation(latitude: 44.56320, longitude: -69.66136)
    var prevDirection : Float? = Optional.none
    
    //var distanceFilter = KalmanFilter(stateEstimatePrior: 0.0, errorCovariancePrior: 1)
    
    // MARK: - Text formmatting
    let attributes1 = [NSAttributedString.Key.font : UIFont.systemFont(ofSize: 50, weight: UIFont.Weight.bold), NSAttributedString.Key.foregroundColor : UIColor.label] //primary
    let attributes2 = [NSAttributedString.Key.font : UIFont.systemFont(ofSize: 50, weight: UIFont.Weight.semibold), NSAttributedString.Key.foregroundColor : UIColor.secondaryLabel] //secondary
    
    // MARK: - Logging
    let dateFormat = DateFormatter()
    var outputLog : OutputLog?
    var experiment : String? = Optional.none
    var experimentIDTitle : String? = Optional.none
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        dateFormat.dateFormat = "y-MM-dd H:m:ss.SSSS"
        
        outputLog = OutputLog("\(String(describing: experimentIDTitle)) - \(String(describing: experiment))")
        
        outputLog?.write("\(dateFormat.string(from: Date())), Starting Experiment\n")
        outputLog?.write("\(dateFormat.string(from: Date())), Participant: \(String(describing: experimentIDTitle))\n")
        outputLog?.write("\(dateFormat.string(from: Date())), Trial: \(String(describing: experiment))\n")
        
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
            
            prevText = ""
        }
        
        arrowImage.isHidden = true
        circleImage.isHidden = true
        
        sceneView.session.delegate = self
        
        let blur = UIBlurEffect(style: .systemMaterialDark)
        let blurView = UIVisualEffectView(effect: blur)
        blurView.frame = sceneView.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.addSubview(blurView)
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.worldAlignment = .gravityAndHeading
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration)
        
        // Initialize visualizations
        let attributedString1 = NSMutableAttributedString(string: "\n-.--", attributes: attributes1)
        let attributedString2 = NSMutableAttributedString(string: " ft", attributes: attributes2)
        
        attributedString1.append(attributedString2)
        
        directionDescriptionLabel.attributedText = attributedString1
        
        updateVisualization()
    }
    
    deinit {
        hapticFeedbackTimer?.invalidate()
        audioTimer?.invalidate()
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
    }
    
    // MARK: - Update GPS Directions
    
    func updateDirections() {
        outputLog?.write("\(dateFormat.string(from: Date())), Accuracy: \(String(describing: locationManager.location?.horizontalAccuracy))\n")
        
        // Update distance
        if let distance = locationManager.location?.distance(from: destination) {
            car_distance = Float(distance)
        } else {
            car_distance = nil
        }

        // Update direction
        if let coordinate = locationManager.location?.coordinate {
            car_yaw = haversine(from: destination.coordinate, to: coordinate)
        } else {
            car_yaw = nil
        }

        if let heading = locationManager.heading?.trueHeading {
            if car_yaw != nil && car_yaw! < 0.0 {
                let result = car_yaw! + 180.0 - Float(heading)
                if result < -180.0 {
                    car_yaw = 360.0 + result
                } else {
                    car_yaw = result
                }
            } else if car_yaw != nil {
                let result = car_yaw! - 180.0 - Float(heading)
                if result < -180.0 {
                    car_yaw = 360.0 + result
                } else {
                    car_yaw = result
                }
            } else {
                car_yaw = nil
            }
        } else {
            car_yaw = nil
        }
        
        if prevDirection != nil && car_yaw != nil && car_distance! > CLOSE_RANGE {
            if abs(prevDirection!) >= 10.0 && abs(car_yaw!) < 10.0 {
                pointingTap()
            }
        }
        prevDirection = car_yaw
        
        if car_distance != nil && car_distance! < CLOSE_RANGE {
            timeInterval = getTimeInterval(distance: car_distance!)
            if ((hapticFeedbackTimer?.isValid) == nil || !hapticFeedbackTimer!.isValid) {
                hapticFeedbackTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: #selector(closeTap), userInfo: nil, repeats: true)
            }
        } else {
            hapticFeedbackTimer?.invalidate()
        }
        updateVisualization()
        
        outputLog?.write("\(dateFormat.string(from: Date())), \(String(describing: car_distance)), \(String(describing: car_yaw))\n")
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
    
    func pointingTap() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred()
        generator.impactOccurred()
        generator.impactOccurred()
        outputLog?.write("\(dateFormat.string(from: Date())), pointingTap\n")
    }
    
    @objc func closeTap() {
        timerCounter += 0.01
        if timerCounter >= Float(timeInterval) {
            timerCounter = 0.0
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
        }
        outputLog?.write("\(dateFormat.string(from: Date())), closeTap\n")
    }
    
    // MARK: - Visualizations
    
    func directionNaturalLanguage(degrees: Float) -> (String, String, String) {
        if degrees >= -165.0 && degrees < -135.0 {
            return ("at", "7", "o'clock")
        } else if degrees >= -135.0 && degrees < -105.0 {
            return ("at", "8", "o'clock")
        } else if degrees >= -105.0 && degrees < -75.0 {
            return ("at", "9", "o'clock")
        } else if degrees >= -75.0 && degrees < -45.0 {
            return ("at", "10", "o'clock")
        } else if degrees >= -45.0 && degrees < -15.0 {
            return ("at", "11", "o'clock")
        } else if degrees >= -15.0 && degrees <= 15.0 {
            return ("at", "12", "o'clock")
        } else if degrees > 15.0 && degrees <= 45.0 {
            return ("at", "1", "o'clock")
        } else if degrees > 45.0 && degrees <= 75.0 {
            return ("at", "2", "o'clock")
        } else if degrees > 75.0 && degrees <= 105.0 {
            return ("at", "3", "o'clock")
        } else if degrees > 105.0 && degrees <= 135.0 {
            return ("at", "4", "o'clock")
        } else if degrees > 135.0 && degrees <= 165.0 {
            return ("at", "5", "o'clock")
        } else {
            return ("at", "6", "o'clock")
        }
    }
    
    func audioHandle(index: Int) {
        if activeState != nil {
            if activeState != index {
                speechSynthesizer.stopSpeaking(at: .immediate)
            } else {
                return
            }
        }
        
        // Disconnect
        if index == 4 {
            prevText = nil
        }
        
        let utterance = AVSpeechUtterance(string: speechArray[index])
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        //utterance.rate = 1. 0
        speechSynthesizer.speak(utterance)
        activeState = index
    }
    
    func readDistance() {
        if activeState != nil {
            activeState = nil
        }
        if let string = directionDescriptionLabel.text {
            speechSynthesizer.stopSpeaking(at: .word)
            let utterance = AVSpeechUtterance(string: string)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            //utterance.rate = 1.0
            speechSynthesizer.speak(utterance)
        }
    }
    
    func updateVisualization() {
        if arrived {
            hapticFeedbackTimer?.invalidate()
            circleImage.isHidden = true
            arrowImage.isHidden = true
            directionDescriptionLabel.attributedText = NSMutableAttributedString(string: "Arrived at car", attributes: attributes1)
            outputLog?.write("\(dateFormat.string(from: Date())), Arrived at car\n")
            return
        }
        
        if let distance = car_distance {
            var format = "%0.0f"
            if distance < CLOSE_RANGE {
                format = "%0.1f"
            }
            var _distance = distance * 3.280839895
            if _distance >= 100.0 {
                _distance = Float(Int(_distance / 10.0) * 10)
            } else if distance >= 30 {
                _distance = Float(Int(_distance / 5.0) * 5)
            }
            let distanceFill = String(format: format, _distance)
            if distance < 1.0 / 3.0 {
                let attributedString1 = NSMutableAttributedString(string: "Within ", attributes: attributes2)
                let attributedString2 = NSMutableAttributedString(string: "1 ", attributes: attributes1)
                let attributedString3 = NSMutableAttributedString(string: "foot\n", attributes: attributes2)
                
                attributedString1.append(attributedString2)
                attributedString1.append(attributedString3)
                
                directionDescriptionLabel.attributedText = attributedString1
                
                circleImage.isHidden = false
                circleImage.bounds.size = CGSize(width: CGFloat(0.5) * circleImageSize.width, height: CGFloat(0.5) * circleImageSize.height)
            } else if distance < CLOSE_RANGE {
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
                if let yaw = car_yaw {
                    let desc = directionNaturalLanguage(degrees: yaw)
                    let attributedString1 = NSMutableAttributedString(string: "\(distanceFill) ", attributes: attributes1)
                    let attributedString2 = NSMutableAttributedString(string: "ft\n\(desc.0)", attributes: attributes2)
                    let attributedString3 = NSMutableAttributedString(string: " \(desc.1)", attributes: attributes1)
                    let attributedString4 = NSMutableAttributedString(string: " \(desc.2)", attributes: attributes2)
                    
                    attributedString1.append(attributedString2)
                    attributedString1.append(attributedString3)
                    attributedString1.append(attributedString4)
                    
                    directionDescriptionLabel.attributedText = attributedString1
                } else {
                    let attributedString1 = NSMutableAttributedString(string: "\(distanceFill) ", attributes: attributes1)
                    let attributedString2 = NSMutableAttributedString(string: "ft", attributes: attributes2)
                    
                    attributedString1.append(attributedString2)
                    
                    directionDescriptionLabel.attributedText = attributedString1
                }
                circleImage.isHidden = true
            }
            if let text = prevText, text != directionDescriptionLabel.text {
                readDistance()
                outputLog?.write("\(dateFormat.string(from: Date())), \(String(describing: directionDescriptionLabel))\n")
                prevText = directionDescriptionLabel.text
            }
        } else {
            let attributedString1 = NSMutableAttributedString(string: "\n-.--", attributes: attributes1)
            let attributedString2 = NSMutableAttributedString(string: " ft", attributes: attributes2)
            
            attributedString1.append(attributedString2)
            
            directionDescriptionLabel.attributedText = attributedString1
            outputLog?.write("\(dateFormat.string(from: Date())), \(String(describing: directionDescriptionLabel))\n")
            circleImage.isHidden = true
        }
        
        if let yaw = car_yaw, circleImage.isHidden {
            arrowImage.isHidden = false
            arrowImage.transform = arrowImage.transform.rotated(by: (CGFloat(yaw) - atan2(arrowImage.transform.b, arrowImage.transform.a).radiansToDegrees).degreesToRadians)
        } else {
            arrowImage.isHidden = true
        }
    }
    
    // MARK: AVSpeechSynthesizer
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speechSynthesizer.stopSpeaking(at: .immediate)
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
