# Task Template Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add task templates that can be saved from task detail and reused from the creation sheet without copying date values.

**Architecture:** Use a dedicated `TaskTemplate` model and repository so templates do not pollute live tasks. Save templates from `TaskDraft`, then rehydrate a new task draft against the current selected date when the user applies a template.

**Tech Stack:** SwiftUI, SwiftData, Observation, repository protocol pattern

---

### Task 1: Add template persistence boundary

**Files:**
- Create: `/Users/papertiger/Desktop/Together/Together/Domain/Entities/TaskTemplate.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Domain/Protocols/TaskTemplateRepositoryProtocol.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Persistence/Models/PersistentTaskTemplate.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Services/TaskTemplates/LocalTaskTemplateRepository.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Services/TaskTemplates/MockTaskTemplateRepository.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Persistence/PersistenceController.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/App/AppContainer.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Services/LocalServiceFactory.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Services/MockServiceFactory.swift`

### Task 2: Save templates from task detail

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Home/HomeViewModel.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Home/HomeItemDetailSheet.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/App/AppContext.swift`

### Task 3: Apply templates in the composer

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/Together/Features/Shared/ComposerPlaceholderSheet.swift`

### Task 4: Verify with tests

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/TogetherTests/TogetherTests.swift`
