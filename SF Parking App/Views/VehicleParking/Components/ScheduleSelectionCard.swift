import SwiftUI

struct ScheduleSelectionCard: View {
    let scheduleWithSide: SweepScheduleWithSide
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var schedule: SweepSchedule {
        scheduleWithSide.schedule
    }
    
    // Get urgency color based on schedule timing
    private var urgencyColor: Color {
        // Use the actual next occurrence calculation from StreetDataManager
        let nextOccurrence = calculateNextOccurrence(for: schedule)
        if let nextDate = nextOccurrence {
            let hoursUntil = nextDate.timeIntervalSinceNow / 3600
            return hoursUntil < 24 ? .red : .green
        }
        return .green
    }
    
    // Check if cleaning is today and hasn't ended yet
    private var isCleaningActiveToday: Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now) // 1 = Sunday, 7 = Saturday
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentTimeInMinutes = currentHour * 60 + currentMinute
        
        // Map weekday names to numbers (1 = Sunday, 7 = Saturday)
        let weekdayMap: [String: Int] = [
            "Sunday": 1, "Sun": 1,
            "Monday": 2, "Mon": 2,
            "Tuesday": 3, "Tues": 3, "Tue": 3,
            "Wednesday": 4, "Wed": 4,
            "Thursday": 5, "Thu": 5, "Thurs": 5,
            "Friday": 6, "Fri": 6,
            "Saturday": 7, "Sat": 7
        ]
        
        // Check if the schedule is for today
        if let scheduleWeekday = schedule.weekday,
           let scheduleDayNumber = weekdayMap[scheduleWeekday],
           scheduleDayNumber == currentWeekday {
            
            // Parse end time from tohour field
            if let endHourString = schedule.tohour,
               let endHour = Int(endHourString) {
                let endTimeInMinutes = endHour * 60
                
                // Return true if current time is before the end time
                return currentTimeInMinutes < endTimeInMinutes
            }
        }
        
        return false
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Left: Direction indicator as pill
                Text(formatSideDescription(scheduleWithSide.side))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isSelected ? urgencyColor : Color.secondary)
                    )
                    .shadow(
                        color: (isSelected ? urgencyColor : Color.secondary).opacity(0.3),
                        radius: 3,
                        x: 0,
                        y: 1
                    )
                
                // Right: Schedule details - matching vehicle card text layout exactly
                VStack(alignment: .leading, spacing: 4) {
                    // Line 1: Week pattern and day - matching parking address style
                    Text(formatWeekAndDay(schedule))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .shadow(
                            color: isSelected ? urgencyColor.opacity(0.3) : Color.clear,
                            radius: isSelected ? 3 : 0,
                            x: 0,
                            y: 0
                        )
                    
                    // Line 2: Time range - matching "Move by" text style
                    Text(formatTimeRange(schedule))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .shadow(
                            color: isSelected ? urgencyColor.opacity(0.2) : Color.clear,
                            radius: isSelected ? 2 : 0,
                            x: 0,
                            y: 0
                        )
                }
                
                Spacer()
            }
            .opacity(isSelected ? 1.0 : 0.4)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Methods
    
    private enum UrgencyLevel {
        case critical  // < 24 hours
        case safe      // >= 24 hours
    }
    
    private func calculateNextOccurrence(for schedule: SweepSchedule) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        
        guard let weekday = schedule.weekday,
              let fromHour = schedule.fromhour,
              let startHour = Int(fromHour) else {
            return nil
        }
        
        let weekdayNum = dayStringToWeekday(weekday)
        guard weekdayNum > 0 else { return nil }
        
        // Look ahead for up to 3 months to find valid occurrences
        for monthOffset in 0..<3 {
            guard let futureMonth = calendar.date(byAdding: .month, value: monthOffset, to: now) else { continue }
            
            // Get all occurrences of the target weekday in this month
            let monthOccurrences = getAllWeekdayOccurrencesInMonth(weekday: weekdayNum, month: futureMonth, calendar: calendar)
            
            for (weekNumber, weekdayDate) in monthOccurrences.enumerated() {
                let weekPos = weekNumber + 1
                let applies = doesScheduleApplyToWeek(weekNumber: weekPos, schedule: schedule)
                
                if applies {
                    // Create the actual start time for this occurrence
                    guard let scheduleDateTime = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: weekdayDate) else { continue }
                    
                    // Only include if the schedule time is in the future
                    if scheduleDateTime > now {
                        return scheduleDateTime
                    }
                }
            }
        }
        
        return nil
    }
    
    private func getAllWeekdayOccurrencesInMonth(weekday: Int, month: Date, calendar: Calendar) -> [Date] {
        var occurrences: [Date] = []
        
        // Get the first day of the month
        let monthComponents = calendar.dateComponents([.year, .month], from: month)
        guard let firstDayOfMonth = calendar.date(from: monthComponents) else { return [] }
        
        // Find the first occurrence of the target weekday in this month
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        var daysToAdd = weekday - firstWeekday
        if daysToAdd < 0 {
            daysToAdd += 7
        }
        
        guard let firstOccurrence = calendar.date(byAdding: .day, value: daysToAdd, to: firstDayOfMonth) else { return [] }
        
        // Add all occurrences of this weekday in the month (typically 4-5 times)
        var currentDate = firstOccurrence
        while calendar.component(.month, from: currentDate) == calendar.component(.month, from: month) {
            occurrences.append(currentDate)
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentDate) else { break }
            currentDate = nextWeek
        }
        
        return occurrences
    }
    
    private func doesScheduleApplyToWeek(weekNumber: Int, schedule: SweepSchedule) -> Bool {
        switch weekNumber {
        case 1: return schedule.week1 == "1"
        case 2: return schedule.week2 == "1"
        case 3: return schedule.week3 == "1"
        case 4: return schedule.week4 == "1"
        case 5: return schedule.week5 == "1"
        default: return false
        }
    }
    
    private func dayStringToWeekday(_ dayString: String) -> Int {
        let normalizedDay = dayString.lowercased().trimmingCharacters(in: .whitespaces)
        
        switch normalizedDay {
        case "sun", "sunday": return 1
        case "mon", "monday": return 2
        case "tue", "tues", "tuesday": return 3
        case "wed", "wednesday": return 4
        case "thu", "thur", "thursday": return 5
        case "fri", "friday": return 6
        case "sat", "saturday": return 7
        default: return 0
        }
    }
    
    private func formatSideDescription(_ side: String) -> String {
        let cleaned = side.lowercased()
        if cleaned.contains("north") { return "North" }
        if cleaned.contains("south") { return "South" }
        if cleaned.contains("east") { return "East" }
        if cleaned.contains("west") { return "West" }
        return side.capitalized
    }
    
    private func formatFullSchedule(_ schedule: SweepSchedule) -> String {
        let pattern = getFullWeekPattern(schedule)
        let dayFull = schedule.sweepDay // Full day name
        let startTime = formatTime(schedule.startTime)
        let endTime = formatTime(schedule.endTime)
        return "\(pattern) \(dayFull), \(startTime) to \(endTime)"
    }
    
    private func formatCompactSchedule(_ schedule: SweepSchedule) -> String {
        let pattern = getCompactWeekPattern(schedule)
        let dayShort = getDayAbbreviation(schedule.sweepDay)
        let startTime = formatTime(schedule.startTime)
        let endTime = formatTime(schedule.endTime)
        return "\(pattern) \(dayShort), \(startTime)-\(endTime)"
    }
    
    private func formatWeekAndDay(_ schedule: SweepSchedule) -> String {
        let pattern = getCompactWeekPattern(schedule)
        let dayShort = getDayAbbreviation(schedule.sweepDay)
        
        // If the day is already "Daily" (from consolidation), don't add "Every"
        if dayShort == "Daily" {
            return dayShort
        }
        
        // If pattern is "Every" and we have consolidated weekdays, just use the weekdays
        if pattern == "Every" && (dayShort.contains(",") || dayShort == "Weekdays" || dayShort == "Weekends" || dayShort.contains("-")) {
            return dayShort
        }
        
        return "\(pattern) \(dayShort)"
    }
    
    private func formatTimeRange(_ schedule: SweepSchedule) -> String {
        let startTime = formatTime(schedule.startTime)
        let endTime = formatTime(schedule.endTime)
        return "\(startTime) - \(endTime)"
    }
    
    private func formatTime(_ time: String) -> String {
        // Remove :00 from times like "9:00 AM" -> "9 AM"
        return time.replacingOccurrences(of: ":00", with: "")
    }
    
    private func getFullWeekPattern(_ schedule: SweepSchedule) -> String {
        let weeks = [
            schedule.week1 == "1",
            schedule.week2 == "1",
            schedule.week3 == "1",
            schedule.week4 == "1",
            schedule.week5 == "1"
        ]
        
        if weeks == [true, false, true, false, true] {
            return "1st, 3rd, and 5th"
        } else if weeks == [false, true, false, true, false] {
            return "2nd and 4th"
        } else if weeks == [true, false, true, false, false] {
            return "1st and 3rd"
        } else if weeks.allSatisfy({ $0 }) {
            return "Every"
        } else {
            return "Select weeks"
        }
    }
    
    private func getCompactWeekPattern(_ schedule: SweepSchedule) -> String {
        let weeks = [
            schedule.week1 == "1",
            schedule.week2 == "1",
            schedule.week3 == "1",
            schedule.week4 == "1",
            schedule.week5 == "1"
        ]
        
        if weeks == [true, false, true, false, true] {
            return "1st, 3rd, 5th"
        } else if weeks == [false, true, false, true, false] {
            return "2nd, 4th"
        } else if weeks == [true, false, true, false, false] {
            return "1st, 3rd"
        } else if weeks.allSatisfy({ $0 }) {
            return "Every"
        } else {
            return "Select"
        }
    }
    
    private func getDayAbbreviation(_ day: String) -> String {
        switch day.lowercased() {
        case "monday": return "Mon"
        case "tuesday": return "Tues"
        case "wednesday": return "Wed"
        case "thursday": return "Thurs"
        case "friday": return "Fri"
        case "saturday": return "Sat"
        case "sunday": return "Sun"
        default: return day
        }
    }
}

