---
name: quota
description: Build, launch, and diagnose the native Codex Quota macOS menu bar app in this repository when the user asks to display or inspect their Codex subscription quota.
---

# Codex Quota

Locate the codex_quota repository containing Sources/Quota.swift and scripts/build.sh. If this plugin has been copied independently, ask for the repository path; do not assume that its cached installation contains the application sources.

- Build with `./scripts/build.sh` from the repository root.
- Launch with `open "dist/Codex Quota.app"`.
- Perform a read-only live check with `"dist/Codex Quota.app/Contents/MacOS/CodexQuota" --probe`.
- Run `./scripts/test.sh` for decoding and transport checks.
- The app uses the existing Codex ChatGPT login through `codex app-server` and `account/rateLimits/read`. Do not extract credentials or query API billing as a replacement.
- Display remaining percentage as `100 - usedPercent`, clamped to 0–100. Missing data is unavailable, never zero. Prefer the `codex` entry in `rateLimitsByLimitId` over the legacy field.
- Network or login failures must be reported; old snapshots must be identified as stale.
- This plugin is a companion for managing the native app. The app runs on its own and refreshes every 60 seconds without a Codex conversation or model call.
