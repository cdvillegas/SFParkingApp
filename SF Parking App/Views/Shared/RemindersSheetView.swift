import SwiftUI

struct RemindersSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var streetDataManager: StreetDataManager
    @ObservedObject var vehicleManager: VehicleManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let currentVehicle = vehicleManager.currentVehicle,
                   let parkingLocation = currentVehicle.parkingLocation {
                    
                    // Header
                    VStack(spacing: 16) {
                        Text("Parking Reminders")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Stay updated on street cleaning schedules")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    
                    // Main content
                    ScrollView {
                        VStack(spacing: 20) {
                            // Vehicle info
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [currentVehicle.color.color, currentVehicle.color.color.opacity(0.8)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 50, height: 50)
                                        
                                        Image(systemName: currentVehicle.type.iconName)
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(currentVehicle.displayName)
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        
                                        Text("Parked at \(parkingLocation.address)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                            }
                            
                            // Upcoming reminders section
                            UpcomingRemindersSection(
                                streetDataManager: streetDataManager,
                                parkingLocation: parkingLocation
                            )
                            
                            // Notification settings info
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Notification Settings")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                        
                                        Text("Get alerts before street cleaning starts")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button("Settings") {
                                        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                            UIApplication.shared.open(settingsUrl)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    
                } else {
                    // No vehicle state
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Image(systemName: "car.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Vehicle Parked")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Add a vehicle and set its parking location to view reminders")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}