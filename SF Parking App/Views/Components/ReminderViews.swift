//
//  ReminderViews.swift
//  SF Parking App
//
//  Created by Chris Villegas on 6/22/25.
//

import SwiftUI

struct LoadingReminderView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Loading...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ActiveReminderView: View {
    let schedule: UpcomingSchedule
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(schedule.isUrgent ? .red : .orange)
                .font(.body)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.relativeTimeString)  // Changed this line
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(schedule.formattedDate)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ErrorReminderView: View {
    let onRetry: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.gray)
                .font(.body)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Unable to load street data")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                Button("Retry", action: onRetry)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NoRemindersView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.body)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("No upcoming street sweeping")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("You're all clear for now!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    ParkingLocationView()
}

#Preview("Light Mode") {
    ParkingLocationView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ParkingLocationView()
        .preferredColorScheme(.dark)
}

