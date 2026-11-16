# Particle sprites

These sheets are tgstation's, unchanged, from `icons/effects/particles/` at commit
`8ae7ebcf4c74a915565ee816a80398c7056a4372` (tgstation/tgstation master, 2026-11-16). Licence: CC BY-SA 3.0, as all of
tgstation's icons are.

| Sheet | States | Used for |
| --- | --- | --- |
| `generic.dmi` | `dot`, `cross`, `curl`, `drop` | sparks, embers, chips, blood, shards, glints, wind streaks, air dust |
| `smoke.dmi` | `smoke_1-3`, `steam_1-3`, `ash_1-3`, `chill_1-3`, `steam_cloud_1-5` | smoke, steam, puffs of dust, burning debris, blast dust |
| `goop.dmi` | `goop_1-3` | acid |
| `stink.dmi` | `stink_1-3` | rot |
| `bonfire.dmi`, `pollen.dmi` | `bonfire`, `pollen` | not used yet |

The particle sets that colour and move them are in `hippiestation/code/modules/particles/`. They draw every sprite at its
own size or twice it, never turned and never growing, so the pixels stay hard.
