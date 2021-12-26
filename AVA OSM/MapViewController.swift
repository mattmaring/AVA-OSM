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

// MARK: - MapViewController
class MapViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate {

    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var container: UIView!
//    @IBOutlet weak var modeText: UILabel!
//    @IBAction func switchMode(_ sender: Any) {
//        if (sender as AnyObject).isOn == true {
//            Debug.sharedInstance.modeText = "User"
//        } else {
//            Debug.sharedInstance.modeText = "Driver"
//        }
//    }
    @IBAction func navigate(_ sender: Any) {
        container.isHidden = false
        mapView.isHidden = true
        updateDirections()
    }
    
    var locationManager = CLLocationManager()
    var navigationDirections: [NavigationDirection] = []
    var routeResponse: RouteResponse?
    
    // OpenRouteService API
    //let origin = CLLocationCoordinate2D(latitude: 44.896792244693884, longitude: -68.6725158170279)
    let destination = CLLocationCoordinate2D(latitude: 44.56320, longitude: -69.66136)
    //let destination = CLLocationCoordinate2D(latitude: 44.90012957373266, longitude: -68.67127501997854)
    var routeOptions = NavigationRouteOptions(waypoints: [])
    
    // MARK: - viewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.showsBuildings = true
        mapView.userTrackingMode = .followWithHeading
        
        container.isHidden = true
        
        locationManager.requestAlwaysAuthorization()
        if (CLLocationManager.locationServicesEnabled()) {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }
        
        //mapView.camera = MKMapCamera(lookingAtCenter: locationManager.location!.coordinate, fromDistance: 1.0, pitch: 75.0, heading: locationManager.location!.course)
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
        if let curLocation = locationManager.location?.coordinate {
            let origin = Waypoint(coordinate: curLocation, name: "Current Location")
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
        }
    }
    
    func presentDirections() {
        guard let routeResponse = routeResponse else { return }
        
        // Since first route is retrieved from response `routeIndex` is set to 0.
        let navigationService = MapboxNavigationService(routeResponse: routeResponse, routeIndex: 0, routeOptions: routeOptions)
        let navigationOptions = NavigationOptions(styles: [CustomStyle()], navigationService: navigationService)
        let navigationViewController = NavigationViewController(for: routeResponse, routeIndex: 0, routeOptions: routeOptions, navigationOptions: navigationOptions)
        navigationViewController.routeLineTracksTraversal = true
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
    
    // MARK: - locationManager
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        //updateDirections()
    }
    
    // MARK: - mapView
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(polyline: overlay as! MKPolyline)
        renderer.strokeColor = UIColor.blue
        renderer.lineWidth = 2.0
        return renderer
    }
}

extension MapViewController: NavigationViewControllerDelegate {
    func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
        navigationController?.popViewController(animated: true)
    }
}
