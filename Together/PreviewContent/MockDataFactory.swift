import Foundation

enum MockDataFactory {
    static let currentUserID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let partnerUserID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let pairSpaceID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let dataBoundaryToken = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let singleSpaceID = UUID(uuidString: "99999999-9999-9999-9999-999999999991")!
    static let inboxListID = UUID(uuidString: "99999999-9999-9999-9999-999999999992")!
    static let todayListID = UUID(uuidString: "99999999-9999-9999-9999-999999999993")!
    static let planningListID = UUID(uuidString: "99999999-9999-9999-9999-999999999996")!
    static let focusProjectID = UUID(uuidString: "99999999-9999-9999-9999-999999999994")!
    static let launchProjectID = UUID(uuidString: "99999999-9999-9999-9999-999999999995")!
    static let migrationProjectID = UUID(uuidString: "99999999-9999-9999-9999-999999999997")!
    static let pairSharedSpaceID = UUID(uuidString: "99999999-9999-9999-9999-999999999998")!

    static let now = Date.now

    static func makeCurrentUser() -> User {
        User(
            id: currentUserID,
            appleUserID: "apple-user-demo",
            displayName: "云丰",
            avatarSystemName: "person.crop.circle.fill",
            createdAt: now.addingTimeInterval(-86_400 * 120),
            updatedAt: now,
            preferences: NotificationSettings(
                taskReminderEnabled: true,
                dailySummaryEnabled: true,
                calendarReminderEnabled: true,
                futureCollaborationInviteEnabled: true,
                taskUrgencyWindowMinutes: 30,
                defaultSnoozeMinutes: 30,
                quickTimePresetMinutes: [5, 30, 60],
                completedTaskAutoArchiveEnabled: true,
                completedTaskAutoArchiveDays: 30
            )
        )
    }

    static func makePartnerUser() -> User {
        User(
            id: partnerUserID,
            appleUserID: nil,
            displayName: "沐晴",
            avatarSystemName: "heart.circle.fill",
            createdAt: now.addingTimeInterval(-86_400 * 118),
            updatedAt: now,
            preferences: NotificationSettings(
                taskReminderEnabled: true,
                dailySummaryEnabled: true,
                calendarReminderEnabled: true,
                futureCollaborationInviteEnabled: false,
                taskUrgencyWindowMinutes: 30,
                defaultSnoozeMinutes: 30,
                quickTimePresetMinutes: [5, 30, 60],
                completedTaskAutoArchiveEnabled: true,
                completedTaskAutoArchiveDays: 30
            )
        )
    }

    static func makeSingleSpace() -> Space {
        Space(
            id: singleSpaceID,
            type: .single,
            displayName: "我的工作空间",
            ownerUserID: currentUserID,
            status: .active,
            createdAt: now.addingTimeInterval(-86_400 * 90),
            updatedAt: now,
            archivedAt: nil
        )
    }

    static func makePairSpace() -> PairSpace {
        PairSpace(
            id: pairSpaceID,
            sharedSpaceID: pairSharedSpaceID,
            status: .active,
            memberA: PairMember(
                userID: currentUserID,
                nickname: "我",
                joinedAt: now.addingTimeInterval(-86_400 * 120)
            ),
            memberB: PairMember(
                userID: partnerUserID,
                nickname: "TA",
                joinedAt: now.addingTimeInterval(-86_400 * 115)
            ),
            dataBoundaryToken: dataBoundaryToken,
            createdAt: now.addingTimeInterval(-86_400 * 120),
            activatedAt: now.addingTimeInterval(-86_400 * 115),
            endedAt: nil
        )
    }

    static func makePairSharedSpace() -> Space {
        Space(
            id: pairSharedSpaceID,
            type: .pair,
            displayName: "一起的任务空间",
            ownerUserID: currentUserID,
            status: .active,
            createdAt: now.addingTimeInterval(-86_400 * 115),
            updatedAt: now,
            archivedAt: nil
        )
    }

    static func makePairSpaceSummary() -> PairSpaceSummary {
        PairSpaceSummary(
            sharedSpace: makePairSharedSpace(),
            pairSpace: makePairSpace(),
            partner: makePartnerUser()
        )
    }

