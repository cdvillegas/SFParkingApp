//
//  CustomReminderEditorView.swift
//  SF Parking App
//
//  Created by Claude on 7/16/25.
//

import SwiftUI

struct DayTiming: CaseIterable, Equatable, Hashable {
    static let morning = DayTiming(title: "Morning", hour: 8)
    static let evening = DayTiming(title: "Evening", hour: 17)
    
    let title: String
    let hour: Int
    
    static let allCases = [morning, evening]
}

struct CustomReminderEditorView: View {
    let reminderToEdit: CustomReminder?
    let schedule: UpcomingSchedule
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var notificationManager = NotificationManager.shared
    
    @State private var amount: Int = 1
    @State private var unit: TimeUnit = .hours
    @State private var dayTiming: DayTiming = DayTiming.morning
    @State private var showingDuplicateAlert = false
    @State private var pendingReminder: CustomReminder?
    
    private let impactFeedback = UIImpactFeedbackGenerator(style: .rigid)
    
    private var isEditing: Bool {
        reminderToEdit != nil
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea(.all)
            
            NavigationView {
                VStack(spacing: 0) {
                    // Fixed header
                    headerSection
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 20)
                    
                    // Reminder preview
                    reminderPreviewCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    
                    // Main content area
                    VStack(spacing: 24) {
                        timingSection
                        
                        // Always show day timing section with consistent height
                        dayTimingSection
                            .opacity(unit == .days ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.3), value: unit)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .navigationBarHidden(true)
                .overlay(alignment: .bottom) {
                    // Fixed bottom buttons with gradient fade
                    VStack(spacing: 0) {
                        // Smooth gradient fade
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color(.systemBackground)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 50)
                        
                        // Button area
                        VStack(spacing: 0) {
                            buttonsSection
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                        }
                        .background(Color(.systemBackground))
                    }
                }
            }
            .background(Color.clear)
        }
        .onAppear {
            loadExistingReminder()
        }
        .alert("Duplicate Reminder", isPresented: $showingDuplicateAlert) {
            Button("Keep Both") {
                if let reminder = pendingReminder {
                    let _ = notificationManager.addCustomReminderForced(reminder)
                    impactFeedback.impactOccurred()
                    onDismiss()
                }
            }
            Button("Cancel", role: .cancel) {
                pendingReminder = nil
            }
        } message: {
            Text("You already have a similar reminder. Would you like to keep both reminders?")
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isEditing ? "Edit Reminder" : "Add Reminder")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    onDismiss()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                        Text("Back")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color(.systemGray4), Color(.systemGray5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(20)
                    .shadow(color: Color(.systemGray4).opacity(0.3), radius: 6, x: 0, y: 3)
                }
            }
        }
    }
    
    private var streetInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.streetName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(formatDateAndTime(schedule.date, startTime: schedule.startTime, endTime: schedule.endTime))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var reminderPreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(generateTitle())
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .animation(.easeInOut(duration: 0.2), value: unit)
                        .animation(.easeInOut(duration: 0.2), value: amount)
                        .animation(.easeInOut(duration: 0.2), value: dayTiming)
                    
                    Text(generateReminderDateTime())
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .animation(.easeInOut(duration: 0.2), value: unit)
                        .animation(.easeInOut(duration: 0.2), value: amount)
                        .animation(.easeInOut(duration: 0.2), value: dayTiming)
                }
                
                Spacer()
            }
            .padding(16)
            .background(.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private var timingSection: some View {
        // Native iOS-style wheel pickers
        HStack(spacing: 24) {
            // Amount picker
            Picker("Amount", selection: $amount) {
                if unit == .minutes {
                    ForEach(Array(stride(from: 5, through: maxAmount, by: 5)), id: \.self) { value in
                        Text("\(value)")
                            .font(.system(size: 28, weight: .medium))
                            .tag(value)
                    }
                } else {
                    ForEach(1...maxAmount, id: \.self) { value in
                        Text("\(value)")
                            .font(.system(size: 28, weight: .medium))
                            .tag(value)
                    }
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 100, height: 160)
            .clipped()
            
            // Unit picker
            Picker("Unit", selection: $unit) {
                ForEach([TimeUnit.minutes, TimeUnit.hours, TimeUnit.days], id: \.self) { timeUnit in
                    Text(amount == 1 ? timeUnit.singularName.capitalized : timeUnit.pluralName.capitalized)
                        .font(.system(size: 28, weight: .medium))
                        .tag(timeUnit)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 140, height: 160)
            .clipped()
            .onChange(of: unit) { _, newUnit in
                // Adjust amount if it exceeds the new max or if switching to minutes
                if amount > maxAmount {
                    amount = maxAmount
                } else if newUnit == .minutes && amount % 5 != 0 {
                    // Round to nearest 5 for minutes
                    amount = ((amount + 2) / 5) * 5
                    if amount == 0 { amount = 5 }
                }
                // Reduced haptic feedback for state changes
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }
    
    private var dayTimingSection: some View {
        VStack(alignment: .leading) {
            // Simple segmented control
            HStack(spacing: 4) {
                ForEach(DayTiming.allCases, id: \.self) { timing in
                    Button(action: {
                        dayTiming = timing
                    }) {
                        Text(timing.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(dayTiming == timing ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(dayTiming == timing ? Color.secondary.opacity(0.15) : Color.clear)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(2)
            .background(.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(10)
        }
    }
    
    private var buttonsSection: some View {
        VStack(spacing: 12) {
            // Save button
            Button(action: saveReminder) {
                Text(isEditing ? "Update Reminder" : "Save Reminder")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
        }
    }
    
    // MARK: - Computed Properties
    
    private var displayText: String {
        let amountText = "\(amount)"
        let unitText = amount == 1 ? unit.singularName : unit.pluralName
        return "\(amountText) \(unitText)"
    }
    
    private var maxAmount: Int {
        switch unit {
        case .minutes: return 60
        case .hours: return 12
        case .days: return 10
        case .weeks: return 4
        }
    }
    
    private func unitDisplayText(for timeUnit: TimeUnit) -> String {
        amount == 1 ? timeUnit.singularName.capitalized : timeUnit.pluralName.capitalized
    }
    
    // MARK: - Methods
    
    private func loadExistingReminder() {
        guard let reminder = reminderToEdit else { return }
        
        switch reminder.timing {
        case .custom(let custom):
            amount = custom.amount
            unit = custom.unit
            if custom.unit == .days {
                dayTiming = custom.specificTime?.hour == 8 ? .morning : .evening
            }
        case .preset(_):
            // Legacy preset - use defaults
            amount = 1
            unit = .hours
        }
    }
    
    private func saveReminder() {
        let specificTime: TimeOfDay? = unit == .days ? TimeOfDay(hour: dayTiming.hour, minute: 0) : nil
        
        let customTiming = CustomTiming(
            amount: amount,
            unit: unit,
            relativeTo: .beforeCleaning,
            specificTime: specificTime
        )
        
        let title = generateTitle()
        
        if let existingReminder = reminderToEdit {
            var updatedReminder = existingReminder
            updatedReminder.title = title
            updatedReminder.timing = .custom(customTiming)
            notificationManager.updateCustomReminder(updatedReminder)
        } else {
            let newReminder = CustomReminder(
                title: title,
                timing: .custom(customTiming),
                isActive: true
            )
            
            let result = notificationManager.addCustomReminder(newReminder)
            
            switch result {
            case .success:
                impactFeedback.impactOccurred()
                onDismiss()
            case .duplicate:
                pendingReminder = newReminder
                showingDuplicateAlert = true
            case .maxReached:
                impactFeedback.impactOccurred()
                onDismiss()
            }
            return // Don't execute the code below
        }
        
        impactFeedback.impactOccurred()
        onDismiss()
    }
    
    
    private func generateTitle() -> String {
        let unitText = amount == 1 ? "1 \(unit.singularName)" : "\(amount) \(unit.pluralName)"
        
        return "\(unitText.capitalized) Before"
    }
    
    private func formatDateAndTime(_ date: Date, startTime: String, endTime: String) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today • \(startTime) - \(endTime)"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow • \(startTime) - \(endTime)"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            return "\(formatter.string(from: date)) • \(startTime) - \(endTime)"
        }
    }
    
    private func calculateReminderTime() -> String {
        // For days, show simple timing text
        if unit == .days {
            let timingText = dayTiming.title.lowercased()
            let timeString = dayTiming.hour < 12 ? "8:00 AM" : "5:00 PM"
            return "in the \(timingText) at \(timeString)"
        }
        
        // For other units, don't show second line
        return ""
    }
    
    private func generateReminderDateTime() -> String {
        // Calculate the reminder notification date based on schedule and timing
        let calendar = Calendar.current
        let now = Date()
        
        // Create a sample reminder date based on the current settings
        let reminderDate: Date
        
        if unit == .days {
            // For days, calculate based on schedule date and day timing
            var components = calendar.dateComponents([.year, .month, .day], from: schedule.date)
            components.hour = dayTiming.hour
            components.minute = 0
            
            if amount > 0 {
                // Subtract days
                components.day = (components.day ?? 0) - amount
            }
            
            reminderDate = calendar.date(from: components) ?? schedule.date
        } else {
            // For hours/minutes, subtract from schedule start time
            let timeInterval = TimeInterval(amount * (unit == .hours ? 3600 : 60))
            reminderDate = schedule.date.addingTimeInterval(-timeInterval)
        }
        
        // Format similar to upcoming schedule
        if calendar.isDateInToday(reminderDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mma"
            let timeString = formatter.string(from: reminderDate)
                .replacingOccurrences(of: "AM", with: "am")
                .replacingOccurrences(of: "PM", with: "pm")
            return "Today, \(timeString)"
        } else if calendar.isDateInTomorrow(reminderDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mma"
            let timeString = formatter.string(from: reminderDate)
                .replacingOccurrences(of: "AM", with: "am")
                .replacingOccurrences(of: "PM", with: "pm")
            return "Tomorrow, \(timeString)"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d, h:mma"
            let dateString = formatter.string(from: reminderDate)
                .replacingOccurrences(of: "AM", with: "am")
                .replacingOccurrences(of: "PM", with: "pm")
            return dateString
        }
    }
}

#Preview("Light Mode") {
    let schedule = UpcomingSchedule(
        streetName: "Mission Street",
        date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
        endDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())?.addingTimeInterval(7200) ?? Date(),
        dayOfWeek: "Tomorrow",
        startTime: "8:00 AM",
        endTime: "10:00 AM"
    )
    
    return CustomReminderEditorView(
        reminderToEdit: nil,
        schedule: schedule,
        onDismiss: {}
    )
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    let schedule = UpcomingSchedule(
        streetName: "Mission Street",
        date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
        endDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())?.addingTimeInterval(7200) ?? Date(),
        dayOfWeek: "Tomorrow",
        startTime: "8:00 AM",
        endTime: "10:00 AM"
    )
    
    return CustomReminderEditorView(
        reminderToEdit: nil,
        schedule: schedule,
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Editing Reminder") {
    let customTiming = CustomTiming(
        amount: 2,
        unit: .hours,
        relativeTo: .beforeCleaning,
        specificTime: nil
    )
    
    let reminderToEdit = CustomReminder(
        title: "2 Hours Before",
        timing: .custom(customTiming),
        isActive: true
    )
    
    let schedule = UpcomingSchedule(
        streetName: "Mission Street",
        date: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
        endDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())?.addingTimeInterval(7200) ?? Date(),
        dayOfWeek: "Tomorrow",
        startTime: "8:00 AM",
        endTime: "10:00 AM"
    )
    
    return CustomReminderEditorView(
        reminderToEdit: reminderToEdit,
        schedule: schedule,
        onDismiss: {}
    )
    .preferredColorScheme(.light)
}
