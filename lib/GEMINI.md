# GEMINI.md — Plaza-Brawler (Gemini CLI context)

Twin of this repo's AGENTS.md, in the format Gemini CLI loads automatically.
Owner: Kiro. Source of truth: "Omniverse Status for NotebookLM — FINAL
Source of Truth (Nov 6, 2026)" (Google Doc) — it governs assignments; if this
file conflicts with it, the source of truth wins and the conflict goes to
George.

## Project
Flutter/Dart 3 fighting game. Public playtest: Nov 28, 2026 (STLGameDev).
Feature freeze: Sun Nov 22, 2026. After the freeze, fixes only.

## Hard rules
- `lib/game/` is pure Dart: NO Flutter imports, NO `dart:ui` imports. Ever.
- No JavaScript anywhere in this project.
- `omni_core_ui` is pinned to git ref v0.1.3 in pubspec.yaml — do not bump
  without Kiro's decision recorded in the source of truth.
- minSdk is 26. Do not raise it.
- No new dependencies without a recorded decision.
- No work on The-Omni-Hub (frozen until after the playtest).

## Working agreement
- Before proposing any PR: run `flutter analyze` (zero errors/warnings) and
  `flutter test` (all pass) from the repo root, and report the results.
- One small PR per issue; reference the issue number; single-purpose changes.
- Never hand-build or hand-upload release APKs; releases come from CI.
- APKs named `com.omniverse.node` are built ONLY by the
  kiroba/Omni-Node-Daemon CI tag pipeline.
- Do not regress shipped features: kiosk mode (PIN + attract), arcade ladder
  (11 Zodiac signs + Ophiuchus boss), Omni Node match sharing, feedback CSV
  export. Their tests stay green.
- Quota discipline: this seat shares one daily request cap between Android
  Studio Agent Mode and Gemini CLI. Work from the written spec in one pass;
  ask Kiro only when genuinely blocked.
