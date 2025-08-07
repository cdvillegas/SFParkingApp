import SwiftUI

struct ActiveScheduleCard: View {
    let schedule: UpcomingSchedule?
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(schedule?.urgencyColor ?? .gray)
                    .frame(width: 40, height: 40)
                
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                // Line 1: Street Cleaning
                Text("Street Cleaning")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if let schedule = schedule {
                    // Line 2: Date and Time
                    Text(schedule.formatDateAndTime())
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    // Line 2.5: Predicted sweep time (optional)
                    if let estimatedTime = schedule.estimatedSweeperTime {
                        Text("Typically arrives ~\(estimatedTime)")
                            .font(.system(size: 13))
                            .foregroundColor(.orange)
                    }
                    
                    // Line 3: Time remaining (with extra spacing above)
                    Text(schedule.formatTimeUntil())
                        .font(.system(size: 15))
                        .foregroundColor(schedule.urgencyColor)
                        .padding(.top, 2)
                } else {
                    Text("No schedule available")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
    }
}

#Preview {
    let sampleSchedule = UpcomingSchedule(
        streetName: "Market Street",
        date: Date().addingTimeInterval(7 * 24 * 3600), // 1 week from now
        endDate: Date().addingTimeInterval(7 * 24 * 3600 + 7200), // 2 hours later
        dayOfWeek: "WEDNESDAY",
        startTime: "9:00 AM",
        endTime: "11:00 AM",
        avgSweeperTime: 9.5, // 9:30 AM
        medianSweeperTime: 9.5 // 9:30 AM
    )
    
    VStack(spacing: 20) {
        ActiveScheduleCard(schedule: sampleSchedule)
            .padding(16)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
        
        ActiveScheduleCard(schedule: nil)
            .padding(16)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
    }
    .padding()
}