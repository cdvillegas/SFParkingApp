//
//  MapControlButtons.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import CoreLocation

struct MapControlButtons: View {
    let userLocation: CLLocation?
    let parkingLocation: ParkingLocation?
    let onCenterOnUser: () -> Void
    let onGoToCar: () -> Void
    let onLocationRequest: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                // Go to Car Button
                if parkingLocation != nil {
                    Button(action: onGoToCar) {
                        Image(systemName: "car.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, 12)
                }
                
                // Center on User Button
                Button(action: {
                    if userLocation != nil {
                        onCenterOnUser()
                    } else {
                        onLocationRequest()
                    }
                }) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .padding(.trailing, 20)
            }
        }
        .padding(.bottom, 20)
    }
}
