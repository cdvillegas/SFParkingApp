//
//  MapView.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import MapKit

struct ParkingMapView: View {
    @Binding var mapPosition: MapCameraPosition
    let userLocation: CLLocation?
    let parkingLocation: ParkingLocation?
    let onLocationTap: (CLLocationCoordinate2D) -> Void
    
    var body: some View {
        Map(position: $mapPosition) {
            // User location annotation
            if let userLocation = userLocation {
                Annotation("Your Location", coordinate: userLocation.coordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 20, height: 20)
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                }
            }
            
            // Parking location annotation
            if let parkingLocation = parkingLocation {
                Annotation("Parked Car", coordinate: parkingLocation.coordinate) {
                    ZStack {
                        Image(systemName: "car.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 32, height: 32)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
        }
        .mapStyle(.standard)
        .onTapGesture(coordinateSpace: .local) { location in
            // This is a simplified tap handler - you'd need more complex logic
            // to convert screen coordinates to map coordinates
        }
    }
}
