//
//  MapViewController.swift
//  AVA OSM
//
//  Created by Matt Maring on 7/12/21.
//

import UIKit
import MapKit
import CoreLocation
import MapboxDirections
import MapboxCoreNavigation
import MapboxNavigation
import MapboxMaps
import AVFoundation

// MARK: - Navigation
struct Navigation: Codable {
    let type: String
    let features: [Feature]
    let bbox: [Double]
    let metadata: Metadata
}

// MARK: - Feature
struct Feature: Codable {
    let bbox: [Double]
    let type: String
    let properties: Properties
    let geometry: Geometry
}

// MARK: - Geometry
struct Geometry: Codable {
    let coordinates: [[Double]]
    let type: String
}

// MARK: - Properties
struct Properties: Codable {
    let segments: [Segment]
    let summary: Summary
    let wayPoints: [Int]

    enum CodingKeys: String, CodingKey {
        case segments, summary
        case wayPoints = "way_points"
    }
}

// MARK: - Segment
struct Segment: Codable {
    let distance, duration: Double
    let steps: [Step]
}

// MARK: - Step
struct Step: Codable {
    let distance, duration: Double
    let type: Int
    let instruction, name: String
    let wayPoints: [Int]

    enum CodingKeys: String, CodingKey {
        case distance, duration, type, instruction, name
        case wayPoints = "way_points"
    }
}

// MARK: - Summary
struct Summary: Codable {
    let distance, duration: Double
}

// MARK: - Metadata
struct Metadata: Codable {
    let attribution, service: String
    let timestamp: Int
    let query: Query
    let engine: Engine
}

// MARK: - Engine
struct Engine: Codable {
    let version: String
    let buildDate, graphDate: Date

    enum CodingKeys: String, CodingKey {
        case version
        case buildDate = "build_date"
        case graphDate = "graph_date"
    }
}

// MARK: - Query
struct Query: Codable {
    let coordinates: [[Double]]
    let profile, format: String
}

// MARK: - Global variables
class Debug {
    var modeText = "User"
    static let sharedInstance: Debug = {
        let instance = Debug()
        return instance
    }()
    
    private init() {}
    
    func setMode(mode: String) {
        modeText = mode
    }
    
    func getMode() -> String {
        return modeText
    }
}

// MARK: - Navigation structs
struct NavigationDistance {
    var meters: CLLocationDistance
    var feet: CLLocationDistance
}

struct NavigationDirection {
    var description: String
    var distance: NavigationDistance
}

// MARK: - Mapbox style
class CustomStyle: DayStyle {
    required init() {
        super.init()
        mapStyleURL = URL(string: "mapbox://styles/mapbox/dark-v10")!
        styleType = .night
    }

    override func apply() {
        super.apply()
        //BottomBannerView.appearance().backgroundColor = .black
    }
}

enum State {
    case normal
    case navigating
    case sensing
}

// MARK: - MapViewController
class MapViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate, AVSpeechSynthesizerDelegate {
    
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var container: UIView!
//    @IBOutlet weak var modeText: UILabel!
//    @IBAction func switchMode(_ sender: Any) {
//        if (sender as AnyObject).isOn == true {
//            Debug.sharedInstance.modeText = "User"
//        } else {
//            Debug.sharedInstance.modeText = "Driver"
//        }
//    }
    @IBOutlet weak var navigateButton: UIButton!
    @IBAction func navigate(_ sender: Any) {
        container.isHidden = false
        textView.isHidden = true
        updateDirections()
    }
    @IBOutlet weak var poisButton: UIButton!
    @IBAction func pointsOfInterest(_ sender: Any) {
        let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let tableViewController = storyBoard.instantiateViewController(withIdentifier: "TableViewController") as! TableViewController
        tableViewController.destination = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        tableViewController.modalPresentationStyle = .fullScreen
        self.present(tableViewController, animated: true, completion: nil)
    }
    @IBOutlet weak var trackerButton: UIButton!
    @IBAction func tracker(_ sender: Any) {
        let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let trackerViewController = storyBoard.instantiateViewController(withIdentifier: "TrackerViewController") as! TrackerViewController
        trackerViewController.destination = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        trackerViewController.experiment = experiment
        trackerViewController.experimentIDTitle = experimentIDTitle
        trackerViewController.modalPresentationStyle = .fullScreen
        self.present(trackerViewController, animated: true, completion: nil)
    }
    