    static func makeInvite() -> Invite {
        Invite(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            pairSpaceID: pairSpaceID,
            inviterID: currentUserID,
            inviteCode: "WITH-YOU",
            status: .pending,
            sentAt: now.addingTimeInterval(-3_600),
            respondedAt: nil,
            expiresAt: now.addingTimeInterval(86_400 * 2)
        )
    }

    static func makeItems() -> [Item] {
        let dayStart = Calendar.current.startOfDay(for: now)
        return [
            Item(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666661")!,
                spaceID: singleSpaceID,
                listID: todayListID,
                projectID: focusProjectID,
                creatorID: currentUserID,
                title: "晨会前整理今日阻塞项",
                notes: "把昨晚遗留的 3 个阻塞点收拢成一句话，会议前同步给团队。",
                locationText: "产品组晨会",
                executionRole: .initiator,
                dueAt: dayStart.addingTimeInterval(3_600 * 7),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 6 + 2_400),
                status: .inProgress,
                latestResponse: nil,
                responseHistory: [],
                createdAt: dayStart.addingTimeInterval(-3_600 * 4),
                updatedAt: dayStart.addingTimeInterval(-3_600 * 4),
                completedAt: nil,
                isPinned: true,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666662")!,
                spaceID: singleSpaceID,
                listID: planningListID,
                projectID: focusProjectID,
                creatorID: currentUserID,
                title: "补齐首页交互说明",
                notes: "把动效原则、筛选逻辑、空态文案补到当前设计说明里。",
                locationText: "文档任务",
                executionRole: .initiator,
                dueAt: dayStart.addingTimeInterval(3_600 * 8 + 1_200),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 8),
                status: .inProgress,
                latestResponse: ItemResponse(
                    responderID: currentUserID,
                    kind: .acknowledged,
                    message: "上午内完成",
                    respondedAt: dayStart.addingTimeInterval(3_600 * 7 + 900)
                ),
                responseHistory: [
                    ItemResponse(
                        responderID: currentUserID,
                        kind: .acknowledged,
                        message: "上午内完成",
                        respondedAt: dayStart.addingTimeInterval(3_600 * 7 + 900)
                    )
                ],
                createdAt: dayStart.addingTimeInterval(-86_400),
                updatedAt: dayStart.addingTimeInterval(3_600 * 7 + 900),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666663")!,
                spaceID: singleSpaceID,
                listID: planningListID,
                projectID: migrationProjectID,
                creatorID: currentUserID,
                title: "确认新导航命名",
                notes: "把 Today / 清单 / 项目 / 日历 / 我 的命名同步到代码骨架。",
                locationText: "架构收敛",
                executionRole: .initiator,
                dueAt: dayStart.addingTimeInterval(3_600 * 10 + 1_800),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 10),
                status: .inProgress,
                latestResponse: ItemResponse(
                    responderID: currentUserID,
                    kind: .acknowledged,
                    message: "收到",
                    respondedAt: dayStart.addingTimeInterval(3_600 * 9 + 600)
                ),
                responseHistory: [
                    ItemResponse(
                        responderID: currentUserID,
                        kind: .acknowledged,
                        message: "收到",
                        respondedAt: dayStart.addingTimeInterval(3_600 * 9 + 600)
                    )
                ],
                createdAt: dayStart.addingTimeInterval(-43_200),
                updatedAt: dayStart.addingTimeInterval(3_600 * 9 + 600),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666664")!,
                spaceID: singleSpaceID,
                listID: todayListID,
                projectID: launchProjectID,
                creatorID: currentUserID,
                title: "梳理本周项目优先级",
                notes: "午休前确认本周只保留 2 个高价值项目目标。",
                locationText: "项目视角",
                executionRole: .initiator,
                dueAt: dayStart.addingTimeInterval(3_600 * 14),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 13 + 1_800),
                status: .pendingConfirmation,
                latestResponse: nil,
                responseHistory: [],
                createdAt: dayStart.addingTimeInterval(-21_600),
                updatedAt: dayStart.addingTimeInterval(-18_000),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666665")!,
                spaceID: singleSpaceID,
                listID: todayListID,
                projectID: launchProjectID,
                creatorID: currentUserID,
                title: "晚间复盘今天进展",
                notes: "记录今天推进最顺和最卡的一件事，明早进入 Today 顶部概览。",
                locationText: "个人复盘",
                executionRole: .initiator,
                dueAt: dayStart.addingTimeInterval(3_600 * 21 + 7_200),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 21 + 3_600),
                status: .pendingConfirmation,
                latestResponse: nil,
                responseHistory: [],
                createdAt: dayStart.addingTimeInterval(-3_600),
                updatedAt: dayStart.addingTimeInterval(-3_600),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                spaceID: singleSpaceID,
                listID: inboxListID,
                projectID: focusProjectID,
                creatorID: currentUserID,
                title: "明早跟进客户邮件",
                notes: "需要补 2 个关键截图，避免早会后继续卡住。",
                locationText: "客户跟进",
                executionRole: .initiator,
                dueAt: dayStart.addingTimeInterval(86_400 + 3_600 * 6),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(86_400 + 3_600 * 4),
                status: .pendingConfirmation,
                latestResponse: nil,
                responseHistory: [],
                createdAt: dayStart.addingTimeInterval(-7_200),
                updatedAt: dayStart.addingTimeInterval(-7_200),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666667")!,
                spaceID: singleSpaceID,
                listID: planningListID,
                projectID: launchProjectID,
                creatorID: currentUserID,
                title: "补发昨天遗漏的里程碑同步",
                notes: "这条任务故意保留为逾期态，用来验证 Today 的逾期提醒胶囊。",
                locationText: "项目同步",
                executionRole: .initiator,
                dueAt: dayStart.addingTimeInterval(3_600 * 8),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 7 + 1_800),
                status: .inProgress,
                latestResponse: nil,
                responseHistory: [],
                createdAt: dayStart.addingTimeInterval(-86_400 * 2),
                updatedAt: dayStart.addingTimeInterval(-86_400),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666668")!,
                spaceID: singleSpaceID,
                listID: planningListID,
                projectID: migrationProjectID,
                creatorID: currentUserID,
                title: "归档旧版文档映射表",
                notes: "这是一条已经完成并进入历史区的任务样本。",
                locationText: "历史样本",
                executionRole: .initiator,
                dueAt: dayStart.addingTimeInterval(-86_400 * 45),
                hasExplicitTime: false,
                remindAt: nil,
                status: .completed,
                latestResponse: nil,
                responseHistory: [],
                createdAt: dayStart.addingTimeInterval(-86_400 * 55),
                updatedAt: dayStart.addingTimeInterval(-86_400 * 35),
                completedAt: dayStart.addingTimeInterval(-86_400 * 35),
                isPinned: false,
                isDraft: false,
                isArchived: true,
                archivedAt: dayStart.addingTimeInterval(-86_400 * 5)
            ),
            Item(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777771")!,
                spaceID: pairSharedSpaceID,
                listID: todayListID,
                projectID: nil,
                creatorID: currentUserID,
                title: "一起确认周末出行清单",
                notes: "今晚一起把行李、证件和路线再过一遍。",
                locationText: "双人空间",
                executionRole: .both,
                assigneeMode: .both,
                dueAt: dayStart.addingTimeInterval(3_600 * 19),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 18 + 1_800),
                status: .inProgress,
                assignmentState: .active,
                latestResponse: nil,
                responseHistory: [],
                assignmentMessages: [
                    TaskAssignmentMessage(
                        authorID: currentUserID,
                        body: "一起确认下别漏东西。",
                        createdAt: dayStart.addingTimeInterval(3_600 * 11)
                    )
                ],
                lastActionByUserID: currentUserID,
                lastActionAt: dayStart.addingTimeInterval(3_600 * 11),
                createdAt: dayStart.addingTimeInterval(-18_000),
                updatedAt: dayStart.addingTimeInterval(3_600 * 11),
                completedAt: nil,
                isPinned: true,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777772")!,
                spaceID: pairSharedSpaceID,
                listID: planningListID,
                projectID: nil,
                creatorID: currentUserID,
                title: "请 TA 订好明晚餐厅",
                notes: "想找安静一点、步行可达的地方。",
                locationText: "双人空间",
                executionRole: .recipient,
                assigneeMode: .partner,
                dueAt: dayStart.addingTimeInterval(3_600 * 17),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 16 + 1_800),
                status: .pendingConfirmation,
                assignmentState: .pendingResponse,
                latestResponse: nil,
                responseHistory: [],
                assignmentMessages: [
                    TaskAssignmentMessage(
                        authorID: currentUserID,
                        body: "你来挑一家更适合聊天的店吧。",
                        createdAt: dayStart.addingTimeInterval(3_600 * 9)
                    )
                ],
                lastActionByUserID: currentUserID,
                lastActionAt: dayStart.addingTimeInterval(3_600 * 9),
                createdAt: dayStart.addingTimeInterval(-12_000),
                updatedAt: dayStart.addingTimeInterval(3_600 * 9),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777773")!,
                spaceID: pairSharedSpaceID,
                listID: planningListID,
                projectID: nil,
                creatorID: partnerUserID,
                title: "我来补齐旅行药品包",
                notes: "已经买好创可贴和常用药。",
                locationText: "双人空间",
                executionRole: .initiator,
                assigneeMode: .self,
                dueAt: dayStart.addingTimeInterval(3_600 * 20),
                hasExplicitTime: true,
                remindAt: dayStart.addingTimeInterval(3_600 * 19 + 1_800),
                status: .inProgress,
                assignmentState: .active,
                latestResponse: ItemResponse(
                    responderID: partnerUserID,
                    kind: .acknowledged,
                    message: "我今晚顺手搞定",
                    respondedAt: dayStart.addingTimeInterval(3_600 * 10)
                ),
                responseHistory: [
                    ItemResponse(
                        responderID: partnerUserID,
                        kind: .acknowledged,
                        message: "我今晚顺手搞定",
                        respondedAt: dayStart.addingTimeInterval(3_600 * 10)
                    )
                ],
                assignmentMessages: [
                    TaskAssignmentMessage(
                        authorID: partnerUserID,
                        body: "我今晚顺手搞定",
                        createdAt: dayStart.addingTimeInterval(3_600 * 10)
                    )
                ],
                lastActionByUserID: partnerUserID,
                lastActionAt: dayStart.addingTimeInterval(3_600 * 10),
                createdAt: dayStart.addingTimeInterval(-20_000),
                updatedAt: dayStart.addingTimeInterval(3_600 * 10),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            )
        ]
    }

    static func makeDecisions() -> [Decision] {
        [
            Decision(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777771")!,
                spaceID: singleSpaceID,
                creatorID: partnerUserID,
                template: .eat,
                title: "今晚试试新开的潮汕牛肉火锅？",
                notes: "离家 15 分钟，排队可能要 20 分钟",
                referenceLink: URL(string: "https://example.com/hotpot"),
                proposedTime: now.addingTimeInterval(3_600 * 5),
                status: .pendingResponse,
                votes: [
                    DecisionVote(voterID: partnerUserID, value: .agree, respondedAt: now.addingTimeInterval(-1_800))
                ],
                createdAt: now.addingTimeInterval(-3_600),
                updatedAt: now.addingTimeInterval(-1_800),
                archivedAt: nil,
                convertedItemID: nil,
                isDraft: false
            ),
            Decision(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777772")!,
                spaceID: singleSpaceID,
                creatorID: currentUserID,
                template: .go,
                title: "五一去杭州吗？",
                notes: "预算先控制在 4k 内",
                referenceLink: nil,
                proposedTime: now.addingTimeInterval(86_400 * 50),
                status: .noConsensusYet,
                votes: [
                    DecisionVote(voterID: currentUserID, value: .agree, respondedAt: now.addingTimeInterval(-86_400)),
                    DecisionVote(voterID: partnerUserID, value: .neutral, respondedAt: now.addingTimeInterval(-43_200))
                ],
                createdAt: now.addingTimeInterval(-86_400 * 2),
                updatedAt: now.addingTimeInterval(-43_200),
                archivedAt: nil,
                convertedItemID: nil,
                isDraft: false
            ),
            Decision(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777773")!,
                spaceID: singleSpaceID,
                creatorID: currentUserID,
                template: .buy,
                title: "要不要买空气炸锅？",
                notes: "厨房收纳尺寸够放一台小号",
                referenceLink: nil,
                proposedTime: nil,
                status: .consensusReached,
                votes: [
                    DecisionVote(voterID: currentUserID, value: .agree, respondedAt: now.addingTimeInterval(-86_400 * 3)),
                    DecisionVote(voterID: partnerUserID, value: .agree, respondedAt: now.addingTimeInterval(-86_400 * 3 + 600))
                ],
                createdAt: now.addingTimeInterval(-86_400 * 3),
                updatedAt: now.addingTimeInterval(-86_400 * 3 + 600),
                archivedAt: nil,
                convertedItemID: nil,
                isDraft: false
            )
        ]
    }

    static func makeAnniversaries() -> [Anniversary] {
        [
            Anniversary(
                id: UUID(uuidString: "88888888-8888-8888-8888-888888888881")!,
                spaceID: singleSpaceID,
                name: "在一起纪念日",
                kind: .relationshipStart,
                eventDate: now.addingTimeInterval(-86_400 * 520),
                reminderRule: ReminderRule(leadDays: 7, remindAtHour: 9, remindAtMinute: 0),
                createdAt: now.addingTimeInterval(-86_400 * 520),
                updatedAt: now.addingTimeInterval(-86_400 * 10)
            ),
            Anniversary(
                id: UUID(uuidString: "88888888-8888-8888-8888-888888888882")!,
                spaceID: singleSpaceID,
                name: "结婚纪念日",
                kind: .wedding,
                eventDate: now.addingTimeInterval(86_400 * 12),
                reminderRule: ReminderRule(leadDays: 3, remindAtHour: 10, remindAtMinute: 0),
                createdAt: now.addingTimeInterval(-86_400 * 220),
                updatedAt: now.addingTimeInterval(-86_400 * 20)
            )
        ]
    }

    static func makeTaskLists() -> [TaskList] {
        [
            TaskList(
                id: inboxListID,
                spaceID: singleSpaceID,
                name: "收集箱",
                kind: .systemInbox,
                colorToken: "slate",
                sortOrder: 0,
                isArchived: false,
                taskCount: 1,
                createdAt: now.addingTimeInterval(-86_400 * 60),
                updatedAt: now
            ),
            TaskList(
                id: todayListID,
                spaceID: singleSpaceID,
                name: "Today",
                kind: .systemToday,
                colorToken: "coral",
                sortOrder: 1,
                isArchived: false,
                taskCount: 3,
                createdAt: now.addingTimeInterval(-86_400 * 60),
                updatedAt: now
            ),
            TaskList(
                id: planningListID,
                spaceID: singleSpaceID,
                name: "产品规划",
                kind: .custom,
                colorToken: "moss",
                sortOrder: 2,
                isArchived: false,
                taskCount: 2,
                createdAt: now.addingTimeInterval(-86_400 * 24),
                updatedAt: now.addingTimeInterval(-3_600)
            )
        ]
    }

    static func makeProjects() -> [Project] {
        [
            Project(
                id: focusProjectID,
                spaceID: singleSpaceID,
                name: "单人模式架构收敛",
                notes: "先把文档、导航、领域模型和 mock 层统一。",
                colorToken: "forest",
                status: .active,
                targetDate: now.addingTimeInterval(86_400 * 3),
                remindAt: now.addingTimeInterval(86_400 * 3 - 3_600),
                taskCount: 3,
                createdAt: now.addingTimeInterval(-86_400 * 5),
                updatedAt: now.addingTimeInterval(-1_800),
                completedAt: nil
            ),
            Project(
                id: launchProjectID,
                spaceID: singleSpaceID,
                name: "Today 交互动效打磨",
                notes: "聚焦完成反馈、日期切换和详情展开的原生质感。",
                colorToken: "sand",
                status: .onHold,
                targetDate: now.addingTimeInterval(86_400 * 10),
                remindAt: now.addingTimeInterval(86_400 * 10 - 7_200),
                taskCount: 2,
                createdAt: now.addingTimeInterval(-86_400 * 8),
                updatedAt: now.addingTimeInterval(-43_200),
                completedAt: nil
            ),
            Project(
                id: migrationProjectID,
                spaceID: singleSpaceID,
                name: "旧文档迁移",
                notes: "双人优先逻辑已经降级为兼容层说明。",
                colorToken: "stone",
                status: .completed,
                targetDate: now.addingTimeInterval(-86_400),
                remindAt: nil,
                taskCount: 1,
                createdAt: now.addingTimeInterval(-86_400 * 14),
                updatedAt: now.addingTimeInterval(-86_400),
                completedAt: now.addingTimeInterval(-86_400)
            )
        ]
    }

    static func makeProjectSubtasks() -> [ProjectSubtask] {
        [
            ProjectSubtask(
                projectID: focusProjectID,
                title: "统一首页与项目页的信息层级",
                sortOrder: 0
            ),
            ProjectSubtask(
                projectID: focusProjectID,
                title: "清理动效与布局的冲突状态",
                isCompleted: true,
                sortOrder: 1
            ),
            ProjectSubtask(
                projectID: focusProjectID,
                title: "补齐项目模式的收尾验收",
                sortOrder: 2
            ),
            ProjectSubtask(
                projectID: launchProjectID,
                title: "压缩顶部周视图与列表间距",
                isCompleted: true,
                sortOrder: 0
            ),
            ProjectSubtask(
                projectID: launchProjectID,
                title: "统一进入与返回的动画语义",
                sortOrder: 1
            ),
            ProjectSubtask(
                projectID: migrationProjectID,
                title: "完成旧文档字段映射",
                isCompleted: true,
                sortOrder: 0
            )
        ]
    }

    // MARK: - Periodic Tasks

    static func makePeriodicTasks() -> [PeriodicTask] {
        [
            PeriodicTask(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                spaceID: singleSpaceID,
                creatorID: currentUserID,
                title: "整理桌面和工作区",
                notes: nil,
                cycle: .weekly,
                reminderRules: [PeriodicReminderRule(timing: .daysBeforeEnd(1))],
                completions: [],
                sortOrder: 0,
                isActive: true,
                createdAt: now.addingTimeInterval(-86_400 * 30),
                updatedAt: now
            ),
            PeriodicTask(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAB")!,
                spaceID: singleSpaceID,
                creatorID: currentUserID,
                title: "回顾本周计划",
                notes: "检查进度、调整优先级",
                cycle: .weekly,
                reminderRules: [PeriodicReminderRule(timing: .dayOfPeriod(5))],
                completions: [],
                sortOrder: 1,
                isActive: true,
                createdAt: now.addingTimeInterval(-86_400 * 30),
                updatedAt: now
            ),
            PeriodicTask(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAC")!,
                spaceID: singleSpaceID,
                creatorID: currentUserID,
                title: "检查月度预算",
                notes: nil,
                cycle: .monthly,
                reminderRules: [PeriodicReminderRule(timing: .dayOfPeriod(20))],
                completions: [],
                sortOrder: 0,
                isActive: true,
                createdAt: now.addingTimeInterval(-86_400 * 60),
                updatedAt: now
            ),
            PeriodicTask(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAD")!,
                spaceID: singleSpaceID,
                creatorID: currentUserID,
                title: "信用卡还款",
                notes: nil,
                cycle: .monthly,
                reminderRules: [PeriodicReminderRule(timing: .businessDayOfPeriod(3))],
                completions: [],
                sortOrder: 1,
                isActive: true,
                createdAt: now.addingTimeInterval(-86_400 * 60),
                updatedAt: now
            ),
            PeriodicTask(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAE")!,
                spaceID: singleSpaceID,
                creatorID: currentUserID,
                title: "备份重要文件",
                notes: "照片、文档、代码仓库",
                cycle: .monthly,
                reminderRules: [PeriodicReminderRule(timing: .daysBeforeEnd(5))],
                completions: [],
                sortOrder: 2,
                isActive: true,
                createdAt: now.addingTimeInterval(-86_400 * 60),
                updatedAt: now
            ),
            PeriodicTask(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAF")!,
                spaceID: singleSpaceID,
                creatorID: currentUserID,
                title: "牙科检查",
                notes: nil,
                cycle: .quarterly,
                reminderRules: [PeriodicReminderRule(timing: .daysBeforeEnd(14))],
                completions: [],
                sortOrder: 0,
                isActive: true,
                createdAt: now.addingTimeInterval(-86_400 * 90),
                updatedAt: now
            ),
            PeriodicTask(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAA0A")!,
                spaceID: singleSpaceID,
                creatorID: currentUserID,
                title: "更新个人简历",
                notes: nil,
                cycle: .quarterly,
                reminderRules: [],
                completions: [],
                sortOrder: 1,
                isActive: true,
                createdAt: now.addingTimeInterval(-86_400 * 90),
                updatedAt: now
            ),
            PeriodicTask(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAA0B")!,
                spaceID: singleSpaceID,
                creatorID: currentUserID,
                title: "年度体检",
                notes: nil,
                cycle: .yearly,
                reminderRules: [PeriodicReminderRule(timing: .daysBeforeEnd(30))],
                completions: [],
                sortOrder: 0,
                isActive: true,
                createdAt: now.addingTimeInterval(-86_400 * 365),
                updatedAt: now
            )
        ]
    }
}
