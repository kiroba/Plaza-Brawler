# Sound effects: credits and licence

| File | Cue | Original file | Made by | Licence |
| --- | --- | --- | --- | --- |
| hit.ogg | landed light hit | `Audio/impactPunch_medium_001.ogg` | Kenney, Impact Sounds 1.0 | CC0 1.0 |
| heavy.ogg | landed heavy, special (Flare Rush etc.) or guard break | `Audio/impactPunch_heavy_002.ogg` | Kenney, Impact Sounds 1.0 | CC0 1.0 |
| block.ogg | blocked hit | `Audio/impactSoft_medium_000.ogg` | Kenney, Impact Sounds 1.0 | CC0 1.0 |
| ko.ogg | K.O. | `Audio/impactPunch_heavy_000.ogg` | Kenney, Impact Sounds 1.0 | CC0 1.0 |
| select.wav | menu select blip | synthesized by `tools/sfx_gen.py` | original (code, no samples) | CC0 1.0 |

The four fight sounds are from **Impact Sounds** by Kenney (www.kenney.nl):
https://kenney.nl/assets/impact-sounds. They are copied unchanged from the pack and renamed. The pack's
`License.txt` says: "License: (Creative Commons Zero, CC0) http://creativecommons.org/publicdomain/zero/1.0/
... This content is free to use in personal, educational and commercial projects. Support us by crediting
Kenney or www.kenney.nl (this is not mandatory)." Thanks, Kenney.

The menu blip is generated from code (sine tones) and dedicated to the public domain under CC0 1.0
Universal: https://creativecommons.org/publicdomain/zero/1.0/. To change it, edit `tools/sfx_gen.py` and
run `python3 tools/sfx_gen.py` (standard library only; the output is byte-identical for the same script).

Playback uses the `audioplayers` package (MIT licence).
