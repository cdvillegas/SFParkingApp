import SwiftUI
import MapKit

struct VehicleLocationSetting: View {
    @ObservedObject var viewModel: VehicleParkingViewModel
    @State private var impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    @Environment(\.colorScheme) private var colorScheme
    
    let onShowReminders: () -> Void
    let onShowSmartParking: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            // Content cards
            contentSection
            
            // Bottom buttons
            buttonSection
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            // Left side: Title and subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.headerTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.top, 6)
                
                // Always show subtitle space to maintain consistent height
                Text(viewModel.headerSubtitle ?? " ")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .opacity(viewModel.headerSubtitle != nil ? 1.0 : 0.0)
            }
            
            Spacer()
            
            // Right side: Buttons
            if viewModel.isSettingLocation && !viewModel.isConfirmingSchedule {
                if viewModel.isAutoDetectingSchedule {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.blue)
                }
            } else if viewModel.isConfirmingSchedule {
                // No buttons during schedule confirmation
            } else {
                // Show different buttons based on whether we have vehicles
                if viewModel.vehicleManager.activeVehicles.isEmpty {
                    // Add vehicle button when no vehicles
                    Button(action: {
                        impactFeedbackLight.impactOccurred()
                        if let currentVehicle = viewModel.vehicleManager.currentVehicle {
                            viewModel.showingEditVehicle = currentVehicle
                        } else {
                            viewModel.showingAddVehicle = true
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .medium))
                            Text("Add Vehicle")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.9))
                                .shadow(color: .blue, radius: 6, x: 0, y: 3)
                        )
                    }
                } else {
                    // Three dot menu button when vehicle exists
                    Menu {
                        Button(action: {
                            impactFeedbackLight.impactOccurred()
                            showRemindersSheet()
                        }) {
                            Label("Reminders", systemImage: "bell.fill")
                        }
                        
                        Button(action: {
                            impactFeedbackLight.impactOccurred()
                            onShowSmartParking()
                        }) {
                            Label("Smart Parking", systemImage: "sparkles")
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(.systemGray6))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .animation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2), value: viewModel.isSettingLocation)
        .animation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0.2), value: viewModel.isConfirmingSchedule)
    }
    
    
    private func showRemindersSheet() {
        onShowReminders()
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        VStack(spacing: 0) {
            if viewModel.isSettingLocation && !viewModel.isConfirmingSchedule {
                // Step 1: Location selection - no schedules shown
                locationSelectionCard
                    .padding(.horizontal, 16)
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Status icon - always green now
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "car.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // Status text
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.locationStatusTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(viewModel.locationStatusSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                .shadow(
                    color: Color.blue.opacity(0.2),
                    radius: 6,
                    x: 0,
                    y: 3
                )
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .padding(.bottom, 12)
        .frame(minHeight: 100)
    }
    
    private var scheduleConfirmationSection: some View {
        VStack(spacing: 16) {
            if viewModel.nearbySchedules.isEmpty {
                noSchedulesCard
                    .padding(.horizontal, 16) // Only the no schedules card needs padding
            } else {
                // Schedule cards extend to screen edges
                scheduleSelectionCards
            }
        }
        .frame(minHeight: 100)
    }
    
    
    private var noSchedulesCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("No parking restrictions")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text("Safe to park here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                .shadow(color: Color.blue.opacity(0.2), radius: 6, x: 0, y: 3)
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .padding(.bottom, 12)
        .frame(minHeight: 100)
    }
    
    private var scheduleSelectionCards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
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
                .padding(.leading, 16)
                .padding(.trailing, 80) // Extra trailing padding to allow scrolling cards off screen
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
            .padding(.bottom, 12)
        }
    }
    
    private var normalVehicleSection: some View {
        SwipeableVehicleSection(
            vehicles: viewModel.vehicleManager.activeVehicles,
            selectedVehicle: viewModel.vehicleManager.currentVehicle,
            onVehicleSelected: { _ in },
            onVehicleTap: { vehicle in
                if vehicle.parkingLocation != nil {
                    openVehicleInMaps(vehicle)
                } else {
                    impactFeedbackLight.impactOccurred()
                    viewModel.isSettingLocationForNewVehicle = false
                    viewModel.startSettingLocationForVehicle(vehicle)
                }
            },
            onShareLocation: { parkingLocation in
                shareParkingLocation(parkingLocation)
            }
        )
        .frame(minHeight: 100)
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
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
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
                            .fill(Color(.systemGray6))
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
                        .fill(viewModel.canProceedToScheduleConfirmation ? Color.blue : Color.blue.opacity(0.6))
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
                            .fill(Color(.systemGray6))
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
                            .fill(Color.blue)
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
