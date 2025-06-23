//
//  LocationPickerView.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI
import CoreLocation

struct LocationPickerView: View {
    let onLocationSelected: (CLLocationCoordinate2D, String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Location Picker")
                Text("This would be a map interface for selecting a parking location")
                
                Button("Select Sample Location") {
                    onLocationSelected(
                        CLLocationCoordinate2D(latitude: 37.784790, longitude: -122.441556),
                        "1530 Broderick Street"
                    )
                    dismiss()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .navigationTitle("Set Parking Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
