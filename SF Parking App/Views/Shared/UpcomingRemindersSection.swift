import SwiftUI
import UserNotifications

struct NotificationOption: Identifiable, Codable {
    var id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let timeOffset: TimeInterval // Placeholder - calculated dynamically
    var isEnabled: Bool = false
    
    // Static notification types that persist across all locations
    static let staticTypes: [NotificationOption] = [
        NotificationOption(
            title: "Week Of",
            subtitle: "A few days before at 9 AM",
            icon: "calendar.badge.exclamationmark",
            timeOffset: 0 // Calculated dynamically
        ),
        NotificationOption(
            title: "Evening Before",
            subtitle: "Day before at 5 PM",
            icon: "moon.fill",
            timeOffset: 0 // Calculated dynamically
        ),
        NotificationOption(
            title: "Morning Of",
            subtitle: "At least 2 hours before",
            icon: "alarm.fill",
            timeOffset: 0 // Calculated dynamically
        ),
        NotificationOption(
            title: "Final Warning",
            subtitle: "30 minutes before",
            icon: "exclamationmark.triangle.fill",
            timeOffset: 1800 // Always 30 minutes
        ),
        NotificationOption(
            title: "All Clear",
            subtitle: "Safe to park back",
            icon: "checkmark.circle.fill",
            timeOffset: 0 // Calculated dynamically
        )
    ]
    
    // Calculate smart timing for each static type based on schedule
    static func calculateTiming(for type: NotificationOption, schedule: UpcomingSchedule) -> TimeInterval {
        let startHour = extractHour(from: schedule.startTime) ?? 8
        let endHour = extractHour(from: schedule.endTime) ?? 10
        let cleaningDate = schedule.date
        
        switch type.title {
        case "Week of":
            // Notify on Sunday at 9 AM of the same week, with at least 2 days notice
            return calculateWeekOfTiming(cleaningDate: cleaningDate)
            
        case "Evening Before":
            // Always notify at 5 PM the evening before
            return calculateTimeOffset(targetHour: 17, cleaningDate: cleaningDate, daysBefore: 1)
            
        case "Day Of":
            if startHour < 10 {
                // For schedules earlier than 10 AM - remind 2 hours before
                return 2 * 3600
            } else {
                // For schedules 10 AM or later - remind at 9 AM same day
                return calculateTimeOffset(targetHour: 9, cleaningDate: cleaningDate, daysBefore: 0)
            }
            
        case "Final Warning":
            return 1800 // Always 30 minutes
            
        case "All Clear":
            let cleaningDuration = endHour - startHour
            return TimeInterval(-(cleaningDuration * 3600)) // After cleaning ends
            
        default:
            return 3600 // 1 hour default
        }
    }
    
    // Helper to extract hour from time string like "8:00 AM"
    static func extractHour(from timeString: String) -> Int? {
        let components = timeString.components(separatedBy: ":")
        guard let hourString = components.first,
              let hour = Int(hourString) else { return nil }
        
        if timeString.contains("PM") && hour != 12 {
            return hour + 12
        } else if timeString.contains("AM") && hour == 12 {
            return 0
        }
        return hour
    }
    
    // Helper to calculate time offset for specific target hour
    private static func calculateTimeOffset(targetHour: Int, cleaningDate: Date, daysBefore: Int) -> TimeInterval {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current
        
        guard let targetDate = calendar.date(byAdding: .day, value: -daysBefore, to: cleaningDate),
              let targetDateTime = calendar.date(bySettingHour: targetHour, minute: 0, second: 0, of: targetDate) else {
            return TimeInterval(daysBefore * 24 * 3600 - targetHour * 3600)
        }
        return cleaningDate.timeIntervalSince(targetDateTime)
    }
    
    private static func calculateWeekOfTiming(cleaningDate: Date) -> TimeInterval {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current
        
        // Get the weekday of the cleaning date (1 = Sunday, 2 = Monday, etc.)
        let cleaningWeekday = calendar.component(.weekday, from: cleaningDate)
        
        // Calculate days until previous Sunday
        let daysFromSunday = cleaningWeekday - 1 // Days since Sunday
        
        // If cleaning is on Sunday, we need the Sunday before
        let targetSundayOffset = daysFromSunday == 0 ? 7 : daysFromSunday
        
        // Get the Sunday of the cleaning week
        guard let sundayDate = calendar.date(byAdding: .day, value: -targetSundayOffset, to: cleaningDate),
              let sundayAt9AM = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: sundayDate) else {
            return TimeInterval(3 * 24 * 3600) // Fallback to 3 days
        }
        
        // Check if Sunday is at least 2 days before cleaning
        let daysBetween = calendar.dateComponents([.day], from: sundayAt9AM, to: cleaningDate).day ?? 0
        
