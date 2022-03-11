//
//  ExperimentViewController.swift
//  AVA OSM
//
//  Created by Matt Maring on 2/1/22.
//

import UIKit
import MapKit
import AVFoundation
import CoreLocation

class ExperimentViewController: UIViewController, AVSpeechSynthesizerDelegate {
    
    //let destination = CLLocation(latitude: 44.564825926200015, longitude: -69.65909124016235)

    @IBOutlet weak var experimentID: UIButton!
    
    @IBAction func pracPhase1(_ sender: Any) {
        if startExperiment() {
            experiment = "pracPhase1"
        }
    }
    
    @IBAction func pracPhase2(_ sender: Any) {
        if startExperiment() {
            experiment = "pracPhase2"
        }
    }
    
    @IBAction func phase1GPS(_ sender: Any) {
        if startExperiment() {
            experiment = "phase1GPS"
            let utterance = AVSpeechUtterance(string: "Your vehicle has arrived! Upon exiting the rear entrance of Davis, your autonomous vehicle is located approximately 30ft slightly left from your position. Please hold the smartphone in portrait mode with the rear facing camera pointed forward so that navigation guidance can be provided.")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            //utterance.rate = 1.0
            speechSynthesizer.speak(utterance)
        }
    }
    
    @IBAction func phase1UWB(_ sender: Any) {
        if startExperiment() {
            experiment = "phase1UWB"
            let utterance = AVSpeechUtterance(string: "Your vehicle has arrived! Upon exiting the rear entrance of Davis, your autonomous vehicle is located approximately 30ft slightly left from your position. Please hold the smartphone in portrait mode with the rear facing camera pointed forward so that navigation guidance can be provided.")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            //utterance.rate = 1.0
            speechSynthesizer.speak(utterance)
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
        let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let mapViewController = storyBoard.instantiateViewController(withIdentifier: "MapViewController") as! MapViewController
        mapViewController.destination = CLLocationCoordinate2D(latitude: 44.56320, longitude: -69.66136)
        mapViewController.modalPresentationStyle = .fullScreen
        self.present(mapViewController, animated: true, completion: nil)
    }
    
    // MARK: - Speech
    var speechSynthesizer = AVSpeechSynthesizer()
    
    var menuItems: [UIAction] = []
    var experiment : String? = Optional.none
    var experimentIDTitle : String? = Optional.none
    let experimentIDs = ["000001", "000002", "000003", "000004", "000005", "000006"]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        speechSynthesizer.delegate = self
        
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
        if experimentIDTitle == nil {
            // Create an alert to request the user select experiment ID.
            let accessAlert = UIAlertController(title: "Missing ID", message: "Please select experiment ID to continue.", preferredStyle: .alert)
            accessAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))

            // Preset the access alert.
            present(accessAlert, animated: true, completion: nil)
            
            return false
        } else {
            print("Starting Experiment")
            print(experimentIDTitle)
            
            return true
        }
    }
    
    // MARK: AVSpeechSynthesizer
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        print(experiment)
        if experiment != nil {
            let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
            switch experiment {
                case "pracPhase1":
                    let trackerViewController = storyBoard.instantiateViewController(withIdentifier: "TrackerViewController") as! TrackerViewController
                    trackerViewController.destination = CLLocation(latitude: 44.56476, longitude: -69.65904)
                    trackerViewController.modalPresentationStyle = .fullScreen
                    self.present(trackerViewController, animated: true, completion: nil)
                case "pracPhase2":
                    let trackerViewController = storyBoard.instantiateViewController(withIdentifier: "TrackerViewController") as! TrackerViewController
                    trackerViewController.destination = CLLocation(latitude: 44.56476, longitude: -69.65904)
                    trackerViewController.modalPresentationStyle = .fullScreen
                    self.present(trackerViewController, animated: true, completion: nil)
                case "phase1GPS":
                    let gpsViewController = storyBoard.instantiateViewController(withIdentifier: "GPSViewController") as! GPSViewController
                    gpsViewController.destination = CLLocation(latitude: 44.56476, longitude: -69.65904)
                    gpsViewController.modalPresentationStyle = .fullScreen
                    self.present(gpsViewController, animated: true, completion: nil)
                case "phase1UWB":
                    let trackerViewController = storyBoard.instantiateViewController(withIdentifier: "TrackerViewController") as! TrackerViewController
                    trackerViewController.destination = CLLocation(latitude: 44.56476, longitude: -69.65904)
                    trackerViewController.modalPresentationStyle = .fullScreen
                    self.present(trackerViewController, animated: true, completion: nil)
                default:
                    let mapViewController = storyBoard.instantiateViewController(withIdentifier: "MapViewController") as! MapViewController
                    mapViewController.destination = CLLocationCoordinate2D(latitude: 44.56320, longitude: -69.66136)
                    mapViewController.modalPresentationStyle = .fullScreen
                    self.present(mapViewController, animated: true, completion: nil)
            }
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
