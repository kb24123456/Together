import SwiftUI

struct ImportantDateEditSheet: View {
    @Environment(AppContext.self) private var appContext
    @Environment(\.dismiss) private var dismiss

    @State var event: ImportantDate

    private let notifyOptions = ImportantDate.validNotifyDaysBefore

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("纪念日名称", text: $event.title)
                }
                Section("日期") {
                    DatePicker("日期", selection: $event.dateValue, displayedComponents: .date)
                    Picker("重复", selection: $event.recurrence) {
                        Text("一次性").tag(Recurrence.none)
                        Text("每年（公历）").tag(Recurrence.solarAnnual)
                        Text("每年（农历）").tag(Recurrence.lunarAnnual)
                    }
                    .pickerStyle(.segmented)
                }
                Section("提醒") {
                    Picker("提前几天", selection: $event.notifyDaysBefore) {
                        ForEach(notifyOptions, id: \.self) { day in
                            Text("\(day) 天").tag(day)
                        }
                    }
                    Toggle("当天提醒", isOn: $event.notifyOnDay)
                }
                if case .birthday = event.kind {
                    Section {
                        Text("生日不能修改所属用户")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("编辑纪念日")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(event.title.isEmpty)
                }
            }
        }
    }

    private func save() {
        var updated = event
        updated.updatedAt = .now
        Task {
            await appContext.importantDatesViewModel.save(updated)
            dismiss()
        }
    }
}
