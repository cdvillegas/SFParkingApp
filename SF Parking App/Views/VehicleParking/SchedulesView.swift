import SwiftUI
import CoreLocation
import MapKit
import CoreMotion
import Combine

struct SchedulesView: View {
    let vehicle: Vehicle
    let parkingLocation: ParkingLocation
    let schedule: UpcomingSchedule?
    let originalSchedule: SweepSchedule?
    @Environment(\.dismiss) private var dismiss
    @State private var impactFeedbackLight = UIImpactFeedbackGenerator(style: .light)
    @State private var showingEditLocation = false
    @State private var mapRegion: MKCoordinateRegion
    @State private var rotationX: Double = 0
    @State private var rotationY: Double = 0
    @StateObject private var motionManager = DeviceMotionManager()
    
    init(vehicle: Vehicle, parkingLocation: ParkingLocation, schedule: UpcomingSchedule?, originalSchedule: SweepSchedule? = nil) {
        self.vehicle = vehicle
        self.parkingLocation = parkingLocation
        self.schedule = schedule
        self.originalSchedule = originalSchedule
        self._mapRegion = State(initialValue: MKCoordinateRegion(
            center: parkingLocation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 24)
            
            // Active Schedule Section
            if let schedule = schedule {
                activeScheduleSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            
            // SF Parking Sign - positioned relative to schedule section
            parkingSignView
                .padding(.horizontal, 40)
                .padding(.top, 40)
            
            Spacer()
        }
        .presentationBackground(.thinMaterial)
        .presentationBackgroundInteraction(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            // Fixed bottom button
            bottomButton
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Schedules")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var activeScheduleSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(scheduleUrgencyColor)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "calendar")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    // Line 1: Street Cleaning
                    Text("Street Cleaning")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if let schedule = schedule {
                        // Line 2: Date and Time
                        Text("\(formatScheduleDate(schedule)) • \(formatScheduleTimeRange(schedule))")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        
                        // Line 2.5: Estimated sweeper time (conditional)
                        if let estimatedTime = schedule.estimatedSweeperTime {
                            Text("Sweepers typically arrive around \(estimatedTime)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(red: 0.8, green: 0.4, blue: 0.2))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        
                        // Line 3: Time remaining
                        Text("in \(scheduleTimeRemaining)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(scheduleUrgencyColor)
                    }
                }
                
                Spacer()
            }
            .padding(16)
        }
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
    
    private func formatScheduleDate(_ schedule: UpcomingSchedule) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: schedule.date)
    }
    
    private func formatScheduleTimeRange(_ schedule: UpcomingSchedule) -> String {
        let cleanStartTime = schedule.startTime.replacingOccurrences(of: ":00", with: "")
        let cleanEndTime = schedule.endTime.replacingOccurrences(of: ":00", with: "")
        return "\(cleanStartTime) - \(cleanEndTime)"
    }
    
    @ViewBuilder
    private func scheduleTimeDisplay(_ schedule: UpcomingSchedule) -> some View {
        HStack(spacing: 6) {
            let startTimeComponents = parseTime(schedule.startTime)
            let endTimeComponents = parseTime(schedule.endTime)
            
            // Start time
            Text(startTimeComponents.hour)
                .font(.custom("HighwayGothic", size: 60))
                .foregroundColor(Color(red: 1.0, green: 0.0, blue: 0.0))
            Text(startTimeComponents.period)
                .font(.custom("HighwayGothic", size: 20))
                .foregroundColor(Color(red: 1.0, green: 0.0, blue: 0.0))
                .padding(.top, 10)
            
            Text("TO")
                .font(.custom("HighwayGothic", size: 16))
                .foregroundColor(Color(red: 1.0, green: 0.0, blue: 0.0))
                .padding(.top, -8)
                .padding(.horizontal, 6)
            
            // End time
            Text(endTimeComponents.hour)
                .font(.custom("HighwayGothic", size: 60))
                .foregroundColor(Color(red: 1.0, green: 0.0, blue: 0.0))
            Text(endTimeComponents.period)
                .font(.custom("HighwayGothic", size: 20))
                .foregroundColor(Color(red: 1.0, green: 0.0, blue: 0.0))
                .padding(.top, 10)
        }
    }
    
    @ViewBuilder
    private func scheduleInfoDisplay(_ schedule: UpcomingSchedule) -> some View {
        HStack(spacing: 3) {
            let dayText = formatScheduleDayForSign(schedule.dayOfWeek)
            
            // Check if it contains ordinals that need special formatting
            if dayText.contains("ST") || dayText.contains("ND") || dayText.contains("RD") || dayText.contains("TH") {
                formatOrdinalText(dayText)
            } else {
                // Simple text without ordinals
                Text(dayText)
                    .font(.custom("HighwayGothic", size: 22))
                    .foregroundColor(Color(red: 1.0, green: 0.0, blue: 0.0))
            }
        }
        .tracking(0.2)
    }
    
    @ViewBuilder
    private func formatOrdinalText(_ text: String) -> some View {
        HStack(spacing: 6) {
            let components = parseOrdinalText(text)
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                if component.isOrdinal {
                    HStack(spacing: 0) {
                        Text(component.number)
                            .font(.custom("HighwayGothic", size: 22))
                            .foregroundColor(Color(red: 1.0, green: 0.0, blue: 0.0))
                        Text(component.suffix)
                            .font(.custom("HighwayGothic", size: 12))
                            .foregroundColor(Color(red: 1.0, green: 0.0, blue: 0.0))
                            .offset(y: -6)
                    }
                } else {
                    Text(component.text)
                        .font(.custom("HighwayGothic", size: 22))
                        .foregroundColor(Color(red: 1.0, green: 0.0, blue: 0.0))
                }
            }
        }
    }
    
