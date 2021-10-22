//
//  MapViewController.swift
//  AVA OSM
//
//  Created by Matt Maring on 7/12/21.
//

import UIKit
import MapKit
import CoreLocation

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

// MARK: - MapViewController
class MapViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate {

    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var modeText: UILabel!
    @IBAction func switchMode(_ sender: Any) {
        if (sender as AnyObject).isOn == true {
            Debug.sharedInstance.modeText = "User"
        } else {
            Debug.sharedInstance.modeText = "Driver"
        }
    }
    @IBOutlet weak var navigationDescription: UILabel!
    
    var locationManager = CLLocationManager()
    var navigationDirections: [NavigationDirection] = []
    
    // OpenRouteService API
    let destination = CLLocationCoordinate2D(latitude: 44.563138, longitude: -69.661305)
    
    // MARK: - viewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        
        mapView.delegate = self
        mapView.showsUserLocation = true
        
        locationManager.requestAlwaysAuthorization()
        if (CLLocationManager.locationServicesEnabled()) {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }
        
        navigationDescription.text = "Calculating route..."
        
        updateDirections()
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
//        let request = MKDirections.Request()
//        request.source = MKMapItem.forCurrentLocation()
//        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 44.563138, longitude: -69.661305)))
//        request.requestsAlternateRoutes = false
//        request.transportType = .walking
//
//        let directions = MKDirections(request: request)
//
//        directions.calculate { [unowned self] response, error in
//            guard let unwrappedResponse = response else { return }
//
//            for route in unwrappedResponse.routes {
//                mapView.addOverlay(route.polyline)
//                mapView.setVisibleMapRect(route.polyline.boundingMapRect, animated: true)
//                navigationDirections = []
//                for step in route.steps {
//                    let distance = NavigationDistance(meters: step.distance, feet: step.distance * 3.280839895)
//                    navigationDirections.append(NavigationDirection(description: step.instructions, distance: distance))
//                    print(step.instructions, distance.feet)
//                }
//
//            }
//            navigationDescription.text = navigationDirections.first?.description
//        }
        if let curLocation = locationManager.location?.coordinate, let path = Bundle.main.path(forResource: "Keys", ofType: "plist"), let keys = NSDictionary(contentsOfFile: path), let api_key = keys["openrouteservice"] as? String {
            guard let url = URL(string: "https://api.openrouteservice.org/v2/directions/foot-walking?api_key=\(api_key)&start=\(curLocation.longitude),\(curLocation.latitude)&end=\(destination.longitude),\(destination.latitude)") else { return }
            var request = URLRequest(url: url)
            request.addValue("application/json, application/geo+json, application/gpx+xml, img/png; charset=utf-8", forHTTPHeaderField: "Accept")
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let _ = response, let data = data {
                    let decoder = JSONDecoder()
                    if #available(iOS 10.0, OSX 10.12, tvOS 10.0, watchOS 3.0, *) {
                        decoder.dateDecodingStrategy = .iso8601
                    }
                    let navigation = try? decoder.decode(Navigation.self, from: data)
                    print(navigation?.bbox)
                } else {
                    print(error ?? "error")
                }
            }
            task.resume()
        }
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
