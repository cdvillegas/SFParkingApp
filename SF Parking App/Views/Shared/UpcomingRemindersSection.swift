import SwiftUI
import UserNotifications

struct NotificationOption: Identifiable, Codable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let timeOffset: TimeInterval // Placeholder - calculated dynamically
    var isEnabled: Bool = false
    
    // Static notification types that persist across all locations
    static let staticTypes: [NotificationOption] = [
        NotificationOption(
            title: "3 Days Before",
            subtitle: "A few days before at 9 AM",
            icon: "calendar.badge.exclamationmark",
            timeOffset: 0 // Calculated dynamically
        ),
        NotificationOption(
            title: "Day Before", 
            subtitle: "Preceding day at 9 AM",
            icon: "clock.fill",
            timeOffset: 0 // Calculated dynamically
        ),
        NotificationOption(
            title: "Day Of",
            subtitle: "9 AM or 2 hours before",
            icon: "alarm.fill",
            timeOffset: 0 // Calculated dynamically
        ),
        NotificationOption(
            title: "Final Warning",
            subtitle: "30 minutes before",
            icon: "exclamationmark.octagon.fill",
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
        case "3 Days Before":
            // Notify at 9 AM, 3 days before cleaning
            return calculateTimeOffset(targetHour: 9, cleaningDate: cleaningDate, daysBefore: 3)
            
        case "Day Before":
            // Always notify at 9 AM the day before
            return calculateTimeOffset(targetHour: 9, cleaningDate: cleaningDate, daysBefore: 1)
            
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
    
    // Smart notification options that adapt to the actual schedule
    static func smartOptions(for schedule: UpcomingSchedule) -> [NotificationOption] {
        let startHour = extractHour(from: schedule.startTime) ?? 8
        let endHour = extractHour(from: schedule.endTime) ?? 10
        let cleaningDate = schedule.date
        let calendar = Calendar.current
        
        var options: [NotificationOption] = []
        
        // 1. Week Before - Always useful for planning
        options.append(NotificationOption(
            title: "3 Days Before",
            subtitle: "Planning ahead",
            icon: "calendar.badge.exclamationmark",
            timeOffset: 3 * 24 * 3600
        ))
        
        // 2. Night Before - Smart timing based on cleaning time
        let nightBeforeHour = startHour < 10 ? 20 : 22 // 8 PM for early cleaning, 10 PM for late
        let nightBeforeOffset = calculateTimeOffset(targetHour: nightBeforeHour, cleaningDate: cleaningDate, daysBefore: 1)
        options.append(NotificationOption(
            title: "Night Before",
            subtitle: startHour < 10 ? "Move by morning" : "Move tonight",
            icon: "moon.stars.fill",
            timeOffset: nightBeforeOffset
        ))
        
        // 3. Smart Morning/Early Reminder
        if startHour <= 8 {
            // Very early cleaning (6-8 AM) - remind the night before at bedtime
            options.append(NotificationOption(
                title: "Before Bed",
                subtitle: "Move tonight",
                icon: "bed.double.fill",
                timeOffset: calculateTimeOffset(targetHour: 23, cleaningDate: cleaningDate, daysBefore: 1)
            ))
        } else if startHour <= 12 {
            // Morning cleaning (8 AM - 12 PM) - morning reminder
            let morningHour = max(7, startHour - 2)
            options.append(NotificationOption(
                title: "Morning",
                subtitle: "2 hours until cleaning",
                icon: "sunrise.fill",
                timeOffset: 2 * 3600
            ))
        } else {
            // Afternoon cleaning - lunch time reminder
            options.append(NotificationOption(
                title: "Midday",
                subtitle: "Move after lunch",
                icon: "sun.max.fill",
                timeOffset: 3 * 3600
            ))
        }
        
        // 4. Final Warning - Always 30 minutes before
        options.append(NotificationOption(
            title: "Final Warning",
            subtitle: "Move now",
            icon: "exclamationmark.triangle.fill",
            timeOffset: 1800
        ))
        
        
        // 6. All Clear - Smart timing based on cleaning end time
        let cleaningDuration = endHour - startHour
        let allClearOffset = TimeInterval(-(cleaningDuration * 3600)) // Negative offset = after start
        options.append(NotificationOption(
            title: "All Clear",
            subtitle: "Safe to park back",
            icon: "checkmark.circle",
            timeOffset: allClearOffset
        ))
        
        return options
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
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(
                        color: Color.orange.opacity(0.2),
                        radius: 6,
                        x: 0,
                        y: 3
                    )
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
    }
    
    // MARK: - No Restrictions State
    private var noRestrictionsState: some View {
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

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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
                        if notificationsEnabled {
                            notificationOptionsSection
                        } else {
                            notificationPermissionPrompt
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    
                    Spacer()
                    
                    // Bottom button
                    if notificationsEnabled {
                        actionButton
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                    } else {
                        Button(action: {
                            dismiss()
                        }) {
                            Text("Done")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.gray)
                                .cornerRadius(16)
                        }
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
                } else {
                    Image(systemName: "bell.badge.plus")
                        .font(.system(size: 18, weight: .bold))
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
        .disabled(isSettingUpNotifications || !notificationOptions.contains { $0.isEnabled })
    }
    
    private var notificationPermissionPrompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enable Notifications")
                .font(.headline)
            
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "bell.slash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications Disabled")
                            .font(.system(size: 16, weight: .medium))
                        
                        Text("Reminders won't work without notification permissions")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
                
                Button(action: {
                    requestNotificationPermission()
                }) {
                    HStack {
                        Image(systemName: "bell")
                        Text("Enable Notifications")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }
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
        
        // If no saved preferences, set smart defaults
        if !notificationOptions.contains(where: { $0.isEnabled }) {
            // Enable Day Before and Final Warning by default
            if let dayBeforeIndex = notificationOptions.firstIndex(where: { $0.title == "Day Before" }) {
                notificationOptions[dayBeforeIndex].isEnabled = true
            }
            if let finalWarningIndex = notificationOptions.firstIndex(where: { $0.title == "Final Warning" }) {
                notificationOptions[finalWarningIndex].isEnabled = true
            }
        }
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
        case "3 Days Before":
            return "📅 Street Sweeping In 3 Days"
        case "Day Before":
            return "🕐 Street Sweeping Tomorrow"
        case "Day Of":
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
        case "3 Days Before":
            return "Starts \(schedule.dayOfWeek) at \(schedule.startTime) on \(schedule.streetName)"
        case "Day Before":
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

// MARK: - Preview Helper
func createMockStreetDataManager(urgencyLevel: UpcomingRemindersSection.UrgencyLevel) -> StreetDataManager {
    let manager = StreetDataManager()
    let timeInterval = timeIntervalForUrgencyLevel(urgencyLevel)
    
    manager.nextUpcomingSchedule = UpcomingSchedule(
        streetName: "Mission St",
        date: Date().addingTimeInterval(timeInterval),
        endDate: Date().addingTimeInterval(timeInterval + 7200),
        dayOfWeek: dayOfWeekForUrgency(urgencyLevel),
        startTime: "8:00 AM",
        endTime: "10:00 AM"
    )
    
    return manager
}

private func timeIntervalForUrgencyLevel(_ level: UpcomingRemindersSection.UrgencyLevel) -> TimeInterval {
    switch level {
    case .info: return 3 * 24 * 3600 // 3 days
    case .warning: return 12 * 3600 // 12 hours
    case .critical: return 1800 // 30 minutes
    }
}

private func dayOfWeekForUrgency(_ level: UpcomingRemindersSection.UrgencyLevel) -> String {
    switch level {
    case .info: return "Tuesday"
    case .warning: return "Tomorrow"
    case .critical: return "Today"
    }
}

#Preview("Info Level") {
    UpcomingRemindersSection(
        streetDataManager: createMockStreetDataManager(urgencyLevel: .info),
        parkingLocation: nil
    )
    .preferredColorScheme(.light)
    .padding()
}

#Preview("Warning Level") {
    UpcomingRemindersSection(
        streetDataManager: createMockStreetDataManager(urgencyLevel: .warning),
        parkingLocation: nil
    )
    .preferredColorScheme(.light)
    .padding()
}

#Preview("Critical Level") {
    UpcomingRemindersSection(
        streetDataManager: createMockStreetDataManager(urgencyLevel: .critical),
        parkingLocation: nil
    )
    .preferredColorScheme(.light)
    .padding()
}

#Preview("Critical Dark") {
    UpcomingRemindersSection(
        streetDataManager: createMockStreetDataManager(urgencyLevel: .critical),
        parkingLocation: nil
    )
    .preferredColorScheme(.dark)
    .padding()
}

#Preview("Light Mode") {
    VehicleParkingView()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VehicleParkingView()
        .preferredColorScheme(.dark)
}
