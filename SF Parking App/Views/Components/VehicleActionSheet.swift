//
//  VehicleActionSheet.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/25/25.
//

import SwiftUI

struct VehicleActionSheet: View {
    let vehicle: Vehicle
    var onClose: () -> Void
    var onEdit: () -> Void
    var onSetLocation: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Vehicle name
            Text(vehicle.displayName)
                .font(.headline)
                .fontWeight(.medium)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSetLocation()
                } label: {
                    Text(vehicle.parkingLocation != nil ? "Update Location" : "Set Location")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onEdit()
                } label: {
                    Text("Edit")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(20)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

#Preview {
    VehicleParkingView()
}
