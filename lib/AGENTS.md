# AGENTS.md — Plaza-Brawler

Rules for any AI agent working in this repository. Owner: Kiro. Keeper of the
project source of truth: George. If this file conflicts with the source of
truth ("Omniverse Status for NotebookLM — FINAL Source of Truth (Nov 6, 2026)",
Google Doc), the source of truth wins — flag the conflict to George.

## Project
Flutter/Dart 3 fighting game. Public playtest: Nov 28, 2026 (STLGameDev).
Feature freeze: Sun Nov 22, 2026. After the freeze, fixes only.

## Hard rules
- `lib/game/` is pure Dart: NO Flutter imports, NO `dart:ui` imports. Ever.
- No JavaScript anywhere in this project.
- `omni_core_ui` is pinned to git ref v0.1.3 in pubspec.yaml. Do not bump it
  without Kiro's decision recorded in the source of truth first.
- minSdk is 26. Do not raise it.
- No new dependencies without Kiro's decision recorded in the source of truth.
- No work on The-Omni-Hub (frozen until after the playtest).

## Before opening any PR
- `flutter analyze` — zero errors, zero warnings.
- `flutter test` — all tests pass. Run both locally and say so in the PR.
- One small PR per issue; reference the issue number; keep changes
  single-purpose.

## Releases
- Never hand-build or hand-upload release APKs; releases come from CI.
- Any APK with package name `com.omniverse.node` (Omni Node) is built ONLY by
  the kiroba/Omni-Node-Daemon CI tag pipeline — never locally.

## Shipped features — do not regress
Kiosk mode (PIN + attract), the arcade ladder (11 Zodiac signs + Ophiuchus
boss), Omni Node match sharing, and feedback CSV export via share_plus.
Tests exist for these; keep them green.
