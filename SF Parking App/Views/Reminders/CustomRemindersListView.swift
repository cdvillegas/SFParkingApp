//
//  CustomRemindersListView.swift
//  SF Parking App
//
//  Created by Claude on 7/16/25.
//

import SwiftUI

struct CustomRemindersListView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @Binding var showingCustomReminderEditor: Bool
    @Binding var customReminderToEdit: CustomReminder?
    let nextCleaningDate: Date?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if notificationManager.customReminders.isEmpty {
                Spacer()
                
                EmptyRemindersStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Spacer()
            } else {
                VStack(spacing: 0) {
                    ForEach(notificationManager.customReminders, id: \.id) { reminder in
                        ReminderRowView(
                            reminder: reminder,
                            nextCleaningDate: nextCleaningDate,
                            onEdit: {
                                customReminderToEdit = reminder
                                showingCustomReminderEditor = true
                            },
                            onDelete: {
                                notificationManager.removeCustomReminder(withId: reminder.id)
                            },
                            onToggle: { isActive in
                                notificationManager.toggleCustomReminder(withId: reminder.id, isActive: isActive)
                            }
                        )
                        
                        if reminder != notificationManager.customReminders.last {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(.clear)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