// MARK: - Auto-Scrolling Text Component

struct AutoScrollingText: View {
    let text: String
    let isSelected: Bool
    let font: Font
    let color: Color
    
    @State private var scrollOffset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            Text(text)
                .font(font)
                .foregroundColor(color)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { textGeometry in
                        Color.clear
                            .onAppear {
                                textWidth = textGeometry.size.width
                                containerWidth = geometry.size.width
                            }
                            .onChange(of: geometry.size.width) { _, newWidth in
                                containerWidth = newWidth
                            }
                    }
                )
                .offset(x: scrollOffset)
                .clipped()
                .onAppear {
                    if isSelected {
                        startAutoScroll()
                    }
                }
                .onChange(of: isSelected) { _, newValue in
                    if newValue {
                        startAutoScroll()
                    } else {
                        stopAutoScroll()
                    }
                }
        }
    }
    
    private func startAutoScroll() {
        // Only scroll if text is wider than container
        guard textWidth > containerWidth else {
            scrollOffset = 0
            return
        }
        
        let maxOffset = textWidth - containerWidth
        
        // Reset to start
        scrollOffset = 0
        
        // Animate to end, then back to start, then repeat
        withAnimation(.linear(duration: 2.0).delay(0.5)) {
            scrollOffset = -maxOffset
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard isSelected else { return }
            
            withAnimation(.linear(duration: 2.0).delay(0.5)) {
                scrollOffset = 0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard isSelected else { return }
                startAutoScroll() // Repeat
            }
        }
    }
    
    private func stopAutoScroll() {
        withAnimation(.easeOut(duration: 0.3)) {
            scrollOffset = 0
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
