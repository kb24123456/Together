# 审核说明草稿

尚未写入 ASC。品牌和版本号确定、正式构建验收后再使用。

## English notes

This update changes the app to a personal task manager. The previous two-person collaboration, third-party account sign-in, and in-app purchase entry points have been removed. No separate developer account or demo login is required for local task management. iCloud sync and restore use the device user's Apple Account and the app's private CloudKit database.

Suggested review flow:

1. Launch the app and use the plus button to create a task. Add a note, subtasks, a date, and optional time/reminder settings.
2. Switch to the recurring-task view at the top to create a repeating task.
3. Use the bottom-left import menu to take a photo, select an image, or paste text. Recognition and parsing produce an editable draft. Tasks are saved only after the user confirms the draft.
4. Open Profile from the top-right avatar to access completed tasks, execution reviews, preferences, and data management.
5. Add a Home Screen widget to view tasks. Following an unfinished regular task enables the task Live Activity when supported and allowed by the system.

Camera, photo, notification, alarm, and biometric permissions are requested for the corresponding optional features. Denying these permissions does not require creating a developer account. Please use the actual version's localized labels when navigating; English App Store metadata does not imply that all in-app text is translated.

## Before submission

- Replace any path or label that differs from the final build after device testing.
- Validate clean launch, existing-data upgrade, iCloud production sync, data deletion, widgets, reminders, and Live Activities with the actual uploaded build.
- Keep the old in-app purchases out of this submission; review historical purchase handling before making storefront availability changes.
- Ensure the support and policy URLs are deployed and accessible, with matching links in the App.
- Review app privacy and age rating answers against the final app. Do not declare accessibility support solely because corresponding modifiers exist in code.
- Keep reviewer contact information private; retain verified ASC contact fields instead of copying personal contact details into this repository.