        if daysBetween < 2 {
            // If less than 2 days, use 2 days before at 9 AM instead
            return calculateTimeOffset(targetHour: 9, cleaningDate: cleaningDate, daysBefore: 2)
        }
        
        return cleaningDate.timeIntervalSince(sundayAt9AM)
    }
}

struct UpcomingRemindersSection: View {
    @ObservedObject var streetDataManager: StreetDataManager
    let parkingLocation: ParkingLocation?
    
    @State private var showingReminderSheet = false
    
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
        .sheet(isPresented: $showingReminderSheet) {
            // Always use the same NotificationSettingsSheet, create dummy schedule if needed
            let schedule = streetDataManager.nextUpcomingSchedule ?? UpcomingSchedule(
                streetName: parkingLocation?.address ?? "Your Location",
                date: Date().addingTimeInterval(7 * 24 * 3600), // 1 week from now
                endDate: Date().addingTimeInterval(7 * 24 * 3600 + 7200), // 2 hours later
                dayOfWeek: "Next Week",
                startTime: "8:00 AM",
                endTime: "10:00 AM"
            )
            NotificationSettingsSheet(schedule: schedule, parkingLocation: parkingLocation)
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
                HStack {
                    Text("Street cleaning \(timeUntil)")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                HStack {
                    Text(formatDateAndTime(schedule.date, startTime: schedule.startTime, endTime: schedule.endTime))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
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
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            showingReminderSheet = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("You're all clear!")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("No upcoming street sweeping")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
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

// MARK: - Notification Settings Sheet
struct NotificationSettingsSheet: View {
    let schedule: UpcomingSchedule
    let parkingLocation: ParkingLocation?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var notificationOptions: [NotificationOption] = []
    @State private var showingPermissionAlert = false
    @State private var isSettingUpNotifications = false
    @State private var setupComplete = false
    @State private var notificationsEnabled = false
    @State private var showingPermissionPrompt = false
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea(.all)
            
            NavigationView {
                VStack(spacing: 0) {
                    VStack(spacing: 24) {
                        // Header section
                        headerSection
                        
                        // Street info card - only show if there's a real upcoming schedule
                        if schedule.dayOfWeek != "Next Week" {
                            streetInfoCard
                        }
                        
                        // Notification options or permission prompt
                        if !notificationsEnabled {
                            notificationPermissionPrompt
                        } else {
                            notificationOptionsSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    
                    Spacer()
                    
                    // Bottom button
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .navigationBarHidden(true)
            }
            .background(Color.clear)
        }
        .onAppear {
            checkNotificationPermissions()
            setupNotificationOptions()
            
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
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reminders")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
        }
    }
    
    private var streetInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                
                Text(schedule.streetName)
                    .font(.headline)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    
                    Text(formatDateAndTime(schedule.date, startTime: schedule.startTime, endTime: schedule.endTime))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    
                    Text("\(schedule.startTime) - \(schedule.endTime)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var notificationOptionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Your Reminders")
                .font(.headline)
            
            VStack(spacing: 0) {
                ForEach(notificationOptions.indices, id: \.self) { index in
                    notificationRow(for: notificationOptions[index], index: index)
                    
                    if index < notificationOptions.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    private func notificationRow(for option: NotificationOption, index: Int) -> some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: option.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.system(size: 16, weight: .medium))
                
                Text(option.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Toggle
            Toggle("", isOn: Binding(
                get: { notificationOptions[index].isEnabled },
                set: { newValue in
                    notificationOptions[index].isEnabled = newValue
                    // Save preferences immediately when changed
                    saveNotificationPreferences()
                }
            ))
            .labelsHidden()
        }
        .padding(16)
        .background(.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            notificationOptions[index].isEnabled.toggle()
            // Save preferences when row is tapped
            saveNotificationPreferences()
        }
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
    
    private var notificationPermissionPrompt: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.red)
                }
                
                VStack(spacing: 8) {
                    Text("Notifications Are Disabled")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text("Enable street cleaning reminders to avoid expensive parking tickets.")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }.padding(.horizontal, 16)
            
            Spacer()
        }
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
    
    
    private func setupNotificationOptions() {
        // Use static notification types that persist across locations
        notificationOptions = NotificationOption.staticTypes
        
        // Load saved preferences first
        loadNotificationPreferences()
        
        // All reminders should be off by default - no auto-enabling
        
    }
    
    private func loadNotificationPreferences() {
        let globalKey = "StaticNotificationPreferences"
        
        // Load global static preferences (no street-specific preferences for static types)
        if let data = UserDefaults.standard.data(forKey: globalKey),
           let savedPreferences = try? JSONDecoder().decode([String: Bool].self, from: data) {
            
            // Apply saved preferences to notification options
            for index in notificationOptions.indices {
                if let savedValue = savedPreferences[notificationOptions[index].title] {
                    notificationOptions[index].isEnabled = savedValue
                }
            }
        }
    }
    
    private func saveNotificationPreferences() {
        let globalKey = "StaticNotificationPreferences"
        var preferences: [String: Bool] = [:]
        
        for option in notificationOptions {
            preferences[option.title] = option.isEnabled
        }
        
        if let data = try? JSONEncoder().encode(preferences) {
            // Save static preferences globally
            UserDefaults.standard.set(data, forKey: globalKey)
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
                    // Save preferences
                    saveNotificationPreferences()
                    
                    // Dismiss immediately when done
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
        let center = UNUserNotificationCenter.current()
        let enabledOptions = notificationOptions.filter { $0.isEnabled }
        
        print("🔔 Scheduling \(enabledOptions.count) notifications...")
        
        // Clear existing notifications
        center.removeAllPendingNotificationRequests()
        
        var scheduledCount = 0
        
        for option in enabledOptions {
            // Calculate dynamic timing based on the current schedule
            let calculatedOffset = NotificationOption.calculateTiming(for: option, schedule: schedule)
            let notificationDate = schedule.date.addingTimeInterval(-calculatedOffset)
            
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current
            print("📅 \(option.title): Scheduled for \(formatter.string(from: notificationDate)) PST (offset: \(calculatedOffset / 3600) hours)")
            
            guard notificationDate > Date() else {
                print("⚠️ Skipping \(option.title) - date is in the past")
                continue
            }
            
            let content = UNMutableNotificationContent()
            content.title = getNotificationTitle(for: option)
            content.body = getNotificationBody(for: option)
            content.sound = calculatedOffset <= 1800 ? .defaultCritical : .default
            content.badge = 1
            content.categoryIdentifier = "STREET_CLEANING"
            var userInfo: [String: Any] = [
                "option": option.title,
                "streetName": schedule.streetName
            ]
            if let locationId = parkingLocation?.id {
                userInfo["parkingLocationId"] = locationId.uuidString
            }
            content.userInfo = userInfo
            
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current
            var dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
            dateComponents.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            
            let request = UNNotificationRequest(
                identifier: "parking-\(option.id.uuidString)",
                content: content,
                trigger: trigger
            )
            
            do {
                try await center.add(request)
                scheduledCount += 1
                print("✅ Successfully scheduled: \(option.title)")
            } catch {
                print("❌ Failed to schedule \(option.title): \(error)")
            }
        }
        
        // Verify notifications were scheduled
        let pendingRequests = await center.pendingNotificationRequests()
        print("🎯 Total notifications scheduled: \(scheduledCount)")
        print("🔍 Verified pending notifications: \(pendingRequests.count)")
        
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current
        
        for request in pendingRequests {
            if let trigger = request.trigger as? UNCalendarNotificationTrigger,
               let nextDate = trigger.nextTriggerDate() {
                let timeUntil = nextDate.timeIntervalSince(Date())
                let hoursUntil = timeUntil / 3600
                let daysUntil = hoursUntil / 24
                print("📋 \(request.content.title) - fires at \(formatter.string(from: nextDate)) (in \(String(format: "%.1f", daysUntil)) days)")
            }
        }
    }
    
    private func getNotificationTitle(for option: NotificationOption) -> String {
        switch option.title {
        case "Week Of":
            return "🗓️ Street Sweeping This Week"
        case "Evening Before":
            return "🗓️ Street Sweeping Tomorrow"
        case "Morning Of":
            return "⏰ Street Sweeping TODAY"
        case "Final Warning":
            return "🚨 Move Your Vehicle NOW"
        case "All Clear":
            return "✅ Street Sweeping Has Ended"
        default:
            return "🅿️ Parking Reminder"
        }
    }
    
    private func getNotificationBody(for option: NotificationOption) -> String {
        switch option.title {
        case "Week Of":
            return "This \(schedule.dayOfWeek) at \(schedule.startTime) on \(schedule.streetName)"
        case "Evening Before":
            return "Starts at \(schedule.startTime) on \(schedule.streetName)"
        case "Morning Of":
            return "Starts at \(schedule.startTime) on \(schedule.streetName)"
        case "Final Warning":
            return "Starts in 30 minutes on \(schedule.streetName)"
        case "All Clear":
            return "Ended just now on \(schedule.streetName)"
        default:
            return "Parking reminder for \(schedule.streetName)"
        }
    }
    
    private func formatDateAndTime(_ date: Date, startTime: String, endTime: String) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter.string(from: date)
        }
    }
}
