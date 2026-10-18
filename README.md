# CleanSheet

A free, open-source Mac cleaner. No account, no login, no telemetry. GPL-3.0.

Developed by **PbW Code Engine**.

## Features (v0.1)
- **Scan**: app caches, logs, Xcode DerivedData, npm/Gradle/Cargo caches and old .dmg installers, each with the reason it is safe.
- **Disk Map**: what takes the most space (read-only).
- **Duplicates**: found by content (SHA-256); at least one copy is always kept.
- **Apps**: uninstall with related files (Apple apps are never listed).
- **Startup**: disable agents in `~/Library/LaunchAgents`.
- **Quarantine**: nothing is deleted directly; everything is kept 30 days and can be restored.
- **Activity**: local log of everything the app did.

## Safety
Every action goes through `SafetyGuard` (`Sources/CleanSheetCore/SafetyGuard.swift`). System folders, your home folder, keys, iCloud Drive, Photos/Music libraries and symlinks into protected areas are always blocked.

## Build
```
swift run CoreChecks        # core safety checks
./scripts/build-app.sh      # builds dist/CleanSheet.app (~2 MB; limit is 100 MB)
```
No Apple account needed: the app is ad-hoc signed. On first launch, right-click → Open.

## Roadmap
- v1.1: **Tunnel** tab, a WireGuard config manager with a community-maintained node list (US, China, Spain, Portugal). The project does not host servers.