    private struct TextComponent {
        let text: String
        let number: String
        let suffix: String
        let isOrdinal: Bool
    }
    
    private func parseOrdinalText(_ text: String) -> [TextComponent] {
        var components: [TextComponent] = []
        let words = text.components(separatedBy: " ")
        
        for word in words {
            if let match = word.range(of: #"(\d+)(ST|ND|RD|TH)"#, options: .regularExpression) {
                let number = String(word[word.startIndex..<match.lowerBound])
                let ordinal = String(word[match])
                let ordinalNumber = String(ordinal.dropLast(2))
                let ordinalSuffix = String(ordinal.suffix(2))
                
                if !number.isEmpty {
                    components.append(TextComponent(text: number, number: "", suffix: "", isOrdinal: false))
                }
                components.append(TextComponent(text: "", number: ordinalNumber, suffix: ordinalSuffix, isOrdinal: true))
                
                let remaining = String(word[match.upperBound...])
                if !remaining.isEmpty {
                    components.append(TextComponent(text: remaining, number: "", suffix: "", isOrdinal: false))
                }
            } else {
                components.append(TextComponent(text: word + " ", number: "", suffix: "", isOrdinal: false))
            }
        }
        
        return components
    }
    
    private func formatScheduleDayForSign(_ dayOfWeek: String) -> String {
        // If we have the original schedule data, use it to build the proper pattern
        if let originalSchedule = originalSchedule {
            print("🗓️ Using original schedule: \(originalSchedule.corridor ?? "Unknown")")
            return buildWeekPatternFromSchedule(originalSchedule, dayOfWeek: dayOfWeek)
        } else {
            print("🗓️ No original schedule available, using fallback")
        }
        
        // First try the existing complex parser
        let complexResult = parseScheduleDay(dayOfWeek)
        
        // If it returns the same thing (meaning it didn't parse), try simple day formatting
        if complexResult.uppercased() == dayOfWeek.uppercased() {
            // Handle simple day names
            let simplified = dayOfWeek.uppercased()
            switch simplified {
            case "MON", "MONDAY":
                return "MONDAY"
            case "TUE", "TUESDAY", "TUES":
                return "TUESDAY"
            case "WED", "WEDNESDAY":
                return "WEDNESDAY"
            case "THU", "THURSDAY", "THUR", "THURS":
                return "THURSDAY"
            case "FRI", "FRIDAY":
                return "FRIDAY"
            case "SAT", "SATURDAY":
                return "SATURDAY"
            case "SUN", "SUNDAY":
                return "SUNDAY"
            default:
                return simplified
            }
        }
        
        return complexResult.uppercased()
    }
    