    var locationManager = CLLocationManager()
    var navigationDirections: [NavigationDirection] = []
    var routeResponse: RouteResponse?
    
    // OpenRouteService API
    var origin = CLLocationCoordinate2D(latitude: 44.56446, longitude: -69.65968)
    var destination = CLLocationCoordinate2D(latitude: 44.56319, longitude: -69.66056)
    var routeOptions = NavigationRouteOptions(waypoints: [])
    
//    let exit_ref_spatial = "rear"
//    let building_nickname = "Davis"
//    let parking_direction = "straight ahead"
//    let parking_distance = "15 feet"
//    let parking_type = "accessible space"
//    let exit_ref_spatial = "side"
//    let building_nickname = "Carnegie Hall"
//    let parking_direction = "left"
//    let parking_distance = "300 feet"
//    let parking_type = "circular driveway in front of Penobscot Hall"
    
    // MARK: - Speech
    var speechSynthesizer = AVSpeechSynthesizer()
    
    let pois = ["in 10 ft, there is a ramp straight ahead",
                "in 8 ft, there is a bench on your left",
                "in 9 ft, there is a tree close by to the right of the sidewalk"]
    let coordinates = [CLLocation(latitude: 44.56432772532755, longitude: -69.65980729473644),
                       CLLocation(latitude: 44.56386405963009, longitude: -69.66041628267189),
                       CLLocation(latitude: 44.56350224523806, longitude: -69.66050750082678)]
    var currentPOI = 0
    
    let contrastLabel = UIColor(named: "contrastLabelColor")
    
    // MARK: - Logging
    let dateFormat = DateFormatter()
    var outputLog : OutputLog?
    var experiment : String? = Optional.none
    var experimentIDTitle : String? = Optional.none
    
    // MARK: - viewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        
//        navigateButton.tintColor = .label
//        poisButton.tintColor = .label
//        trackerButton.tintColor = .label
//
//        navigateButton.setTitleColor(.systemBackground, for: .normal)
//        poisButton.setTitleColor(.systemBackground, for: .normal)
//        trackerButton.setTitleColor(.systemBackground, for: .normal)
//
//        view.addSubview(navigateButton)
//        view.addSubview(poisButton)
//        view.addSubview(trackerButton)
        
        outputLog = OutputLog("\(String(describing: experimentIDTitle)) - \(String(describing: experiment))")
        
        outputLog?.write("\(dateFormat.string(from: Date())), Starting Experiment\n")
        outputLog?.write("\(dateFormat.string(from: Date())), Participant: \(String(describing: experimentIDTitle))\n")
        outputLog?.write("\(dateFormat.string(from: Date())), Trial: \(String(describing: experiment))\n")
        
        speechSynthesizer.delegate = self
        
        let utterance = AVSpeechUtterance(string: "Your vehicle has arrived to the Eustis Parking Lot! Upon exiting the front entrance of Davis, your autonomous vehicle is located approximately 600ft away at 12 o'clock from your position. Please hold the smartphone in portrait mode with the rear facing camera pointed forward so that navigation guidance can be provided.")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        //utterance.rate = 1.0
        speechSynthesizer.speak(utterance)
        
        container.isHidden = true
        //poisTextView.isHidden = true
        textView.isHidden = false
        
//        textView.text = "Upon exiting from the \(exit_ref_spatial) entrance of \(building_nickname), your autonomous vehicle is located \(parking_distance) to the \(parking_direction) in the \(parking_type). Use the sensor naviagtion to locate the rear driver side door handle."
        
