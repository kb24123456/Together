-- Migration 010: drop task_messages.sender_id FK to auth.users.
--
-- Context: this codebase uses app-level local UUIDs for user identity (the
-- same scheme that migration 006 already freed five other sync tables from).
-- task_messages(sender_id) was added later (migration 001) and still carries
-- the legacy FK. Every push of task_messages from the client fails with a
-- foreign-key violation because sessionStore.currentUser.id never appears in
-- auth.users.
--
-- This migration drops that FK so task_messages can be written with the
-- same identity scheme as tasks/items/projects/etc.
ALTER TABLE public.task_messages
    DROP CONSTRAINT IF EXISTS task_messages_sender_id_fkey;
