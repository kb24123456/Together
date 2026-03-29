import SwiftUI

struct ProfileDurationPickerSheet: View {
    let title: String
    let initialMinutes: Int
    let onSave: (Int) -> Void
    let onDismiss: () -> Void

    @State private var selectedMinutes: Int

    init(
        title: String,
        initialMinutes: Int,
        onSave: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.initialMinutes = NotificationSettings.normalizedSnoozeMinutes(initialMinutes)
        self.onSave = onSave
        self.onDismiss = onDismiss
        _selectedMinutes = State(initialValue: NotificationSettings.normalizedSnoozeMinutes(initialMinutes))
    }

    private let allMinuteOptions = Array(stride(from: 5, through: 180, by: 5))

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("分钟", selection: $selectedMinutes) {
                    ForEach(allMinuteOptions, id: \.self) { minutes in
                        Text(durationLabel(minutes))
                            .tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Button("保存") {
                    onSave(selectedMinutes)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.colors.accent)
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.top, AppTheme.spacing.md)
                .padding(.bottom, AppTheme.spacing.xl)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: onDismiss)
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60) 小时"
        }

        return "\(minutes) 分钟"
    }
}
