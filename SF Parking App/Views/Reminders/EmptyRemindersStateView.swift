//
//  EmptyRemindersStateView.swift
//  SF Parking App
//
//  Created by Claude on 7/16/25.
//

import SwiftUI

struct EmptyRemindersStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 12) {
                Text("No Reminders Yet")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Create your first reminder using the Add button above to get notified before street cleaning.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 32)
    }
}
