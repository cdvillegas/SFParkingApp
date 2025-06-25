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
    let onLocationTap: (CLLocationCoordinate2D) -> Void
    
    // Setting mode properties
    let isSettingMode: Bool
    let settingAddress: String?
    let settingNeighborhood: String?
    let settingCoordinate: CLLocationCoordinate2D?
    
    init(
        parkingLocation: ParkingLocation?,
        onLocationTap: @escaping (CLLocationCoordinate2D) -> Void,
        isSettingMode: Bool = false,
        settingAddress: String? = nil,
        settingNeighborhood: String? = nil,
        settingCoordinate: CLLocationCoordinate2D? = nil
    ) {
        self.parkingLocation = parkingLocation
        self.onLocationTap = onLocationTap
        self.isSettingMode = isSettingMode
        self.settingAddress = settingAddress
        self.settingNeighborhood = settingNeighborhood
        self.settingCoordinate = settingCoordinate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parking Location")
                .font(.title3)
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
            if let coordinate = settingCoordinate {
                onLocationTap(coordinate)
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
                Button(action: { onLocationTap(location.coordinate) }) {
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
