//
//  TableViewController.swift
//  AVA OSM
//
//  Created by Matt Maring on 7/12/21.
//

import UIKit
import Foundation
import CoreLocation

// MARK: - Header
struct Header: Codable {
    let version, generator, copyright: String
    let attribution, license: String
    let bounds: Bounds
    let elements: [Element]
}

// MARK: - Bounds
struct Bounds: Codable {
    let minlat, minlon, maxlat, maxlon: Double
}

// MARK: - Element
struct Element: Codable {
    let type: TypeEnum
    let id: Int
    let lat, lon: Double?
    //let timestamp: String
    //let version, changeset: Int
    //let user: String
    //let uid: Int
    let tags: [String: String]?
    let nodes: [Int]?
    //let members: [Member]?
}

// MARK: - Member
//struct Member: Codable {
//    let type: TypeEnum
//    let ref: Int
//    let role: Role
//}

//enum Role: String, Codable {
//    case empty = ""
//    case inner = "inner"
//    case label = "label"
//    case north = "north"
//    case outer = "outer"
//    case route = "route"
//    case south = "south"
//}

enum TypeEnum: String, Codable {
    case node = "node"
    case relation = "relation"
    case way = "way"
}

enum Complexity {
    case concise
    case normal
    case verbose
}

enum Units {
    case imperial
    case metric
}

class TableViewController: UITableViewController, CLLocationManagerDelegate {
    // local settings, retrieve from AVA settings implementation later
    var units : Units = Units.imperial
    var complexity : Complexity = Complexity.normal
    var locationManager = CLLocationManager()
    var activityIndicator: UIActivityIndicatorView!
    
    // default values
    let DIST_MAX = 999999.0
    let DIR_MAX = 999.0
    
    // Car location
    let destination = CLLocation(latitude: 44.563138, longitude: -69.661305) // Example location of vehicle in Eustis Parking Lot
    var car_distance = 999999.0
    var car_direction = 999.0
    
    // Store JSON data for quick retrieval/sorting
    var nodesToLoc : [Int : CLLocation] = [:]
    var poisToName : [Int : String] = [:]
    var poisToType : [Int : String] = [:]
    var poisToNodes : [Int : [Int]] = [:]
    var poisToDist : [Int : Double] = [:]
    var poisToHead : [Int : Double] = [:]
    var names : [Dictionary<Int, String>.Element] = [] //Array has order, dictionaries do NOT
    var updatingNames = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Request permission to access location
        locationManager.requestAlwaysAuthorization()
        if (CLLocationManager.locationServicesEnabled()) {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.headingFilter = 5.0
            locationManager.distanceFilter = 1.0
            locationManager.startUpdatingLocation()
            // simulator doesn't support heading data
            if (CLLocationManager.headingAvailable()) {
                locationManager.startUpdatingHeading()
            }
        }
        
        // Show progress of loading OSM data (in AVA App load this in the background when ride is requested so POIs are available immediatley)
        activityIndicator = UIActivityIndicatorView(style: UIActivityIndicatorView.Style.large)
        activityIndicator.color = UIColor.secondaryLabel
        activityIndicator.center = self.view.center
        activityIndicator.hidesWhenStopped = true
        activityIndicator.startAnimating()
        self.view.addSubview(activityIndicator)
        
