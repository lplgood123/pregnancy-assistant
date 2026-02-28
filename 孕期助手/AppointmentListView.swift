import SwiftUI

struct AppointmentListView: View {
    @EnvironmentObject private var store: PregnancyStore

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                List {
                    if activeAppointments.isEmpty {
                        Text("暂无产检预约")
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        ForEach(activeAppointments) { appointment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(appointment.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(store.formatDate(appointment.dueDate)) · \(store.countdownText(to: appointment.dueDate))")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                                Text(appointment.detail)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) {
                    Color.clear
                        .frame(height: AppLayout.scrollTailPadding)
                }
            }
            .navigationTitle("产检预约")
            .font(AppTheme.bodyFont)
        }
    }

    private var activeAppointments: [AppointmentItem] {
        store.activeAppointments.sorted { $0.dueDate < $1.dueDate }
    }
}

#Preview {
    AppointmentListView()
        .environmentObject(PregnancyStore())
}
