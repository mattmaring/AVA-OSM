//
//  MapViewController.swift
//  AVA OSM
//
//  Created by Matt Maring on 7/12/21.
//

import UIKit
import MapKit
import CoreLocation

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

class MapViewController: UIViewController, CLLocationManagerDelegate {

    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var modeText: UILabel!
    @IBAction func switchMode(_ sender: Any) {
        if (sender as AnyObject).isOn == true {
            Debug.sharedInstance.modeText = "User"
        } else {
            Debug.sharedInstance.modeText = "Driver"
        }
    }
    
    var locationManager = CLLocationManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager.requestAlwaysAuthorization()
        if (CLLocationManager.locationServicesEnabled()) {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last{
            let center = CLLocationCoordinate2D(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            let region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001))
            self.mapView.setRegion(region, animated: true)
//            print(self.mapView.visibleMapRect.maxX)
//            print(self.mapView.visibleMapRect.maxY)
//            print(self.mapView.visibleMapRect.minX)
//            print(self.mapView.visibleMapRect.minY)
//            print(self.mapView.centerCoordinate)
        }
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
