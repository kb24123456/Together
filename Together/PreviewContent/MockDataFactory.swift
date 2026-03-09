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
        [
            Item(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666661")!,
                relationshipID: pairSpaceID,
                creatorID: partnerUserID,
                title: "今晚回家顺路带牛奶",
                notes: "如果超市有低糖酸奶也可以一起带",
                locationText: "小区北门盒马",
                executionRole: .recipient,
                priority: .important,
                dueAt: now.addingTimeInterval(3_600 * 6),
                remindAt: now.addingTimeInterval(3_600 * 4),
                status: .pendingConfirmation,
                latestResponse: nil,
                responseHistory: [],
                createdAt: now.addingTimeInterval(-3_600 * 2),
                updatedAt: now.addingTimeInterval(-3_600 * 2),
                completedAt: nil,
                isPinned: true,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666662")!,
                relationshipID: pairSpaceID,
                creatorID: currentUserID,
                title: "一起确认周末看房时间",
                notes: "中介给了两个时间段，今晚前定下来",
                locationText: "工作室附近咖啡店",
                executionRole: .both,
                priority: .critical,
                dueAt: now.addingTimeInterval(86_400),
                remindAt: now.addingTimeInterval(43_200),
                status: .inProgress,
                latestResponse: ItemResponse(
                    responderID: partnerUserID,
                    kind: .willing,
                    message: "今晚吃完饭一起看",
                    respondedAt: now.addingTimeInterval(-1_800)
                ),
                responseHistory: [
                    ItemResponse(
                        responderID: partnerUserID,
                        kind: .willing,
                        message: "今晚吃完饭一起看",
                        respondedAt: now.addingTimeInterval(-1_800)
                    )
                ],
                createdAt: now.addingTimeInterval(-86_400),
                updatedAt: now.addingTimeInterval(-1_800),
                completedAt: nil,
                isPinned: false,
                isDraft: false
            ),
            Item(
                id: UUID(uuidString: "66666666-6666-6666-6666-666666666663")!,
                relationshipID: pairSpaceID,
                creatorID: currentUserID,
                title: "我来预约体检，你先知情",
                notes: "预约好后把时间同步给你",
                locationText: "市一医院体检中心",
                executionRole: .initiator,
                priority: .normal,
                dueAt: now.addingTimeInterval(86_400 * 3),
                remindAt: nil,
                status: .inProgress,
                latestResponse: ItemResponse(
                    responderID: partnerUserID,
                    kind: .acknowledged,
                    message: "收到",
                    respondedAt: now.addingTimeInterval(-7_200)
                ),
                responseHistory: [
                    ItemResponse(
                        responderID: partnerUserID,
                        kind: .acknowledged,
                        message: "收到",
                        respondedAt: now.addingTimeInterval(-7_200)
                    )
                ],
                createdAt: now.addingTimeInterval(-43_200),
                updatedAt: now.addingTimeInterval(-7_200),
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
