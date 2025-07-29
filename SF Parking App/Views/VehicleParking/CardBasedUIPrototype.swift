import SwiftUI
import MapKit

struct CardBasedUIPrototype: View {
    @State private var remindersEnabled = true
    @State private var smartParkEnabled = true
    @State private var showingRemindersSheet = false
    @State private var showingSmartParkSettings = false
    @State private var activeRemindersCount = 2 // Example: 2 active reminders
    @State private var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )
    
    var body: some View {
        ZStack {
            // Map background
            Map(position: $mapPosition)
                .ignoresSafeArea()
            
            // Content at bottom
            VStack {
                Spacer()
                
                bottomInterface
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
        .sheet(isPresented: $showingRemindersSheet) {
            Text("Reminders Settings")
                .font(.largeTitle)
                .padding()
        }
        .sheet(isPresented: $showingSmartParkSettings) {
            Text("Smart Park Settings")
                .font(.largeTitle)
                .padding()
        }
    }
    
    private var bottomInterface: some View {
        VStack(spacing: 12) {
            // Main vehicle info card
            HStack(spacing: 12) {
                // Vehicle icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "car.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.blue.opacity(0.3), radius: 3, x: 0, y: 1)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("1234 Market Street")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text("Move by Tomorrow, 8:00 AM")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Menu button
                Menu {
                    Button("View in Maps", systemImage: "map") {}
                    Button("Share Location", systemImage: "square.and.arrow.up") {}
                    Divider()
                    Button("Reminders", systemImage: "bell.fill") {
                        showingRemindersSheet = true
                    }
                    Button("Smart Park", systemImage: "sparkles") {
                        showingSmartParkSettings = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
            )
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
            
            // Feature cards section
            HStack(spacing: 12) {
                // Reminders Card
                Button(action: {
                    remindersEnabled.toggle()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(remindersEnabled ? .white : .secondary)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(remindersEnabled ? Color.blue : Color(.systemGray5))
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reminders")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text(remindersEnabled ? "\(activeRemindersCount) active" : "Tap to enable")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.6
                                    )
                            )
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            if remindersEnabled {
                                showingRemindersSheet = true
                            }
                        }
                )
                
                // Smart Park Card
                Button(action: {
                    smartParkEnabled.toggle()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(smartParkEnabled ? .white : .secondary)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(smartParkEnabled ? Color.green : Color(.systemGray5))
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart Park")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text(smartParkEnabled ? "Active" : "Tap to enable")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.6
                                    )
                            )
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            if smartParkEnabled {
                                showingSmartParkSettings = true
                            }
                        }
                )
            }
            
            // Button section
            Button(action: {}) {
                Text("Move Vehicle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.2), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

#Preview {
    CardBasedUIPrototype()
}