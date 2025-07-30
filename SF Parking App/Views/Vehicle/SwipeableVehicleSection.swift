import SwiftUI
import CoreLocation
import MapKit

struct SwipeableVehicleSection: View {
    let vehicles: [Vehicle]
    let selectedVehicle: Vehicle?
    let onVehicleSelected: (Vehicle) -> Void
    let onVehicleTap: (Vehicle) -> Void
    let onShareLocation: ((ParkingLocation) -> Void)?
    let streetDataManager: StreetDataManager?
    let onShowReminders: (() -> Void)?
    let onShowSmartParking: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            if !vehicles.isEmpty {
                // Single vehicle card - no swiping
                if let vehicle = vehicles.first {
                    VehicleSwipeCard(
                        vehicle: vehicle,
                        isSelected: selectedVehicle?.id == vehicle.id,
                        onTap: {
                            impactFeedback()
                            onVehicleTap(vehicle)
                        },
                        onShare: onShareLocation,
                        streetDataManager: streetDataManager,
                        onShowReminders: onShowReminders,
                        onShowSmartParking: onShowSmartParking
                    )
                }
            } else {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "car.circle")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("No Vehicles")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("Add your first vehicle to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(height: 120)
                .padding(.horizontal, 20)
            }
        }
    }
    
    private func impactFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

struct VehicleSwipeCard: View {
    let vehicle: Vehicle
    let isSelected: Bool
    let onTap: () -> Void
    let onShare: ((ParkingLocation) -> Void)?
    let streetDataManager: StreetDataManager?
    let onShowReminders: (() -> Void)?
    let onShowSmartParking: (() -> Void)?
    
    @State private var isPressed = false
    @State private var isMenuPressed = false
    @State private var cachedMoveText: String = "No restrictions found"
    @State private var lastScheduleDate: Date?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Vehicle icon with urgency color - smaller
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    getUrgencyColor(for: vehicle),
                                    getUrgencyColor(for: vehicle).opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: vehicle.type.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: getUrgencyColor(for: vehicle).opacity(0.3), radius: 3, x: 0, y: 1)
                
                // Vehicle info
                VStack(alignment: .leading, spacing: 4) {
                    // Parking address
                    if let parkingLocation = vehicle.parkingLocation {
                        Text(parkingLocation.address.components(separatedBy: ",").prefix(2).joined(separator: ","))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        Text(cachedMoveText)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("No vehicle location set")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Text("Press \"Set Vehicle Location\"")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Menu button (only show when there are valid options)
                if vehicle.parkingLocation != nil {
                    Menu {
                        Button("View in Maps", systemImage: "map") {
                            openVehicleInMaps(vehicle)
                        }
                        
                        if let parkingLocation = vehicle.parkingLocation, let onShare = onShare {
                            Button("Share Location", systemImage: "square.and.arrow.up") {
                                onShare(parkingLocation)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(.regularMaterial)
                                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                            )
                    }
                    .onLongPressGesture(minimumDuration: 0) {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
                }
            }
        }
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.9), value: isPressed)
        .onAppear {
            updateCachedMoveText()
        }
        .onChange(of: streetDataManager?.nextUpcomingSchedule?.date) { _, newDate in
            if newDate != lastScheduleDate {
                updateCachedMoveText()
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func updateCachedMoveText() {
        cachedMoveText = getMoveBeforeText(for: vehicle)
        lastScheduleDate = streetDataManager?.nextUpcomingSchedule?.date
    }
    
    private func getUrgencyColor(for vehicle: Vehicle) -> Color {
        guard let streetDataManager = streetDataManager,
              let nextSchedule = streetDataManager.nextUpcomingSchedule,
              vehicle.parkingLocation != nil else {
            return vehicle.color.color
        }
        
        let urgencyLevel = getUrgencyLevel(for: nextSchedule.date)
        switch urgencyLevel {
        case .critical:
            return .red
        case .safe:
            return .green
        }
    }
    
    private func getMoveBeforeText(for vehicle: Vehicle) -> String {
        guard let streetDataManager = streetDataManager,
              let nextSchedule = streetDataManager.nextUpcomingSchedule,
              vehicle.parkingLocation != nil else {
            return "No restrictions found"
        }
        
        let calendar = Calendar.current
        let now = Date()
        let timeInterval = nextSchedule.date.timeIntervalSince(now)
        let hours = timeInterval / 3600
        let minutes = Int(timeInterval / 60)
        
        // Very close (less than 2 hours)
        if hours < 2 {
            if minutes <= 30 {
                return "Move in \(minutes) Minutes"
            } else if minutes <= 60 {
                return "Move in 1 Hour"
            } else {
                let roundedHours = Int(ceil(hours))
                return "Move in \(roundedHours) Hours"
            }
        }
        
        // Today
        if calendar.isDateInToday(nextSchedule.date) {
            return "Move by Today, \(nextSchedule.startTime)"
        }
        
        // Tomorrow
        if calendar.isDateInTomorrow(nextSchedule.date) {
            return "Move by Tomorrow, \(nextSchedule.startTime)"
        }
        
        // Calculate days more accurately
        let startOfToday = calendar.startOfDay(for: now)
        let startOfScheduleDay = calendar.startOfDay(for: nextSchedule.date)
        let daysUntil = calendar.dateComponents([.day], from: startOfToday, to: startOfScheduleDay).day ?? 0
        
        
        if daysUntil == 2 {
            return "Move in 2 Days, \(nextSchedule.startTime)"
        }
        
        // Perfect logic based on your requirements:
        // - Within 6 days: show day name with time
        // - Exactly 7 days (next week same day): show "Next [Day]" without time  
        // - 8+ days but < 2 weeks: show "Next [Day]" without time
        // - 2+ weeks: show weeks
        
        if daysUntil <= 6 {
            // Within 6 days - show day name with time
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            let dayString = formatter.string(from: nextSchedule.date)
            return "Move by \(dayString), \(nextSchedule.startTime)"
        } else if daysUntil <= 13 {
            // 7-13 days (next week) - show "Next [Day]" with time
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            let dayString = formatter.string(from: nextSchedule.date)
            return "Move by Next \(dayString), \(nextSchedule.startTime)"
        } else {
            // 14+ days - show actual date with time
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"  // e.g., "August 12"
            let dateString = formatter.string(from: nextSchedule.date)
            return "Move by \(dateString), \(nextSchedule.startTime)"
        }
    }
    
    private enum UrgencyLevel {
        case critical  // < 24 hours
        case safe      // >= 24 hours
    }
    
    private func getUrgencyLevel(for date: Date) -> UrgencyLevel {
        let timeInterval = date.timeIntervalSinceNow
        let hours = timeInterval / 3600
        
        if hours < 24 {
            return .critical
        } else {
            return .safe
        }
    }
    
    private func openVehicleInMaps(_ vehicle: Vehicle) {
        guard let parkingLocation = vehicle.parkingLocation else { return }
        
        let coordinate = parkingLocation.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "Parking Location"
        
        mapItem.openInMaps(launchOptions: [:])
    }
}

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
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