        // In actual AVA App calculate bounding box surrounding navigation area
        let location = self.locationManager.location!.coordinate
        let left : Double = location.longitude - 0.005
        let bottom : Double = location.latitude - 0.005
        let right : Double = location.longitude + 0.005
        let top : Double = location.latitude + 0.005
        queryDataInBounds(left: left, bottom: bottom, right: right, top: top)
    }
    
    // Check if the area is less than 0.25
    func checkBounds(left: Double, bottom: Double, right: Double, top: Double) -> Bool {
        return abs(left - right) * abs(top - bottom) < 0.25
    }
    
    func noDataNotify() {
        let alert = UIAlertController(title: "No Data", message: "There is no data available for the selected region", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) {_ in
            // necessary actions here
        })
        self.present(alert, animated: true)
    }
    
    func tagNaturalLanguage(tags: [String: String]) -> String {
        if (tags["building"] != nil) {
            if (tags["building"] == "yes") {
                return "Building"
            } else if (tags["building"] == "college") {
                return "College Building"
            } else {
                if let building = tags["building"] {
                    return building.capitalized
                } else {
                    return "Building"
                }
            }
        } else if (tags["amenity"]) != nil {
            if let amenity = tags["amenity"] {
                return amenity.capitalized
            } else {
                return "Amenity"
            }
        } else if (tags["highway"] != nil) {
            return "Road"
        } else {
            return ""
        }
    }
    
    func directionNaturalLanguage(degrees: Double) -> String {
        if degrees > -165 && degrees < -135 {
            return "back left"
        } else if degrees >= -135 && degrees <= -45 {
            return "to your left"
        } else if degrees > -45 && degrees < -15 {
            return "slightly left"
        } else if degrees >= -15 && degrees <= 15 {
            return "ahead"
        } else if degrees > 15 && degrees < 45 {
            return "slightly right"
        } else if degrees >= 45 && degrees <= 135 {
            return "to your right"
        } else if degrees > 135 && degrees < 165 {
            return "back right"
        } else {
            return "behind"
        }
    }
    
