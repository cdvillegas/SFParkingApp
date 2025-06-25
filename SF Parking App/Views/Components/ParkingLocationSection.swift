//
//  ParkingLocationSection.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/24/25.
//

import CoreLocation
import SwiftUI

// MARK: - Location Section

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

struct ParkingLocationSection: View {
    let parkingLocation: ParkingLocation?
    let onLocationTap: (String) -> Void
    
    // Setting mode properties
    let isSettingMode: Bool
    let settingAddress: String?
    let settingNeighborhood: String?
    
    init(
        parkingLocation: ParkingLocation?,
        onLocationTap: @escaping (String) -> Void,
        isSettingMode: Bool = false,
        settingAddress: String? = nil,
        settingNeighborhood: String? = nil
    ) {
        self.parkingLocation = parkingLocation
        self.onLocationTap = onLocationTap
        self.isSettingMode = isSettingMode
        self.settingAddress = settingAddress
        self.settingNeighborhood = settingNeighborhood
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Parking Location")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            if isSettingMode {
                settingModeView
            } else {
                normalModeView
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .padding(.top, 0)
        .padding(.bottom, 0)
    }
    
    // MARK: - Setting Mode View
    
    private var settingModeView: some View {
        Button(action: {
            if let address = settingAddress {
                onLocationTap(address)
            }
        }) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "car.fill")
                    .foregroundColor(.blue)
                    .font(.body)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Address line - smooth transition from default
                    Text(settingAddress ?? "San Francisco")
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                        .animation(.easeInOut(duration: 0.4), value: settingAddress)
                    
                    // Neighborhood line - show neighborhood or default to "San Francisco"
                    Text(settingNeighborhood ?? "San Francisco")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
        }
        .animation(.easeInOut(duration: 0.3), value: settingNeighborhood)
    }
    
    // MARK: - Normal Mode View
    
    private var normalModeView: some View {
        Group {
            if let location = parkingLocation {
                Button(action: { onLocationTap(location.address) }) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "car.fill")
                            .foregroundColor(.blue)
                            .font(.body)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            // Address line
                            Text(location.address)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(nil)
                            
                            // Always show "View in Maps" - no neighborhood logic
                            Text("View in Maps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "car")
                        .foregroundColor(.secondary)
                        .font(.body)
                    
                    Text("No parking location set")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}



#Preview {
    ParkingLocationView()
}

#Preview("Light Mode") {
    ParkingLocationView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ParkingLocationView()
        .preferredColorScheme(.dark)
}
