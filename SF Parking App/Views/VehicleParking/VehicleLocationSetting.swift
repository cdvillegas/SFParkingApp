import SwiftUI
import MapKit

struct VehicleLocationSetting: View {
    @ObservedObject var viewModel: VehicleParkingViewModel
    @State private var impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    @Environment(\.colorScheme) private var colorScheme
    
    let onShowReminders: () -> Void
    let onShowSmartParking: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Content cards
            contentSection
            
            // Divider (always show when there are buttons)
            if viewModel.vehicleManager.currentVehicle != nil || !viewModel.vehicleManager.activeVehicles.isEmpty {
                Divider()
                    .padding(.top, 4)
            }
            
            // Bottom buttons
            buttonSection
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
                .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: -5)
        )
    }
    
    private func showRemindersSheet() {
        onShowReminders()
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        VStack(spacing: 16) {
            if viewModel.isSettingLocation && !viewModel.isConfirmingSchedule {
                // Step 1: Location selection - no schedules shown
                locationSelectionCard
            } else if viewModel.isConfirmingSchedule {
                // Step 2: Schedule confirmation
                scheduleConfirmationSection
            } else {
                // Normal vehicle view
                normalVehicleSection
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2), value: viewModel.isSettingLocation)
        .animation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2), value: viewModel.isConfirmingSchedule)
    }
    
    private var locationSelectionCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                // Status icon - smaller and consistent
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "car.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.blue.opacity(0.3), radius: 3, x: 0, y: 1)
                
                // Status text
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.locationStatusTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(viewModel.locationStatusSubtitle)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
    }
    
    private var scheduleConfirmationSection: some View {
        Group {
            if viewModel.nearbySchedules.isEmpty {
                noSchedulesCard
            } else {
                // Schedule cards with vehicle card styling
                scheduleSelectionCards
            }
        }
    }
    
    
    private var noSchedulesCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.green.opacity(0.3), radius: 3, x: 0, y: 1)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("No parking restrictions")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text("Safe to park here")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
    }
    
    private var scheduleSelectionCards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.nearbySchedules.enumerated()), id: \.0) { index, scheduleWithSide in
                        ScheduleSelectionCard(
                            scheduleWithSide: scheduleWithSide,
                            index: index,
                            isSelected: index == viewModel.selectedScheduleIndex && viewModel.hasSelectedSchedule,
                            onTap: {
                                impactFeedbackLight.impactOccurred()
                                viewModel.selectScheduleOption(index)
                            }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.trailing, 40)
            }
            .onChange(of: viewModel.selectedScheduleIndex) { _, newIndex in
                if viewModel.hasSelectedSchedule {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2)) {
                        let totalSchedules = viewModel.nearbySchedules.count
                        let isLastItem = newIndex == totalSchedules - 1
                        
                        if newIndex == 0 {
                            // First card: scroll back to initial position (~16px from screen edge)
                            proxy.scrollTo(0, anchor: UnitPoint(x: 0.5, y: 0.5))
                        } else if isLastItem {
                            // Last card: position 16px from right edge (less aggressive)
                            proxy.scrollTo(newIndex, anchor: UnitPoint(x: 0.88, y: 0.5))
                        } else {
                            // Middle cards: position 16px from left edge
                            proxy.scrollTo(newIndex, anchor: UnitPoint(x: 0.08, y: 0.5))
                        }
                    }
                }
            }
            .onChange(of: viewModel.hoveredScheduleIndex) { _, newIndex in
                if let index = newIndex {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2)) {
                        let totalSchedules = viewModel.nearbySchedules.count
                        let isLastItem = index == totalSchedules - 1
                        
                        if index == 0 {
                            // First card: scroll back to initial position (16px from screen edge)
                            proxy.scrollTo(0, anchor: UnitPoint(x: 0.0, y: 0.5))
                        } else if isLastItem {
                            // Last card: position 16px from right edge (less aggressive)
                            proxy.scrollTo(index, anchor: UnitPoint(x: 0.88, y: 0.5))
                        } else {
                            // Middle cards: position 16px from left edge
                            proxy.scrollTo(index, anchor: UnitPoint(x: 0.08, y: 0.5))
                        }
                    }
                }
            }
        }
    }
    
    private var normalVehicleSection: some View {
        SwipeableVehicleSection(
            vehicles: viewModel.vehicleManager.activeVehicles,
            selectedVehicle: viewModel.vehicleManager.currentVehicle,
            onVehicleSelected: { _ in },
            onVehicleTap: { vehicle in
                // Vehicle cards are no longer clickable - all actions go through menu or buttons
            },
            onShareLocation: { parkingLocation in
                shareParkingLocation(parkingLocation)
            },
            streetDataManager: viewModel.streetDataManager,
            onShowReminders: onShowReminders,
            onShowSmartParking: onShowSmartParking
        )
    }
    
    // MARK: - Button Section
    
    private var buttonSection: some View {
        VStack(spacing: 0) {
            if viewModel.isSettingLocation && !viewModel.isConfirmingSchedule {
                step1Buttons
            } else if viewModel.isConfirmingSchedule {
                step2Buttons
            } else {
                normalModeButtons
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2), value: viewModel.isSettingLocation)
        .animation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2), value: viewModel.isConfirmingSchedule)
    }
    
    private var step1Buttons: some View {
        HStack(spacing: 12) {
            // Cancel button
            Button(action: {
                impactFeedbackLight.impactOccurred()
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2)) {
                    viewModel.cancelSettingLocation()
                }
            }) {
                Text(viewModel.isSettingLocationForNewVehicle || viewModel.vehicleManager.currentVehicle?.parkingLocation == nil ? "Set Later" : "Cancel")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.thinMaterial)
                            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Set button
            Button(action: {
                impactFeedbackLight.impactOccurred()
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2)) {
                    viewModel.proceedToScheduleConfirmation()
                }
            }) {
                HStack(spacing: 8) {
                    if viewModel.isAutoDetectingSchedule {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    }
                    Text("Set Location")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: viewModel.canProceedToScheduleConfirmation ? [.blue, .blue.opacity(0.8)] : [.blue.opacity(0.6), .blue.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                )
            }
            .disabled(!viewModel.canProceedToScheduleConfirmation)
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var step2Buttons: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: {
                impactFeedbackLight.impactOccurred()
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2)) {
                    viewModel.goBackToLocationSetting()
                }
            }) {
                Text("Back")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.thinMaterial)
                            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Confirm button
            Button(action: {
                impactFeedbackLight.impactOccurred()
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2)) {
                    viewModel.confirmUnifiedLocation()
                }
            }) {
                Text("Confirm")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var normalModeButtons: some View {
        Group {
            if let currentVehicle = viewModel.vehicleManager.currentVehicle {
                Button(action: {
                    impactFeedbackLight.impactOccurred()
                    viewModel.isSettingLocationForNewVehicle = false
                    viewModel.startSettingLocationForVehicle(currentVehicle)
                }) {
                    Text(currentVehicle.parkingLocation != nil ? "Move Vehicle" : "Set Vehicle Location")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Map and Share Functions
    
    private func openVehicleInMaps(_ vehicle: Vehicle) {
        guard let parkingLocation = vehicle.parkingLocation else {
            impactFeedbackLight.impactOccurred()
            return
        }
        
        impactFeedbackLight.prepare()
        impactFeedbackLight.impactOccurred()
        
        let coordinate = parkingLocation.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Parking Location"
        
        mapItem.openInMaps(launchOptions: [:])
    }
    
    private func shareParkingLocation(_ parkingLocation: ParkingLocation) {
        let coordinate = parkingLocation.coordinate
        let mapLink = "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=Parking%20Location"
        
        let shareItems: [Any] = [
            URL(string: mapLink)!
        ]
        
        let activityViewController = UIActivityViewController(
            activityItems: shareItems,
            applicationActivities: nil
        )
        
        // Log analytics when share sheet is presented
        AnalyticsManager.shared.logParkingLocationShared(method: "share_sheet")
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            if let presentedViewController = rootViewController.presentedViewController {
                presentedViewController.present(activityViewController, animated: true)
            } else {
                rootViewController.present(activityViewController, animated: true)
            }
        }
    }
}

#Preview("Light Mode") {
    VehicleParkingView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VehicleParkingView()
        .preferredColorScheme(.dark)
}
