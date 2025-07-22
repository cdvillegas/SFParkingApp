import SwiftUI
import UserNotifications

struct UpcomingRemindersSection: View {
    @ObservedObject var streetDataManager: StreetDataManager
    let parkingLocation: ParkingLocation?
    
    
    var body: some View {
        VStack(spacing: 0) {
            if streetDataManager.isLoading {
                loadingState
            } else if let nextSchedule = streetDataManager.nextUpcomingSchedule {
                upcomingAlert(for: nextSchedule)
            } else if streetDataManager.hasError {
                errorState
            } else {
                noRestrictionsState
            }
        }
    }
    
    // MARK: - Loading State
    private var loadingState: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Checking schedule...")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Looking for street cleaning times")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Upcoming Alert
    private func upcomingAlert(for schedule: UpcomingSchedule) -> some View {
        let timeUntil = formatPreciseTimeUntil(schedule.date)
        let urgencyLevel = getUrgencyLevel(for: schedule.date)
        let urgencyStyle = getUrgencyStyle(urgencyLevel)
        
        return HStack(spacing: 16) {
            Image(systemName: urgencyStyle.1)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(urgencyStyle.0)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Street cleaning \(timeUntil)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(formatDateAndTime(schedule.date, startTime: schedule.startTime, endTime: schedule.endTime))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Error State
    private var errorState: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            if let location = parkingLocation {
                streetDataManager.fetchSchedules(for: location.coordinate)
            }
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unable to load schedule")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Tap to retry")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.orange)
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
    }
    
    // MARK: - No Restrictions State
    private var noRestrictionsState: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("You're all clear!")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("No upcoming street sweeping")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 16)
    }
}

// MARK: - Helper Extensions
extension UpcomingRemindersSection {
    enum UrgencyLevel {
        case critical  // < 2 hours
        case warning   // < 24 hours
        case info      // > 24 hours
    }
    
    private func getUrgencyLevel(for date: Date) -> UrgencyLevel {
        let timeInterval = date.timeIntervalSinceNow
        let hours = timeInterval / 3600
        
        if hours < 2 {
            return .critical
        } else if hours < 24 {
            return .warning
        } else {
            return .info
        }
    }
    
    private func getUrgencyStyle(_ level: UrgencyLevel) -> (Color, String) {
        switch level {
        case .critical:
            return (.red, "exclamationmark.triangle.fill")
        case .warning:
            return (.orange, "exclamationmark.triangle")
        case .info:
            return (.blue, "checkmark.circle.fill")
        }
    }
    
    private func formatPreciseTimeUntil(_ date: Date) -> String {
        let timeInterval = date.timeIntervalSinceNow
        let totalSeconds = Int(timeInterval)
        
        // Handle past/current times
        if totalSeconds <= 0 {
            return "happening now"
        }
        
        // Handle very soon (under 2 minutes)
        if totalSeconds < 120 {
            if totalSeconds < 60 {
                return "in under 1 minute"
            } else {
                return "in 1 minute"
            }
        }
        
        let minutes = totalSeconds / 60
        let hours = minutes / 60
        let days = hours / 24
        let remainingHours = hours % 24
        let remainingMinutes = minutes % 60
        
        // Under 1 hour - show minutes
        if hours < 1 {
            return "in \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        
        // Under 12 hours - show hours and be precise
        if hours < 12 {
            if remainingMinutes < 10 {
                return "in \(hours) hour\(hours == 1 ? "" : "s")"
            } else if remainingMinutes < 40 {
                return "in \(hours)½ hours"
            } else {
                return "in \(hours + 1) hours"
            }
        }
        
        // 12-36 hours - special handling for "tomorrow"
        if hours >= 12 && hours < 36 {
            // Check if it's actually tomorrow
            let calendar = Calendar.current
            if calendar.isDateInTomorrow(date) {
                return "tomorrow"
            } else if hours < 24 {
                return "in \(hours) hours"
            }
        }
        
        // 1.5 - 2.5 days - be more precise
        if hours >= 36 && hours < 60 {
            // Round to nearest half day
            if remainingHours < 6 {
                return "in \(days) day\(days == 1 ? "" : "s")"
            } else if remainingHours < 18 {
                return "in \(days)½ days"
            } else {
                return "in \(days + 1) days"
            }
        }
        
        // 2.5 - 6.5 days - round to nearest day
        if days >= 2 && days < 7 {
            if remainingHours < 12 {
                return "in \(days) days"
            } else {
                return "in \(days + 1) days"
            }
        }
        
        // 1+ weeks
        let weeks = days / 7
        if weeks >= 1 && weeks < 4 {
            let remainingDays = days % 7
            if weeks == 1 && remainingDays <= 1 {
                return "in 1 week"
            } else if remainingDays <= 3 {
                return "in \(weeks) week\(weeks == 1 ? "" : "s")"
            } else {
                return "in \(weeks + 1) weeks"
            }
        }
        
        // Default for longer periods
        return "in \(days) days"
    }
    
    private func formatDateAndTime(_ date: Date, startTime: String, endTime: String) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today, \(startTime) - \(endTime)"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow, \(startTime) - \(endTime)"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            let dateString = formatter.string(from: date)
            return "\(dateString), \(startTime) - \(endTime)"
        }
    }
}