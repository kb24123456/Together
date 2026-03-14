# Task Application And Sync Boundary Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a stable task use-case layer for the single-user Todo MVP and reserve a clean future CloudKit sync boundary without changing UI.

**Architecture:** Keep SwiftUI views and view models thin by moving task creation, mutation, completion, and scoped querying into a dedicated application service. Record local write events through a sync coordinator protocol so future CloudKit integration can consume a stable change stream instead of reaching directly into views or repositories.

**Tech Stack:** Swift, SwiftData, Swift Testing

---

### Task 1: Add task application service contracts

**Files:**
- Create: `/Users/papertiger/Desktop/Together/Together/Application/Tasks/TaskApplicationServiceProtocol.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Application/Tasks/TaskDraft.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Application/Tasks/TaskScope.swift`

### Task 2: Add sync boundary contracts

**Files:**
- Create: `/Users/papertiger/Desktop/Together/Together/Sync/SyncCoordinatorProtocol.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Sync/CloudSyncGatewayProtocol.swift`
- Create: `/Users/papertiger/Desktop/Together/Together/Sync/NoOpSyncCoordinator.swift`

### Task 3: Implement default task application service

**Files:**
- Create: `/Users/papertiger/Desktop/Together/Together/Application/Tasks/DefaultTaskApplicationService.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/App/AppContainer.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Services/LocalServiceFactory.swift`
- Modify: `/Users/papertiger/Desktop/Together/Together/Services/MockServiceFactory.swift`

### Task 4: Add tests for use cases and sync emission

**Files:**
- Modify: `/Users/papertiger/Desktop/Together/TogetherTests/TogetherTests.swift`

