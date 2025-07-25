//
//  RemindersSheet.swift
//  SF Parking App
//
//  Created by Chris Villegas on 7/15/25.
//

import SwiftUI

struct RemindersSheet: View {
    let schedule: UpcomingSchedule
    let parkingLocation: ParkingLocation?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingPermissionAlert = false
    @State private var isSettingUpNotifications = false
    @State private var setupComplete = false
    @State private var notificationsEnabled = false
    @State private var showingPermissionPrompt = false
    @State private var showingCustomReminderEditor = false
    @State private var customReminderToEdit: CustomReminder? = nil
    @State private var showingDuplicateAlert = false
    @State private var pendingReminder: CustomReminder?
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var hasLoggedOpen = false
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea(.all)
            
            NavigationView {
                VStack(spacing: 0) {
                    // Fixed header
                    headerSection
                        .padding(.horizontal, 20)
                        .padding(.top, 40)
                        .padding(.bottom, 24)
                    
                    // Fixed street info card - only show if there's a real upcoming schedule
                    if schedule.dayOfWeek != "Next Week" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("UPCOMING SCHEDULE")
                                .font(.footnote)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                                .onAppear {
                                    if !hasLoggedOpen {
                                        AnalyticsManager.shared.logRemindersSheetOpened()
                                        hasLoggedOpen = true
                                    }
                                }
                            
                            streetInfoCard
                                .background(.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                                .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 20)
                    }
                    
                    // Always show the Active Reminders section title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MY REMINDERS")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        
                        // Scrollable content - unified for all states
                        ScrollView {
                            VStack(spacing: 24) {
                                // Show unified empty state for both notifications disabled and no reminders
                                if !notificationsEnabled || notificationManager.customReminders.isEmpty {
                                    UnifiedEmptyStateView(isNotificationsDisabled: !notificationsEnabled)
                                        .frame(minHeight: 300) // Give it consistent height for centering
                                } else {
                                    // Only custom reminders section
                                    CustomRemindersListView(
                                        showingCustomReminderEditor: $showingCustomReminderEditor,
                                        customReminderToEdit: $customReminderToEdit,
                                        nextCleaningDate: schedule.date
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 120) // Add bottom padding to ensure content doesn't get hidden behind button
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .navigationBarHidden(true)
                .overlay(alignment: .bottom) {
                    // Fixed bottom button with gradient fade
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
                        
                        // Button area with solid background
                        VStack(spacing: 0) {
                            if !notificationsEnabled {
                                // User needs to enable notifications first
                                enableNotificationsButton
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 20)
                            } else {
                                // User has notifications enabled, show the normal action button
                                actionButton
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 20)
                            }
                        }
                        .background(Color(.systemBackground))
                    }
                }
            }
            .background(Color.clear)
        }
        .onAppear {
            checkNotificationPermissions()
            notificationManager.loadCustomReminders()
            
            // Listen for app becoming active (user returning from Settings)
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                checkNotificationPermissions()
            }
        }
        .alert("Enable Notifications", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To receive parking reminders, please enable notifications in Settings.")
        }
        .alert("Duplicate Reminder", isPresented: $showingDuplicateAlert) {
            Button("Keep Both") {
                if let reminder = pendingReminder {
                    let _ = notificationManager.addCustomReminderForced(reminder)
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }
            }
            Button("Cancel", role: .cancel) {
                pendingReminder = nil
            }
        } message: {
            Text("You already have a similar reminder. Would you like to keep both reminders?")
        }
        .sheet(isPresented: $showingCustomReminderEditor) {
            CustomReminderEditorView(
                reminderToEdit: customReminderToEdit,
                schedule: schedule,
                onDismiss: {
                    showingCustomReminderEditor = false
                    customReminderToEdit = nil
                }
            )
        }
    }
    
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reminders")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Only show Add button when notifications are enabled
                if notificationsEnabled {
                    Menu {
                        Button {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            createPresetReminder(title: "Evening Before", amount: 1, unit: .days, timing: .evening)
                        } label: {
                            Label("Evening Before", systemImage: "moon.fill")
                        }
                        Button {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            createPresetReminder(title: "Morning Of", amount: 0, unit: .days, timing: .morning)
                        } label: {
                            Label("Morning Of", systemImage: "sun.max.fill")
                        }
                        Button {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            createPresetReminder(title: "30 Minutes Before", amount: 30, unit: .minutes, timing: nil)
                        } label: {
                            Label("30 Minutes Before", systemImage: "clock.fill")
                        }
                        Button {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            customReminderToEdit = nil
                            showingCustomReminderEditor = true
                        } label: {
                            Label("Custom", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                            Text("Add")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(20)
                        .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                }
            }
        }
    }
    
    private var streetInfoCard: some View {
        let timeUntil = formatPreciseTimeUntil(schedule.date)
        
        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 40, height: 40)
                
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
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
        .padding(16)
    }
    
    
    
    private var actionButton: some View {
        Button(action: {
            setupNotifications()
        }) {
            HStack {
                if isSettingUpNotifications {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
                
                Text("Looks Good")
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.blue)
            .cornerRadius(16)
        }
        .disabled(isSettingUpNotifications)
    }
    
    
    private var enableNotificationsButton: some View {
        Button(action: {
            requestNotificationPermission()
        }) {
            Text("Enable Notifications")
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
    
    private var activeCustomRemindersCount: Int {
        return notificationManager.customReminders.filter { $0.isActive }.count
    }
    
    
    
    
    
    // MARK: - Helper Methods
    private func checkNotificationPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    notificationsEnabled = true
                    // All reminders remain off by default - user can choose which ones to enable
                } else {
                    // If permission denied, show alert to go to settings
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
            }
        }
    }
    
    private func setupNotifications() {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        isSettingUpNotifications = true
        
        Task {
            await requestPermissionAndScheduleNotifications()
        }
    }
    
    private func requestPermissionAndScheduleNotifications() async {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await scheduleSelectedNotifications()
                
                await MainActor.run {
                    
                    // Dismiss immediately when done
                    AnalyticsManager.shared.logRemindersSheetClosed()
                    dismiss()
                }
            } else {
                await MainActor.run {
                    isSettingUpNotifications = false
                    showingPermissionAlert = true
                }
            }
        } catch {
            await MainActor.run {
                isSettingUpNotifications = false
            }
        }
    }
    
    private func scheduleSelectedNotifications() async {
        // Custom reminders are now managed by NotificationManager
        print("Custom reminders are managed by NotificationManager")
    }
    
    private func formatDateAndTime(_ date: Date, startTime: String, endTime: String) -> String {
        let calendar = Calendar.current
        
        // Helper to format time strings
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
    
    private func createPresetReminder(title: String, amount: Int, unit: TimeUnit, timing: DayTiming?) {
        let specificTime: TimeOfDay? = timing != nil ? TimeOfDay(hour: timing!.hour, minute: 0) : nil
        
        // For "Morning Of", we want same day morning, so use 0 days with morning timing
        let adjustedAmount = (title == "Morning Of") ? 0 : amount
        let adjustedUnit = (title == "Morning Of") ? TimeUnit.days : unit
        
        let customTiming = CustomTiming(
            amount: adjustedAmount,
            unit: adjustedUnit,
            relativeTo: .beforeCleaning,
            specificTime: specificTime
        )
        
        let newReminder = CustomReminder(
            title: title,
            timing: .custom(customTiming),
            isActive: true
        )
        
        let result = notificationManager.addCustomReminder(newReminder)
        
        switch result {
        case .success:
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        case .duplicate:
            pendingReminder = newReminder
            showingDuplicateAlert = true
        case .maxReached:
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
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
}

// MARK: - Unified Empty State
private struct UnifiedEmptyStateView: View {
    let isNotificationsDisabled: Bool
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(iconColor)
                }
                
                VStack(spacing: 12) {
                    Text(titleText)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text(subtitleText)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private var iconName: String {
        isNotificationsDisabled ? "bell.slash.fill" : "bell.fill"
    }
    
    private var iconColor: Color {
        isNotificationsDisabled ? .red : .gray
    }
    
    private var titleText: String {
        isNotificationsDisabled ? "Notifications Disabled" : "No Reminders Yet"
    }
    
    private var subtitleText: String {
        isNotificationsDisabled 
            ? "Enable notifications to receive street cleaning reminders and avoid parking tickets."
            : "Create your first reminder using the Add button above to get notified before street cleaning."
    }
}


private struct RemindersSheetContent: View {
    let schedule: UpcomingSchedule
    let parkingLocation: ParkingLocation?
    @Binding var notificationsEnabled: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCustomReminderEditor = false
    @State private var customReminderToEdit: CustomReminder? = nil
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea(.all)
            
            NavigationView {
                VStack(spacing: 0) {
                    VStack(spacing: 24) {
                        // Header section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Reminders")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button(action: {
                                    customReminderToEdit = nil
                                    showingCustomReminderEditor = true
                                }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 36, height: 36)
                                        .background(Color.blue)
                                        .clipShape(Circle())
                                        .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                            }
                        }
                        
                        // Street info card
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
                                    
                                    Text("Tomorrow • \(schedule.startTime) - \(schedule.endTime)")
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
                        
                        // All reminders section - Default + Custom combined
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Choose Your Reminders")
                                .font(.headline)
                            
                            VStack(spacing: 0) {
                                // Default reminders
                                // ForEach(notificationOptions.indices, id: \.self) { index in
                                HStack(spacing: 16) {
                                    // Icon
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.1))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: "clock")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.blue)
                                    }
                                    
                                    // Text content
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Sample Reminder")
                                            .font(.system(size: 16, weight: .medium))
                                        
                                        Text("Preview reminder")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    // Toggle
                                    Toggle("", isOn: .constant(true)) // Preview toggle
                                        .labelsHidden()
                                }
                                .padding(16)
                                .background(.clear)
                                
                                Divider()
                                    .padding(.leading, 56)
                            }
                            
                            // Sample custom reminders for preview
                            ForEach(["2 hours before", "All Clear"], id: \.self) { customTitle in
                                HStack(spacing: 16) {
                                    // Icon
                                    ZStack {
                                        Circle()
                                            .fill(Color.purple.opacity(0.1))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: "bell.badge")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.purple)
                                    }
                                    
                                    // Text content
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(customTitle)
                                            .font(.system(size: 16, weight: .medium))
                                        
                                        Text("Custom reminder")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    // Edit button
                                    Button(action: {}) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.purple)
                                            .frame(width: 32, height: 32)
                                            .background(Color.purple.opacity(0.1))
                                            .clipShape(Circle())
                                    }
                                    
                                    // Toggle
                                    Toggle("", isOn: .constant(customTitle == "2 hours before")) // First custom enabled
                                        .labelsHidden()
                                }
                                .padding(16)
                                .background(.clear)
                                
                            if customTitle != "All Clear" {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                        .background(.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
                
                Spacer()
                
                // Action button
                Button(action: {}) {
                    Text("Looks Good")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.blue)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .navigationBarHidden(true)
        }
        .background(Color.clear)
        }
        .onAppear {
            notificationManager.loadCustomReminders()
        }
        .sheet(isPresented: $showingCustomReminderEditor) {
            CustomReminderEditorView(
                reminderToEdit: customReminderToEdit,
                schedule: schedule,
                onDismiss: {
                    showingCustomReminderEditor = false
                    customReminderToEdit = nil
                }
            )
        }
    }
}

#Preview("Permission Prompt") {
    let schedule = UpcomingSchedule(
        streetName: "Your Location",
        date: Date().addingTimeInterval(7 * 24 * 3600), // 1 week from now
        endDate: Date().addingTimeInterval(7 * 24 * 3600 + 7200), // 2 hours later
        dayOfWeek: "Next Week",
        startTime: "8:00 AM",
        endTime: "10:00 AM"
    )
    
    return RemindersSheet(
        schedule: schedule,
        parkingLocation: nil
    )
}
