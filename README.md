# Plaza Brawler

A 2D fighter mini-game for **The Omniverse** by **Hactik Games Studios**, written in Flutter (Android first). You fight an
OmniMind opponent in the Halo Plaza arena: move, jump and punch until one fighter's HP runs out.
Or play **online PvP versus**: pair with another player and fight in lockstep, with dual-signed
match results (proven phone-vs-laptop on Nov 15, 2026).

Screens: Boot → Main menu → Settings → Fight → Victory / Defeat.

**Windows build:** CI also builds a Windows desktop build for repeated playtesting, with
controller support (A light · B heavy · X block · Y special, stick pushed up to jump) —
controller verified working Nov 15, 2026. The Android build is the event build of record for
the Nov 28, 2026 STLGameDev playtest.

**Houses:** the Houses subclass system, the default-Halo pack loader and LPE pack visuals
merged on Nov 16, 2026 (PR #34); the house table was ruled by Kiro the same day.

## Build and run

```sh
flutter pub get
flutter run                      # on a connected Android phone (Android 8.0+, minSdk 26)
flutter build apk --release --target-platform android-arm64 \
  --dart-define=OMNI_APP=plaza-brawler --dart-define=OMNI_BUILD=0
```

CI (`.github/workflows/build.yml`) builds a test APK for arm64 on every push and pull request to
`main` and uploads it as the `plaza-brawler-android-arm64` artifact. It is signed with the debug
key, like the other Omni app repos' CI builds.

Shared app code comes from [Omni-Core-UI](https://github.com/kiroba/Omni-Core-UI), pinned by git
tag `v0.1.0`.

## Omni Node

| Feature | Status |
|---|---|
| Connection check | **Wired.** `GET :9100/api/v1/telemetry/node-health` on Omni Node on this phone, through `OmniHubClient`. Status dot + words in Settings. |
| Omni Node token | **Wired.** Settings → paste the token from *Omni Node > Connect apps* (behind the screen lock). Sent as `Authorization: Bearer`. Stored with `flutter_secure_storage`. |
| Player identity | **Wired.** `StargateIdentity`: an Ed25519 key created on first launch. |
| Fight events (match start, hits, match end) | **Signed and kept on this phone** (`LocalEventStore`). Per-hit events never leave the phone. |
| Match results | **Wired, opt-in (Omni Node 8.28+).** Settings → *Share my match results* (off by default) is enabled once `node-health` lists `"features": ["games_match"]`. When it's on, each finished match's `MatchShare.payloadFrom` summary is POSTed once to `:5000/api/games/match` with the same Bearer token (200 = shared, 404 = node too old, anything else = kept on this phone; no retries, because the node doesn't de-duplicate). Since daemon 8.33.2 (Nov 15, 2026), PvP results travel as a dual-signed `pvp_match` envelope on the generic signed game-result contract. |
| PvP versus | **Wired and proven.** S1: pairing + transport (lobby, QR + code pairing, signed hello/ready handshake). S2: lockstep versus play (input exchange, seed agreement). S3: state-hash integrity — a desync means no result — plus the dual-signed result envelope. A full laptop-vs-phone match was played Nov 15, 2026. |
| Your fighter (Live Persona Engine, LPE) | **Needs Omni Node 8.25+.** When the node answers, `GET :5000/api/lpe/profile?pubkey=<your key>` gives your avatar, aura tier and XP, and `GET /api/lpe/plaza` gives a real opponent from the plaza (another known avatar). Read-only, same Bearer token. With an older node, no node, or no LPE profile for your key yet, the offline personas are used and labelled in the app. This app doesn't create LPE profiles yet — LPE does. |
| Opponent generation (OmniMind) | **Not wired yet.** There is no OmniMind asset endpoint; an offline Scorpio persona is used and labelled in the app. The fight AI runs on the phone. |
| Updates | Settings → *Check for updates* (`OmniOta.checkAndPrompt`). Plaza Brawler ships in The Omniverse release manifest (e.g. v0.2.0, Nov 15, 2026, as `plaza-brawler-android-arm64.apk`). |

Network: cleartext HTTP is allowed to `127.0.0.1` / `localhost` only (`network_security_config.xml`).

## Drafts (not built)

Drafted Nov 16, 2026 and deliberately not in the Nov 28 playtest scope: per-character music
tracks + a menu track, training mode, combos, a throw, a real pause menu, difficulty select,
more stages, alt colours per fighter, a new app icon, and the Hactik Games Studios splash
screen (the company's first use).

## Sound

Sounds are in `assets/sfx/`. Light hit, heavy hit (heavies, specials and guard breaks), block and
K.O. are from Kenney's [Impact Sounds](https://kenney.nl/assets/impact-sounds) pack (CC0); the
menu-select blip is synthesized by `tools/sfx_gen.py` (CC0). See
[assets/sfx/CREDITS.md](assets/sfx/CREDITS.md). Playback uses `audioplayers` in low-latency mode,
mixed with other apps' audio. Settings → *Sound effects* mutes them. If audio can't start, the game
plays silently; sound never stops a fight.

## Art pipeline (AI drafts)

`tools/asset_gen/` makes first-draft sprites, the stage background, effects and icons with open
models: FLUX.1 [schnell] on a free Kaggle/Colab GPU, or an OpenVINO model on an Intel PC.
Output stays in `assets/generated/` (git-ignored) with a provenance manifest. See
[tools/asset_gen/README.md](tools/asset_gen/README.md).