//    func directionNaturalLanguage(degrees: Double) -> String {
//        if degrees > -150 && degrees < -30 {
//            return "to your left"
//        } else if degrees >= -30 && degrees <= 30 {
//            return "ahead"
//        } else if degrees > 30 && degrees < 150 {
//            return "to your right"
//        } else {
//            return "behind"
//        }
//    }
    
    // Query OSM data into structs
    func queryDataInBounds(left: Double, bottom: Double, right: Double, top: Double) {
        if (!checkBounds(left: left, bottom: bottom, right: right, top: top)) {
            noDataNotify()
            return
        }
        
        guard let url = URL(string: "https://api.openstreetmap.org/api/0.6/map.json?bbox=\(left),\(bottom),\(right),\(top)") else { return }
        URLSession.shared.dataTask(with: url) { [self] (data, response, error) in
            guard let data = data else { return }
            do {
                // Fetch data and decode
                let results = try JSONDecoder().decode(Header.self, from: data).elements
                
                // Clear dictionary of old data
                self.nodesToLoc = [:]
                self.poisToName  = [:]
                self.poisToType = [:]
                self.poisToNodes = [:]
                self.poisToDist = [:]
                self.poisToHead = [:]
                
                // Loop through results and store only the necessary data
                for item in results {
                    // Store coordinates of nodes which have this data
                    if item.lat != nil && item.lon != nil {
                        if let lat = item.lat, let lon = item.lon {
                            self.nodesToLoc[item.id] = CLLocation(latitude: lat, longitude: lon)
                        } else {
                            self.nodesToLoc[item.id] = CLLocation(latitude: 0.0, longitude: 0.0)
                        }
                    }
                    
                    // Store nodes with names (to be displayed on the table)
                    if item.tags?["name"] != nil {
                        self.poisToName[item.id] = item.tags?["name"]
                        self.poisToDist[item.id] = DIST_MAX
                        self.poisToHead[item.id] = DIR_MAX
                        
                        // Natural language node description type
                        if let tags = item.tags {
                            self.poisToType[item.id] = tagNaturalLanguage(tags: tags)
                        } else {
                            self.poisToType[item.id] = ""
                        }
                    }
                    
                    // Store nodes associated with current node
                    if item.nodes != nil {
                        self.poisToNodes[item.id] = item.nodes
                    }
                }
                
                // Reload table on the main thread
                DispatchQueue.main.async {
                    self.updateNames()
                }
            } catch let err {
                print("Err ", err)
                DispatchQueue.main.async() {
                    self.noDataNotify()
                }
            }
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
            }
        }.resume()
    }
    
    // See Haversine formula for calculating bearing between two points:
    // https://en.wikipedia.org/wiki/Haversine_formula
    // https://www.igismap.com/formula-to-find-bearing-or-heading-angle-between-two-points-latitude-longitude/
    func haversine(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let deg2rad = Double.pi / 180.0
        let phi1 = from.latitude * deg2rad
        let lambda1 = from.longitude * deg2rad
        let phi2 = to.latitude * deg2rad
        let lambda2 = to.longitude * deg2rad
        let deltaLon = lambda2 - lambda1
        let result = atan2(sin(deltaLon) * cos(phi2), cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLon))
        return result * 180.0 / Double.pi
    }
    
    func updateNames() {
        if (updatingNames == true) {
            return
        }
        updatingNames = true
        if let distance = locationManager.location?.distance(from: destination) {
            car_distance = distance
            if let coordinate = locationManager.location?.coordinate {
                car_direction = haversine(from: destination.coordinate, to: coordinate)
            } else {
                car_direction = DIR_MAX
            }
        } else {
            car_distance = DIST_MAX
            car_direction = DIR_MAX
        }
        for key in poisToDist.keys {
            if let location = nodesToLoc[key] {
                if let distance = locationManager.location?.distance(from: location) {
                    poisToDist[key] = distance
                    if let coordinate = locationManager.location?.coordinate {
                        poisToHead[key] = haversine(from: location.coordinate, to: coordinate)
                    } else {
                        poisToHead[key] = DIR_MAX
                    }
                } else {
                    poisToDist[key] = DIST_MAX
                    poisToHead[key] = DIR_MAX
                }
            } else {
                poisToDist[key] = DIST_MAX
//                var minimum1 = DIST_MAX // ac
//                var location1 = CLLocation(latitude: 0.0, longitude: 0.0) // a
//                var minimum2 = DIST_MAX // bc
//                var location2 = CLLocation(latitude: 0.0, longitude: 0.0) // b
                for node in poisToNodes[key] ?? [] {
                    if let location = nodesToLoc[node] {
                        if let distance = locationManager.location?.distance(from: location) {
                            if distance < poisToDist[key] ?? DIST_MAX {
                                poisToDist[key] = distance
                                if let coordinate = locationManager.location?.coordinate {
                                    poisToHead[key] = haversine(from: location.coordinate, to: coordinate)
                                } else {
                                    poisToHead[key] = DIR_MAX
                                }
                            }
//                            if distance < minimum1 {
//                                minimum2 = minimum1
//                                location2 = location1
//                                minimum1 = distance
//                                location1 = location
//                            } else if distance < minimum2 {
//                                minimum2 = distance
//                                location2 = location
//                            }
                        }
                    }
                }
//                let minimum3 = location1.distance(from: location2) // ab
//                if minimum3 == 0.0 {
//                    poisToDist[key] = minimum2
//                } else {
//                    let theta = acos((pow(minimum3, 2) + pow(minimum2, 2) - pow(minimum1, 2)) / (2 * minimum2 * minimum3))
//                    poisToDist[key] = abs(sin(theta * 180.0 / Double.pi) * minimum2)
//                }
//                if let coordinate = locationManager.location?.coordinate {
//                    poisToHead[key] = haversine(from: location2.coordinate, to: coordinate)
//                } else {
//                    poisToHead[key] = DIR_MAX
//                }
            }
        }
        
        names = poisToName.sorted(by: { poisToDist[$0.key]! < poisToDist[$1.key]! })
        tableView.reloadData()
        updatingNames = false
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        updateNames()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        updateNames()
    }
    
    func roundFeet(distance: Double) -> Int {
        return Int(distance / 10) * 10
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if names.count > 9 {
            return 9
        } else {
            return names.count
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "POICell", for: indexPath) as! TableViewCell
        
        if indexPath.row == 0 {
            cell.isHidden = false
            cell.backgroundColor = UIColor.green
            cell.overrideUserInterfaceStyle = UIUserInterfaceStyle.light
            
            cell.descriptiveName.text = "Your Ride"
            cell.tagType.text = "Destination"
            
            if units == Units.imperial && car_distance < DIST_MAX {
                cell.distance.text = "\(roundFeet(distance: car_distance * 3.28083)) ft"
            } else if units == Units.metric && car_distance < DIST_MAX {
                cell.distance.text = "\(Int(car_distance)) m"
            } else {
                cell.distance.text = "---"
            }
            
            let heading = car_direction
            if complexity != Complexity.concise {
                if let direction = locationManager.heading?.trueHeading {
                    if heading < 0.0 {
                        let result = heading + 180.0 - direction
                        if result < -180.0 {
                            if complexity == Complexity.verbose {
                                cell.direction.text = "\(Int(360.0 + result))º"
                            } else {
                                cell.direction.text = directionNaturalLanguage(degrees: 360.0 + result)
                            }
                        } else {
                            if complexity == Complexity.verbose {
                                cell.direction.text = "\(Int(result))º"
                            } else {
                                cell.direction.text = directionNaturalLanguage(degrees: result)
                            }
                        }
                    } else if heading != DIR_MAX {
                        let result = heading - 180.0 - direction
                        if result < -180.0 {
                            if complexity == Complexity.verbose {
                                cell.direction.text = "\(Int(360.0 + result))º"
                            } else {
                                cell.direction.text = directionNaturalLanguage(degrees: 360.0 + result)
                            }
                        } else {
                            if complexity == Complexity.verbose {
                                cell.direction.text = "\(Int(result))º"
                            } else {
                                cell.direction.text = directionNaturalLanguage(degrees: result)
                            }
                        }
                    } else {
                        cell.direction.text = "---º"
                    }
                } else {
                    cell.direction.text = "---º"
                }
            } else {
                cell.direction.text = "---º"
            }
            
            return cell
        } else {
            let connect = names[indexPath.row - 1]
            
            if let distance = poisToDist[connect.key] {
                cell.isHidden = false
                cell.backgroundColor = UIColor.systemBackground
                cell.overrideUserInterfaceStyle = UIUserInterfaceStyle.unspecified
                
                cell.tagType.text = poisToType[connect.key]
                cell.descriptiveName.text = connect.value
                
                if units == Units.imperial && distance < DIST_MAX {
                    cell.distance.text = "\(roundFeet(distance: distance * 3.28083)) ft"
                } else if units == Units.metric && distance < DIST_MAX {
                    cell.distance.text = "\(Int(distance)) m"
                } else {
                    cell.distance.text = "---"
                }
                
                if complexity != Complexity.concise, let heading = poisToHead[connect.key] {
                    if let direction = locationManager.heading?.trueHeading {
                        if heading < 0.0 {
                            let result = heading + 180.0 - direction
                            if result < -180.0 {
                                if complexity == Complexity.verbose {
                                    cell.direction.text = "\(Int(360.0 + result))º"
                                } else {
                                    cell.direction.text = directionNaturalLanguage(degrees: 360.0 + result)
                                }
                            } else {
                                if complexity == Complexity.verbose {
                                    cell.direction.text = "\(Int(result))º"
                                } else {
                                    cell.direction.text = directionNaturalLanguage(degrees: result)
                                }
                            }
                        } else if heading != DIR_MAX {
                            let result = heading - 180.0 - direction
                            if result < -180.0 {
                                if complexity == Complexity.verbose {
                                    cell.direction.text = "\(Int(360.0 + result))º"
                                } else {
                                    cell.direction.text = directionNaturalLanguage(degrees: 360.0 + result)
                                }
                            } else {
                                if complexity == Complexity.verbose {
                                    cell.direction.text = "\(Int(result))º"
                                } else {
                                    cell.direction.text = directionNaturalLanguage(degrees: result)
                                }
                            }
                        } else {
                            cell.direction.text = "---º"
                        }
                    } else {
                        cell.direction.text = "---º"
                    }
                } else {
                    cell.direction.text = "---º"
                }
            } else {
                cell.isHidden = true
            }
            return cell
        }
    }
    
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
       return false
    }

    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }

}
