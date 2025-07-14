import SwiftUI
import MapKit
import CoreLocation

struct VehicleParkingMapView: View {
    @ObservedObject var viewModel: VehicleParkingViewModel
    @State private var currentMapHeading: CLLocationDirection = 0
    @State private var impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        Map(position: $viewModel.mapPosition, interactionModes: .all) {
            // User location annotation
            if viewModel.locationManager.authorizationStatus == .authorizedWhenInUse || viewModel.locationManager.authorizationStatus == .authorizedAlways {
                userLocationAnnotation
            }
            
            // Vehicle annotations
            vehicleAnnotations
            
            // Street sweeping schedule edge lines (only show in step 2)
            if viewModel.isConfirmingSchedule && !viewModel.nearbySchedules.isEmpty {
                streetEdgeScheduleLines
            }
        }
        .overlay(
            Group {
                if viewModel.isSettingLocation, let vehicle = viewModel.vehicleManager.selectedVehicle {
                    // Setting location pin - positioned so tip aligns with cursor
                    VStack {
                        Spacer()
                        
                        // Pin with adaptive color
                        VStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.green, Color.green.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 24, height: 24)
                                
                                Image(systemName: vehicle.type.iconName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: Color.green.opacity(0.4), radius: 6, x: 0, y: 3)
                            
                            // Pin tail
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.green)
                                .frame(width: 3, height: 12)
                        }
                        .offset(y: -18) // Move pin up so the tip of the line aligns with center
                        
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
        )
        .overlay(
            // Floating map control buttons - only show when NOT in confirm schedule mode
            Group {
                if !viewModel.isConfirmingSchedule {
                    HStack(spacing: 12) {
                        // Center on vehicle button
                        Button(action: {
                            impactFeedbackLight.impactOccurred()
                            centerOnVehicle()
                        }) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color(.systemGray6))
                                )
                        }
                        
                        // Center on user location button
                        Button(action: {
                            impactFeedbackLight.impactOccurred()
                            centerOnUser()
                        }) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16) // Closer to bottom
                }
            },
            alignment: .bottomTrailing
        )
        .mapStyle(.standard)
        .onMapCameraChange(frequency: .continuous) { context in
            currentMapHeading = context.camera.heading
            handleMapCameraChange(context)
        }
    }
    
    // MARK: - Map Content Builders
    
    @MapContentBuilder
    private var userLocationAnnotation: some MapContent {
        if let userLocation = viewModel.locationManager.userLocation {
            Annotation("", coordinate: userLocation.coordinate) {
                UserDirectionCone(heading: viewModel.locationManager.userHeading, mapHeading: currentMapHeading)
            }
        }
    }
    
    @MapContentBuilder
    private var vehicleAnnotations: some MapContent {
        ForEach(viewModel.vehicleManager.activeVehicles, id: \.id) { vehicle in
            if let parkingLocation = vehicle.parkingLocation {
                Annotation("My Vehicle", coordinate: parkingLocation.coordinate) {
                    VehicleParkingMapMarker(
                        vehicle: vehicle,
                        isSelected: viewModel.vehicleManager.selectedVehicle?.id == vehicle.id,
                        onTap: {
                            viewModel.centerMapOnLocation(parkingLocation.coordinate)
                        }
                    )
                }
            }
        }
    }
    
    @MapContentBuilder
    private var streetEdgeScheduleLines: some MapContent {
        ForEach(Array(viewModel.nearbySchedules.enumerated()), id: \.0) { index, scheduleWithSide in
            if let line = scheduleWithSide.schedule.line {
                ForEach(0..<line.coordinates.count-1, id: \.self) { segmentIndex in
                    let startCoord = line.coordinates[segmentIndex]
                    let endCoord = line.coordinates[segmentIndex + 1]
                    
                    if startCoord.count >= 2 && endCoord.count >= 2 {
                        let streetEdgeCoords = calculateStreetEdgeCoordinates(
                            start: CLLocationCoordinate2D(latitude: startCoord[1], longitude: startCoord[0]),
                            end: CLLocationCoordinate2D(latitude: endCoord[1], longitude: endCoord[0]),
                            blockSide: scheduleWithSide.side
                        )
                        
                        // Main parking zone line - improved visibility
                        MapPolyline(coordinates: streetEdgeCoords)
                            .stroke(
                                (index == viewModel.selectedScheduleIndex && viewModel.hasSelectedSchedule) ? Color.blue : Color.secondary.opacity(0.6),
                                style: StrokeStyle(
                                    lineWidth: (index == viewModel.selectedScheduleIndex && viewModel.hasSelectedSchedule) ? 10 : 7,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                        
                        // Tap areas for line interaction
                        ForEach(0..<min(streetEdgeCoords.count, 5), id: \.self) { tapIndex in
                            let coordIndex = (streetEdgeCoords.count - 1) * tapIndex / max(1, 4)
                            Annotation("", coordinate: streetEdgeCoords[coordIndex]) {
                                Button(action: {
                                    if viewModel.isConfirmingSchedule {
                                        viewModel.onScheduleHover(index)
                                    } else {
                                        impactFeedbackLight.impactOccurred()
                                        viewModel.selectScheduleOption(index)
                                    }
                                }) {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(width: 100, height: 40)
                                }
                            }
                        }
                        
                        // Selection glow - enhanced visibility
                        if index == viewModel.selectedScheduleIndex && viewModel.hasSelectedSchedule {
                            MapPolyline(coordinates: streetEdgeCoords)
                                .stroke(
                                    Color.blue.opacity(0.25),
                                    style: StrokeStyle(
                                        lineWidth: 20,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func centerOnVehicle() {
        if let currentVehicle = viewModel.vehicleManager.currentVehicle,
           let parkingLocation = currentVehicle.parkingLocation {
            viewModel.centerMapOnLocation(parkingLocation.coordinate)
        }
    }
    
    private func centerOnUser() {
        viewModel.locationManager.requestLocationPermission()
        if let userLocation = viewModel.locationManager.userLocation {
            viewModel.centerMapOnLocation(userLocation.coordinate)
            
            // If setting location, update the setting coordinate
            if viewModel.isSettingLocation {
                viewModel.settingCoordinate = userLocation.coordinate
                viewModel.debouncedGeocoder.reverseGeocode(coordinate: userLocation.coordinate) { address, _ in
                    DispatchQueue.main.async {
                        viewModel.settingAddress = address
                    }
                }
            }
        }
    }
    
    private func handleMapCameraChange(_ context: MapCameraUpdateContext) {
        currentMapHeading = context.camera.heading
        
        if viewModel.isSettingLocation && !viewModel.isConfirmingSchedule {
            // Step 1: Location setting - no schedule detection
            let newCoordinate = context.camera.centerCoordinate
            viewModel.settingCoordinate = newCoordinate
            viewModel.debouncedGeocoder.reverseGeocode(coordinate: newCoordinate) { address, _ in
                DispatchQueue.main.async {
                    viewModel.settingAddress = address
                }
            }
            
        } else if viewModel.isConfirmingSchedule {
            // Step 2: Schedule confirmation
            let newCoordinate = context.camera.centerCoordinate
            viewModel.settingCoordinate = newCoordinate
            
            // Smart selection between existing drawn lines
            smartSelectBetweenDrawnLines(for: newCoordinate)
        }
    }
    
    private func smartSelectBetweenDrawnLines(for coordinate: CLLocationCoordinate2D) {
        guard !viewModel.nearbySchedules.isEmpty else { return }
        
        var closestIndex = 0
        var closestDistance = Double.infinity
        
        for (index, scheduleWithSide) in viewModel.nearbySchedules.enumerated() {
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: scheduleWithSide.offsetCoordinate.latitude,
                                         longitude: scheduleWithSide.offsetCoordinate.longitude))
            
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }
        
        let flippedIndex = viewModel.nearbySchedules.count - 1 - closestIndex
        let finalIndex = flippedIndex < viewModel.nearbySchedules.count ? flippedIndex : closestIndex
        
        if viewModel.selectedScheduleIndex != finalIndex {
            viewModel.selectedScheduleIndex = finalIndex
            viewModel.hasSelectedSchedule = true
            viewModel.detectedSchedule = viewModel.nearbySchedules[finalIndex].schedule
            
            let distance = viewModel.nearbySchedules[finalIndex].distance
            viewModel.scheduleConfidence = Float(max(0.3, min(0.9, 1.0 - (distance / 50.0))))
            
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.selectionChanged()
        }
    }
    
    private func calculateStreetEdgeCoordinates(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        blockSide: String
    ) -> [CLLocationCoordinate2D] {
        
        let streetVector = (
            longitude: end.longitude - start.longitude,
            latitude: end.latitude - start.latitude
        )
        
        let perpVector = (
            longitude: -streetVector.latitude,
            latitude: streetVector.longitude
        )
        
        let perpLength = sqrt(perpVector.longitude * perpVector.longitude + perpVector.latitude * perpVector.latitude)
        guard perpLength > 0 else { return [start, end] }
        
        let normalizedPerp = (
            longitude: perpVector.longitude / perpLength,
            latitude: perpVector.latitude / perpLength
        )
        
        let (offsetDirection, offsetDistance) = getStreetEdgeOffset(blockSide: blockSide)
        
        let offsetStart = CLLocationCoordinate2D(
            latitude: start.latitude + (normalizedPerp.latitude * offsetDistance * offsetDirection),
            longitude: start.longitude + (normalizedPerp.longitude * offsetDistance * offsetDirection)
        )
        
        let offsetEnd = CLLocationCoordinate2D(
            latitude: end.latitude + (normalizedPerp.latitude * offsetDistance * offsetDirection),
            longitude: end.longitude + (normalizedPerp.longitude * offsetDistance * offsetDirection)
        )
        
        return [offsetStart, offsetEnd]
    }
    
    private func getStreetEdgeOffset(blockSide: String) -> (direction: Double, distance: Double) {
        let side = blockSide.lowercased()
        let parkingLaneOffset = 0.00003
        
        if side.contains("north") || side.contains("northeast") || side.contains("northwest") {
            return (-1.0, parkingLaneOffset)
        } else if side.contains("south") || side.contains("southeast") || side.contains("southwest") {
            return (1.0, parkingLaneOffset)
        } else if side.contains("east") {
            return (-1.0, parkingLaneOffset)
        } else if side.contains("west") {
            return (1.0, parkingLaneOffset)
        } else {
            return (1.0, parkingLaneOffset * 0.5)
        }
    }
}
