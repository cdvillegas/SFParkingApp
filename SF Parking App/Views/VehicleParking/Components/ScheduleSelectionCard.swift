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
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Schedule info - two line layout
                    VStack(alignment: .leading, spacing: 4) {
                        // Line 1: Street name with direction pill
                        HStack(spacing: 8) {
                            Text(schedule.streetName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            
                            // Direction pill - bigger than before
                            Text(formatSideDescription(scheduleWithSide.side))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isSelected ? .white : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.blue : Color(.systemGray5))
                                )
                        }
                        
                        // Line 2: Full schedule details (no abbreviations)
                        Text(formatFullSchedule(schedule))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isSelected ? .blue : .secondary)
                    }
                    
                    Spacer()
                }
            }
            .padding(20)
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
            .frame(width: 280)
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
}