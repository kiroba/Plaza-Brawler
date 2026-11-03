# Sound effects: credits and licence

| File | What it is | Made by | Licence |
| --- | --- | --- | --- |
| hit.wav | landed hit (thump + noise) | synthesized by `tools/sfx_gen.py` | CC0 1.0 |
| block.wav | blocked hit ("clack") | synthesized by `tools/sfx_gen.py` | CC0 1.0 |
| ko.wav | K.O. (boom + falling tone) | synthesized by `tools/sfx_gen.py` | CC0 1.0 |
| select.wav | menu select blip | synthesized by `tools/sfx_gen.py` | CC0 1.0 |

All four are original sounds generated from code (sine/square tones and seeded noise; no recorded or
third-party samples). They are dedicated to the public domain under CC0 1.0 Universal:
https://creativecommons.org/publicdomain/zero/1.0/

To change them, edit `tools/sfx_gen.py` and run `python3 tools/sfx_gen.py` (standard library only; the
output is byte-identical for the same script).

Playback uses the `audioplayers` package (MIT licence).
