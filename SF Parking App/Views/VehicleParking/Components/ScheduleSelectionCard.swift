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
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Left: Direction pill
                Text(formatSideDescription(scheduleWithSide.side))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.blue : Color(.systemGray5))
                    )
                
                // Right: Schedule details
                VStack(alignment: .leading, spacing: 2) {
                    // Line 1: Week pattern and day
                    Text(formatWeekAndDay(schedule))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Line 2: Time range
                    Text(formatTimeRange(schedule))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.blue.opacity(0.12) : (colorScheme == .dark ? Color(.systemBackground) : Color.white))
                    .shadow(
                        color: isSelected ? Color.blue.opacity(0.4) : Color.black.opacity(0.08),
                        radius: isSelected ? 16 : 6,
                        x: 0,
                        y: isSelected ? 8 : 3
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue.opacity(0.8) : Color(.systemGray6), lineWidth: isSelected ? 3 : 1)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSelected)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(width: 200)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Methods
    
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
