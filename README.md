# AVA-OSM

This tool is the navigation component of an Autonomous Vehicle Assistant application designed to help guide blind and visuallly impaired users to autonomous vehicles. I have implemented a multistage spatial guidance system for BVI users that is designed to take advantage of a variety of technologies that have varrying accuracies and capabilities. The high-level directions are generated from GPS measurements, the Mapbox API, and map sources such as Apple Maps and Open Street Maps. Low-level navigation is accomplished by using ultra-wideband measurements using the Nearby Interaction framework (U1 chip) and a Qorvo DWM3000 UWB sensor, combined with augmented reality using the ARKit framework to continuously provide direction measurements when the UWB is out of the line of sight.

## Installation

This tool requires a U1-compatable third-party UWB sensor preloaded with the Apple Nearby Interaction demo code ("https://developer.apple.com/nearby-interaction/").

## Usage

This tool is designed to work with VoiceOver, however users with a variety of disabilities (or none at all!) can take advantage of the accurate navigation techniques used. As such, haptic and visual feedback is used in addition to audio feedback,