    private func buildWeekPatternFromSchedule(_ schedule: SweepSchedule, dayOfWeek: String) -> String {
        // Get the full day name
        let fullDayName = getFullDayName(dayOfWeek)
        
        // Debug logging
        print("🗓️ Schedule debug: week1=\(schedule.week1 ?? "nil"), week2=\(schedule.week2 ?? "nil"), week3=\(schedule.week3 ?? "nil"), week4=\(schedule.week4 ?? "nil"), week5=\(schedule.week5 ?? "nil")")
        
        // Build array of active weeks
        var activeWeeks: [String] = []
        
        if schedule.week1 == "Y" || schedule.week1 == "1" { activeWeeks.append("1ST") }
        if schedule.week2 == "Y" || schedule.week2 == "1" { activeWeeks.append("2ND") }
        if schedule.week3 == "Y" || schedule.week3 == "1" { activeWeeks.append("3RD") }
        if schedule.week4 == "Y" || schedule.week4 == "1" { activeWeeks.append("4TH") }
        if schedule.week5 == "Y" || schedule.week5 == "1" { activeWeeks.append("5TH") }
        
        // Debug: show what weeks are active
        print("🗓️ Active weeks: \(activeWeeks)")
        
        // If no weeks specified or 4+ weeks active, show just the day
        if activeWeeks.isEmpty || activeWeeks.count >= 4 {
            return "EVERY \(fullDayName)"
        }
        
        // Build the pattern like "1ST and 3RD WEDNESDAY"
        let weekPattern = activeWeeks.joined(separator: " and ")
        let result = "\(weekPattern) \(fullDayName)"
        print("🗓️ Final result: \(result)")
        return result
    }
    
    private func getFullDayName(_ dayOfWeek: String) -> String {
        let simplified = dayOfWeek.uppercased()
        switch simplified {
        case "MON", "MONDAY":
            return "MONDAY"
        case "TUE", "TUESDAY", "TUES":
            return "TUESDAY"
        case "WED", "WEDNESDAY":
            return "WEDNESDAY"
        case "THU", "THURSDAY", "THUR", "THURS":
            return "THURSDAY"
        case "FRI", "FRIDAY":
            return "FRIDAY"
        case "SAT", "SATURDAY":
            return "SATURDAY"
        case "SUN", "SUNDAY":
            return "SUNDAY"
        default:
            return simplified
        }
    }
    
    private func parseTime(_ timeString: String) -> (hour: String, period: String) {
        // Parse time like "9:00 AM" or "11:00 AM"
        let components = timeString.components(separatedBy: " ")
        guard components.count == 2 else {
            return ("?", "")
        }
        
        let timePart = components[0]
        let period = components[1]
        
        // Extract hour (remove :00 if present)
        let hourPart = timePart.components(separatedBy: ":")[0]
        
        // Add dots to AM/PM
        let periodWithDots = period.replacingOccurrences(of: "AM", with: "A.M.")
                                  .replacingOccurrences(of: "PM", with: "P.M.")
        
        return (hourPart, periodWithDots)
    }
    
    private var parkingSignView: some View {
        ZStack {
            // Parking sign image
            ZStack {
                Image("NoParkingImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 260, height: 260)
                
                // Text overlay with premium glow
                VStack(spacing: 5) {
                    // Dynamic time display from schedule
                    if let schedule = schedule {
                        scheduleTimeDisplay(schedule)
                        scheduleInfoDisplay(schedule)
                    } else {
                        // Fallback display when no schedule
                        Text("NO RESTRICTIONS")
                            .font(.custom("HighwayGothic", size: 24))
                            .foregroundColor(Color(red: 1.0, green: 0.0, blue: 0.0))
                            .tracking(1.0)
                    }
                }
                .padding(.top, 15)
            }
        }
        .rotation3DEffect(
            .degrees(rotationX * 0.3),
            axis: (x: 1, y: 0, z: 0),
            perspective: 1.5
        )
        .rotation3DEffect(
            .degrees(rotationY * 0.3),
            axis: (x: 0, y: 1, z: 0),
            perspective: 1.5
        )
        .shadow(
            color: .black.opacity(0.3),
            radius: 8,
            x: rotationY * 0.2,
            y: rotationX * 0.2 + 4
        )
        .onReceive(motionManager.motionUpdatePublisher) { motion in
            withAnimation(.easeOut(duration: 0.2)) {
                // Use gravity vector for natural movement (phone held screen outward/upward)
                let gravity = motion.gravity
                // Offset for screen-out orientation - subtract base tilt
                rotationX = (-gravity.y - 0.4) * 25  // Tilted upward baseline
                rotationY = -gravity.x * 25  // Left/right tilt unchanged
            }
        }
        .onAppear {
            motionManager.startUpdates()
        }
        .onDisappear {
            motionManager.stopUpdates()
        }
    }
    
    
    
    
    private var bottomButton: some View {
        Button(action: {
            impactFeedbackLight.impactOccurred()
            dismiss()
        }) {
            Text("Looks Good")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.blue)
                .cornerRadius(16)
        }
    }
    
