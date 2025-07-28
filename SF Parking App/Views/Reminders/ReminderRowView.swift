//
//  ReminderRowView.swift
//  SF Parking App
//
//  Created by Claude on 7/16/25.
//

import SwiftUI

struct ReminderRowView: View {
    let reminder: CustomReminder
    let nextCleaningDate: Date?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 24) {
            // Toggle switch instead of icon
            Toggle("", isOn: Binding(
                get: { reminder.isActive },
                set: { newValue in onToggle(newValue) }
            ))
            .labelsHidden()
            .frame(width: 40, height: 40)
            
            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.timing.displayText)
                    .font(.system(size: 18, weight: .semibold))
                
                if let cleaningDate = nextCleaningDate,
                   let reminderDate = reminder.timing.notificationDate(from: cleaningDate) {
                    Text(formatReminderDateTime(reminderDate))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                } else {
                    Text("No upcoming cleaning scheduled")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 3-dot menu
            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.clear)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 0)
        .background(.clear)
        .contentShape(Rectangle())
    }
    
    
    private func formatReminderDateTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today,' EEE 'at' h:mma"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "'Tomorrow,' EEE 'at' h:mma"
        } else {
            // For dates more than tomorrow, show the day of week and date
            let daysUntil = calendar.dateComponents([.day], from: Date(), to: date).day ?? 0
            if daysUntil <= 7 {
                formatter.dateFormat = "EEE, MMM d 'at' h:mma"
            } else {
                formatter.dateFormat = "EEE, MMM d 'at' h:mma"
            }
        }
        
        // Make AM/PM lowercase
        let formattedString = formatter.string(from: date)
        return formattedString
            .replacingOccurrences(of: "AM", with: "am")
            .replacingOccurrences(of: "PM", with: "pm")
    }
}
