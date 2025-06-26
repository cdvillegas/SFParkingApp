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
        VStack(spacing: 0) {
            // Vehicle info section
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(vehicle.color.color)
                        .frame(width: 48, height: 48)
                    Image(systemName: vehicle.type.iconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(radius: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(vehicle.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(vehicle.color.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

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
                .controlSize(.large)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onEdit()
                } label: {
                    Text("Edit Vehicle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}

#Preview {
    VehicleParkingView()
}
