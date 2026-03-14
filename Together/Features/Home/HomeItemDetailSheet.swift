import SwiftUI

struct HomeItemDetailSheet: View {
    @Bindable var viewModel: HomeViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case notes
    }

    var body: some View {
        NavigationStack {
            if let draft = viewModel.detailDraft {
                Form {
                    Section("基础信息") {
                        TextField(
                            "标题",
                            text: Binding(
                                get: { viewModel.detailDraft?.title ?? "" },
                                set: { viewModel.updateDraftTitle($0) }
                            ),
                            axis: .vertical
                        )
                        .focused($focusedField, equals: .title)

                        TextField(
                            "备注",
                            text: Binding(
                                get: { viewModel.detailDraft?.notes ?? "" },
                                set: { viewModel.updateDraftNotes($0) }
                            ),
                            axis: .vertical
                        )
                        .lineLimit(4, reservesSpace: true)
                        .focused($focusedField, equals: .notes)
                    }

                    Section("时间") {
                        Toggle(
                            "设置截止时间",
                            isOn: Binding(
                                get: { viewModel.detailDraft?.dueAt != nil },
                                set: { viewModel.setDraftDueDateEnabled($0) }
                            )
                        )

                        if let dueAt = viewModel.detailDraft?.dueAt {
                            DatePicker(
                                "截止日期",
                                selection: Binding(
                                    get: { dueAt },
                                    set: { viewModel.updateDraftDueDate($0) }
                                ),
                                displayedComponents: .date
                            )

                            DatePicker(
                                "截止时间",
                                selection: Binding(
                                    get: { dueAt },
                                    set: { viewModel.updateDraftDueTime($0) }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                        }

                        Toggle(
                            "设置提醒",
                            isOn: Binding(
                                get: { viewModel.detailDraft?.remindAt != nil },
                                set: { viewModel.setDraftReminderEnabled($0) }
                            )
                        )

                        if let remindAt = viewModel.detailDraft?.remindAt {
                            DatePicker(
                                "提醒时间",
                                selection: Binding(
                                    get: { remindAt },
                                    set: { viewModel.updateDraftReminder($0) }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    }

                    Section("属性") {
                        Picker(
                            "优先级",
                            selection: Binding(
                                get: { viewModel.detailDraft?.priority ?? .normal },
                                set: { viewModel.updateDraftPriority($0) }
                            )
                        ) {
                            ForEach(ItemPriority.allCases, id: \.self) { priority in
                                Text(priority.title).tag(priority)
                            }
                        }

                        Toggle(
                            "置顶到今日顶部",
                            isOn: Binding(
                                get: { viewModel.detailDraft?.isPinned ?? false },
                                set: { viewModel.updateDraftPinned($0) }
                            )
                        )

                        Picker(
                            "重复",
                            selection: Binding<ItemRepeatFrequency?>(
                                get: { viewModel.detailDraft?.repeatRule?.frequency },
                                set: { viewModel.updateDraftRepeatRule($0) }
                            )
                        ) {
                            Text("不重复").tag(Optional<ItemRepeatFrequency>.none)
                            ForEach(ItemRepeatFrequency.allCases, id: \.self) { frequency in
                                Text(frequency.title).tag(Optional(frequency))
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("事件详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            viewModel.dismissItemDetail()
                        }
                    }
                }
            } else {
                ProgressView()
                    .navigationTitle("事件详情")
            }
        }
        .presentationDetents([.medium, .large], selection: $viewModel.detailDetent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .onChange(of: focusedField) { _, newValue in
            if newValue != nil {
                viewModel.markDetailForExpandedEditing()
            }
        }
    }
}
