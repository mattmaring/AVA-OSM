//
//  ExperimentViewController.swift
//  AVA OSM
//
//  Created by Matt Maring on 2/1/22.
//

import UIKit
import MapKit
import CoreLocation

class ExperimentViewController: UIViewController {
    
    //let destination = CLLocation(latitude: 44.564825926200015, longitude: -69.65909124016235)

    @IBOutlet weak var experimentID: UIButton!
    
    @IBAction func pracPhase1(_ sender: Any) {
        if startExperiment() {
            let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
            let trackerViewController = storyBoard.instantiateViewController(withIdentifier: "TrackerViewController") as! TrackerViewController
            trackerViewController.destination = CLLocation(latitude: 44.56320, longitude: -69.66136)
            trackerViewController.modalPresentationStyle = .fullScreen
            self.present(trackerViewController, animated: true, completion: nil)
        }
    }
    
    @IBAction func pracPhase2(_ sender: Any) {
        if startExperiment() {
            let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
            let trackerViewController = storyBoard.instantiateViewController(withIdentifier: "TrackerViewController") as! TrackerViewController
            trackerViewController.destination = CLLocation(latitude: 44.56320, longitude: -69.66136)
            trackerViewController.modalPresentationStyle = .fullScreen
            self.present(trackerViewController, animated: true, completion: nil)
        }
    }
    
    @IBAction func phase1GPS(_ sender: Any) {
        // Need to lock this to GPS
        if startExperiment() {
            let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
            let trackerViewController = storyBoard.instantiateViewController(withIdentifier: "TrackerViewController") as! TrackerViewController
            trackerViewController.destination = CLLocation(latitude: 44.56320, longitude: -69.66136)
            trackerViewController.modalPresentationStyle = .fullScreen
            self.present(trackerViewController, animated: true, completion: nil)
        }
    }
    
    @IBAction func phase1UWB(_ sender: Any) {
        if startExperiment() {
            let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
            let trackerViewController = storyBoard.instantiateViewController(withIdentifier: "TrackerViewController") as! TrackerViewController
            trackerViewController.destination = CLLocation(latitude: 44.56320, longitude: -69.66136)
            trackerViewController.modalPresentationStyle = .fullScreen
            self.present(trackerViewController, animated: true, completion: nil)
        }
    }
    
    @IBAction func phase2(_ sender: Any) {
        if startExperiment() {
            let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
            let mapViewController = storyBoard.instantiateViewController(withIdentifier: "MapViewController") as! MapViewController
            mapViewController.destination = CLLocationCoordinate2D(latitude: 44.56320, longitude: -69.66136)
            mapViewController.modalPresentationStyle = .fullScreen
            self.present(mapViewController, animated: true, completion: nil)
        }
    }
    
    @IBAction func normalOps(_ sender: Any) {
        if startExperiment() {
            let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
            let mapViewController = storyBoard.instantiateViewController(withIdentifier: "MapViewController") as! MapViewController
            mapViewController.destination = CLLocationCoordinate2D(latitude: 44.56320, longitude: -69.66136)
            mapViewController.modalPresentationStyle = .fullScreen
            self.present(mapViewController, animated: true, completion: nil)
        }
    }
    
    var menuItems: [UIAction] = []
    var experimentIDTitle = "nil"
    let experimentIDs = ["000001", "000002", "000003", "000004", "000005", "000006"]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        for user in experimentIDs {
            let action = UIAction(title: user) { (action) in
                self.experimentIDTitle = user
            }
            menuItems.append(action)
        }

        experimentID.menu = UIMenu(title: "Select ID", image: nil, identifier: nil, options: [], children: menuItems)
        experimentID.showsMenuAsPrimaryAction = true
    }
    
    func startExperiment() -> Bool {
        if experimentIDTitle == "nil" {
            // Create an alert to request the user select experiment ID.
            let accessAlert = UIAlertController(title: "Missing ID", message: "Please select experiment ID to continue.", preferredStyle: .alert)
            accessAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))

            // Preset the access alert.
            present(accessAlert, animated: true, completion: nil)
            
            return false
        } else {
            print("Startng Experiment")
            print(experimentIDTitle)
            
            return true
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