        textView.text = "Your vehicle has arrived to the Eustis Parking Lot! Upon exiting the front entrance of Davis, your autonomous vehicle is located approximately 600ft away at 12 o'clock from your position. Please hold the smartphone in portrait mode with the rear facing camera pointed forward so that navigation guidance can be provided."
        
        locationManager.requestAlwaysAuthorization()
        if (CLLocationManager.locationServicesEnabled()) {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }
        
        //mapView.camera = MKMapCamera(lookingAtCenter: locationManager.location!.coordinate, fromDistance: 1.0, pitch: 75.0, heading: locationManager.location!.course)
    }
    
//    override func viewWillAppear(_ animated: Bool) {
//        container.isHidden = true
//    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = manager.location, currentPOI < pois.count {
            if location.distance(from: coordinates[currentPOI]) < 4.0 {
                let utterance = AVSpeechUtterance(string: pois[currentPOI])
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                //utterance.rate = 1.0
                speechSynthesizer.speak(utterance)
                currentPOI += 1
            }
        }
    }
    
    func newJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        if #available(iOS 10.0, OSX 10.12, tvOS 10.0, watchOS 3.0, *) {
            decoder.dateDecodingStrategy = .iso8601
        }
        return decoder
    }
    
    // MARK: - updateDirections
    func updateDirections() {
        if let curLocation = locationManager.location {
//            if curLocation.distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)) < 10.0 {
//                let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
//                let trackerViewController = storyBoard.instantiateViewController(withIdentifier: "TrackerViewController") as! TrackerViewController
//                trackerViewController.destination = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
//                trackerViewController.modalPresentationStyle = .fullScreen
//                self.present(trackerViewController, animated: true, completion: nil)
//            } else {
            let origin = Waypoint(coordinate: curLocation.coordinate, name: "Current Location")
            //let origin = Waypoint(coordinate: origin, name: "Current Location")
            let destination = Waypoint(coordinate: destination, name: "Autonomous Vehicle")
            
            routeOptions = NavigationRouteOptions(waypoints: [origin, destination])
            routeOptions.profileIdentifier = .walking
            routeOptions.includesAlternativeRoutes = false
            routeOptions.includesVisualInstructions = true
            Directions.shared.calculate(routeOptions) { [weak self] (session, result) in
                switch result {
                case .failure(let error):
                    print(error.localizedDescription)
                case .success(let response):
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.routeResponse = response
                    strongSelf.presentDirections()
                }
            }
            //}
        }
    }
    
    func presentDirections() {
        guard let routeResponse = routeResponse else { return }
        
        container.isHidden = false
        textView.isHidden = true
        //poisTextView.isHidden = false
        
        //poisTextView.text = pois[currentPOI]
        
        // Since first route is retrieved from response `routeIndex` is set to 0.
        let navigationService = MapboxNavigationService(routeResponse: routeResponse, routeIndex: 0, routeOptions: routeOptions)
        let navigationOptions = NavigationOptions(styles: [CustomStyle()], navigationService: navigationService)
        let navigationViewController = NavigationViewController(for: routeResponse, routeIndex: 0, routeOptions: routeOptions, navigationOptions: navigationOptions)
        navigationViewController.routeLineTracksTraversal = true
        navigationViewController.detailedFeedbackEnabled = true
        navigationViewController.navigationMapView?.userLocationStyle = .courseView()
        
        navigationViewController.delegate = self
        addChild(navigationViewController)
        container.addSubview(navigationViewController.view)
        navigationViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navigationViewController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
            navigationViewController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0),
            navigationViewController.view.topAnchor.constraint(equalTo: container.topAnchor, constant: 0),
            navigationViewController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: 0)
        ])
        self.didMove(toParent: self)
    }
}

extension MapViewController: NavigationViewControllerDelegate {
    func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
        navigationController?.popViewController(animated: true)
        container.isHidden = true
        //poisTextView.isHidden = true
        textView.isHidden = false
    }
}