    // MARK: - Helper Properties
    
    private var timeAgoText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: parkingLocation.timestamp, relativeTo: Date())
    }
    
    private var scheduleUrgencyColor: Color {
        guard let schedule = schedule else { return .gray }
        let hoursUntil = schedule.date.timeIntervalSinceNow / 3600
        
        if hoursUntil < 2 {
            return .red
        } else if hoursUntil < 24 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var scheduleUrgencyText: String {
        guard let schedule = schedule else { return "" }
        let hoursUntil = schedule.date.timeIntervalSinceNow / 3600
        
        if hoursUntil < 0 {
            return "Happening Now"
        } else if hoursUntil < 2 {
            return "Very Soon"
        } else if hoursUntil < 24 {
            return "Today"
        } else {
            return "Upcoming"
        }
    }
    
    private var scheduleTimeRemaining: String {
        guard let schedule = schedule else { return "" }
        let timeInterval = schedule.date.timeIntervalSinceNow
        
        if timeInterval < 0 {
            return "Move now"
        }
        
        let hours = Int(timeInterval / 3600)
        let minutes = Int((timeInterval.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 24 {
            let days = hours / 24
            return "\(days) day\(days == 1 ? "" : "s")"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
    
    private func formatDateAndTime(_ date: Date, startTime: String, endTime: String) -> String {
        let calendar = Calendar.current
        
        let formatTime = { (time: String) -> String in
            return time
                .replacingOccurrences(of: ":00", with: "")
                .replacingOccurrences(of: " AM", with: "am")
                .replacingOccurrences(of: " PM", with: "pm")
        }
        
        let formattedStartTime = formatTime(startTime)
        let formattedEndTime = formatTime(endTime)
        
        if calendar.isDateInToday(date) {
            return "Today, \(formattedStartTime) - \(formattedEndTime)"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow, \(formattedStartTime) - \(formattedEndTime)"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            let dateString = formatter.string(from: date)
            return "\(dateString), \(formattedStartTime) - \(formattedEndTime)"
        }
    }
    
    private func formatPreciseTimeUntil(_ date: Date) -> String {
        let timeInterval = date.timeIntervalSinceNow
        let totalSeconds = Int(timeInterval)
        
        if totalSeconds <= 0 {
            return "Happening Now"
        }
        
        if totalSeconds < 120 {
            if totalSeconds < 60 {
                return "In Under 1 Minute"
            } else {
                return "In 1 Minute"
            }
        }
        
        let minutes = totalSeconds / 60
        let hours = minutes / 60
        let days = hours / 24
        let remainingHours = hours % 24
        let remainingMinutes = minutes % 60
        
        if hours < 1 {
            return "In \(minutes) Minute\(minutes == 1 ? "" : "s")"
        }
        
        if hours < 12 {
            if remainingMinutes < 10 {
                return "In \(hours) Hour\(hours == 1 ? "" : "s")"
            } else if remainingMinutes < 40 {
                return "In \(hours)½ Hours"
            } else {
                return "In \(hours + 1) Hours"
            }
        }
        
        if hours >= 12 && hours < 36 {
            let calendar = Calendar.current
            if calendar.isDateInTomorrow(date) {
                return "Tomorrow"
            } else if hours < 24 {
                return "In \(hours) Hours"
            }
        }
        
        if hours >= 36 && hours < 60 {
            if remainingHours < 6 {
                return "In \(days) Day\(days == 1 ? "" : "s")"
            } else if remainingHours < 18 {
                return "In \(days)½ Days"
            } else {
                return "In \(days + 1) Days"
            }
        }
        
        if days >= 2 && days < 7 {
            if remainingHours < 12 {
                return "In \(days) Days"
            } else {
                return "In \(days + 1) Days"
            }
        }
        
        let weeks = days / 7
        if weeks >= 1 && weeks < 4 {
            let remainingDays = days % 7
            if weeks == 1 && remainingDays <= 1 {
                return "In 1 Week"
            } else if remainingDays <= 3 {
                return "In \(weeks) Week\(weeks == 1 ? "" : "s")"
            } else {
                return "In \(weeks + 1) Weeks"
            }
        }
        
        return "In \(days) Days"
    }
    
    private func parseScheduleDay(_ dayOfWeek: String) -> String {
        let pattern = dayOfWeek.uppercased()
        
        // Handle "every" patterns
        if pattern.contains("EVERY") {
            if pattern.contains("MONDAY") { return "EVERY MONDAY" }
            if pattern.contains("TUESDAY") { return "EVERY TUESDAY" }
            if pattern.contains("WEDNESDAY") { return "EVERY WEDNESDAY" }
            if pattern.contains("THURSDAY") { return "EVERY THURSDAY" }
            if pattern.contains("FRIDAY") { return "EVERY FRIDAY" }
            if pattern.contains("SATURDAY") { return "EVERY SATURDAY" }
            if pattern.contains("SUNDAY") { return "EVERY SUNDAY" }
        }
        
        // Handle numbered patterns like "2nd & 4th FRIDAY"
        var ordinals: [String] = []
        if pattern.contains("1ST") { ordinals.append("1ST") }
        if pattern.contains("2ND") { ordinals.append("2ND") }
        if pattern.contains("3RD") { ordinals.append("3RD") }
        if pattern.contains("4TH") { ordinals.append("4TH") }
        if pattern.contains("5TH") { ordinals.append("5TH") }
        
        if !ordinals.isEmpty {
            var dayName = ""
            if pattern.contains("MONDAY") { dayName = "MONDAY" }
            else if pattern.contains("TUESDAY") { dayName = "TUESDAY" }
            else if pattern.contains("WEDNESDAY") { dayName = "WEDNESDAY" }
            else if pattern.contains("THURSDAY") { dayName = "THURSDAY" }
            else if pattern.contains("FRIDAY") { dayName = "FRIDAY" }
            else if pattern.contains("SATURDAY") { dayName = "SATURDAY" }
            else if pattern.contains("SUNDAY") { dayName = "SUNDAY" }
            
            if ordinals.count == 1 {
                return "\(ordinals[0]) \(dayName)"
            } else {
                let joinedOrdinals = ordinals.joined(separator: " and ")
                return "\(joinedOrdinals) \(dayName)"
            }
        }
        
        // Fallback
        return pattern
    }
    
    private func extractStreetName(from address: String) -> String {
        // Remove common suffixes and prefixes to get just the street name
        let components = address.components(separatedBy: ",")
        let streetPart = components.first ?? address
        
        // Remove numbers at the beginning
        let withoutNumbers = streetPart.replacingOccurrences(
            of: "^\\d+\\s*", 
            with: "", 
            options: .regularExpression
        )
        
        return withoutNumbers.trimmingCharacters(in: .whitespaces).uppercased()
    }
}

// MARK: - Device Motion Manager for Trading Card Effect
class DeviceMotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    let motionUpdatePublisher = PassthroughSubject<CMDeviceMotion, Never>()
    
    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0 // 30 FPS for smoother performance
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let motion = motion, error == nil else { return }
            self?.motionUpdatePublisher.send(motion)
        }
    }
    
    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: - Extensions
extension Color {
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
}

#Preview {
    SchedulesView(
        vehicle: Vehicle(
            name: "My Car",
            type: .car,
            color: .blue,
            parkingLocation: ParkingLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                address: "123 Market Street",
                timestamp: Date().addingTimeInterval(-3600),
                source: .manual,
                selectedSchedule: nil
            )
        ),
        parkingLocation: ParkingLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            address: "123 Market Street",
            timestamp: Date().addingTimeInterval(-3600),
            source: .manual,
            selectedSchedule: nil
        ),
        schedule: UpcomingSchedule(
            streetName: "Market Street",
            date: Date().addingTimeInterval(7200),
            endDate: Date().addingTimeInterval(14400),
            dayOfWeek: "WEDNESDAY",
            startTime: "9:00 AM",
            endTime: "11:00 AM",
            avgSweeperTime: 9.75,
            medianSweeperTime: 9.5
        ),
        originalSchedule: SweepSchedule(
            cnn: "123456",
            corridor: "Market Street",
            limits: "Block 100-200",
            blockside: "North",
            fullname: "Market Street",
            weekday: "WED",
            fromhour: "9",
            tohour: "11",
            week1: "N",
            week2: "Y",
            week3: "N",
            week4: "Y",
            week5: "N",
            holidays: "N",
            line: nil
        )
    )
}
