import Foundation

enum MockDataFactory {
    static let currentUserID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let partnerUserID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let pairSpaceID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let dataBoundaryToken = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    static let now = Date(timeIntervalSince1970: 1_773_000_000)

    static func makeCurrentUser() -> User {
        User(
            id: currentUserID,
            appleUserID: "apple-user-demo",
            displayName: "云丰",
            avatarSystemName: "person.crop.circle.fill",
            createdAt: now.addingTimeInterval(-86_400 * 120),
            updatedAt: now,
            preferences: NotificationSettings(
                newItemEnabled: true,
                decisionEnabled: true,
                anniversaryEnabled: true,
                deadlineEnabled: true
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
                newItemEnabled: true,
                decisionEnabled: true,
                anniversaryEnabled: true,
                deadlineEnabled: false
            )
        )
    }

    static func makePairSpace() -> PairSpace {
        PairSpace(
            id: pairSpaceID,
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
                relationshipID: pairSpaceID,
                creatorID: partnerUserID,
                title: "起床",
                notes: "今天要一起早出门，闹钟响了给我回个表情。",
                locationText: "家里",
                executionRole: .recipient,
                priority: .important,
                dueAt: dayStart.addingTimeInterval(3_600 * 7),
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
                relationshipID: pairSpaceID,
                creatorID: currentUserID,
                title: "开会",
                notes: "晨会结束后同步一下中午是否一起吃饭。",
                locationText: "公司会议室",
                executionRole: .both,
                priority: .critical,
                dueAt: dayStart.addingTimeInterval(3_600 * 8 + 1_200),
                remindAt: dayStart.addingTimeInterval(3_600 * 8),
                status: .inProgress,
                latestResponse: ItemResponse(
                    responderID: partnerUserID,
                    kind: .willing,
                    message: "会后碰一下",
                    respondedAt: dayStart.addingTimeInterval(3_600 * 7 + 900)
                ),
                responseHistory: [
                    ItemResponse(
                        responderID: partnerUserID,
                        kind: .willing,
                        message: "会后碰一下",
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
                relationshipID: pairSpaceID,
                creatorID: currentUserID,
                title: "喝水",
                notes: "下午别忘了补水，我会在群里提醒你。",
                locationText: nil,
                executionRole: .initiator,
                priority: .normal,
                dueAt: dayStart.addingTimeInterval(3_600 * 10 + 1_800),
                remindAt: dayStart.addingTimeInterval(3_600 * 10),
                status: .inProgress,
                latestResponse: ItemResponse(
                    responderID: partnerUserID,
                    kind: .acknowledged,
                    message: "收到",
                    respondedAt: dayStart.addingTimeInterval(3_600 * 9 + 600)
                ),
                responseHistory: [
                    ItemResponse(
                        responderID: partnerUserID,
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
                relationshipID: pairSpaceID,
                creatorID: partnerUserID,
                title: "任务优先级排序",
                notes: "午休前把今天最重要的两件事排出来。",
                locationText: "共享清单",
                executionRole: .both,
                priority: .important,
                dueAt: dayStart.addingTimeInterval(3_600 * 14),
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
                relationshipID: pairSpaceID,
                creatorID: currentUserID,
                title: "放松",
                notes: "睡前留半小时一起散步或者看一集剧。",
                locationText: "客厅",
                executionRole: .both,
                priority: .normal,
                dueAt: dayStart.addingTimeInterval(3_600 * 21 + 7_200),
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
                relationshipID: pairSpaceID,
                creatorID: partnerUserID,
                title: "顺路带牛奶",
                notes: "如果超市有低糖酸奶也一起带。",
                locationText: "小区北门盒马",
                executionRole: .recipient,
                priority: .important,
                dueAt: dayStart.addingTimeInterval(86_400 + 3_600 * 6),
                remindAt: dayStart.addingTimeInterval(86_400 + 3_600 * 4),
                status: .pendingConfirmation,
                latestResponse: nil,
                responseHistory: [],
                createdAt: dayStart.addingTimeInterval(-7_200),
                updatedAt: dayStart.addingTimeInterval(-7_200),
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
                relationshipID: pairSpaceID,
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
                relationshipID: pairSpaceID,
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
                relationshipID: pairSpaceID,
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
                relationshipID: pairSpaceID,
                name: "在一起纪念日",
                kind: .relationshipStart,
                eventDate: now.addingTimeInterval(-86_400 * 520),
                reminderRule: ReminderRule(leadDays: 7, remindAtHour: 9, remindAtMinute: 0),
                createdAt: now.addingTimeInterval(-86_400 * 520),
                updatedAt: now.addingTimeInterval(-86_400 * 10)
            ),
            Anniversary(
                id: UUID(uuidString: "88888888-8888-8888-8888-888888888882")!,
                relationshipID: pairSpaceID,
                name: "结婚纪念日",
                kind: .wedding,
                eventDate: now.addingTimeInterval(86_400 * 12),
                reminderRule: ReminderRule(leadDays: 3, remindAtHour: 10, remindAtMinute: 0),
                createdAt: now.addingTimeInterval(-86_400 * 220),
                updatedAt: now.addingTimeInterval(-86_400 * 20)
            )
        ]
    }
}
