# v2 nebulae (tools/sky_gen/v2/nebula.py)

Nothing committed. Files touched: tools/sky_gen/v2/nebula.py, tools/sky_gen/v2/__init__.py (empty, created).
Run: `python tools/sky_gen/v2/nebula.py preview` (~10 s) | `python tools/sky_gen/v2/nebula.py dm` (DM lists, copy in nebula_dm_lists.txt here).

## Colour split: packed channels + colour matrix (one layer, three tones)
Each state is an opaque RGB 480x480 picture (drawn 2x, BLEND_ADD) with three greyscale fields in its channels:
- billows: R = body glow (+ faint envelope, backlight behind pillars), G = crests + lit rims + pillar-head fronts, B = hot core + embedded cluster stars
- veils: R = filament set A, G = filament set B (braided), B = sheet glow
- haze: R, G = two broad washes, B = 0
The game tints with a 9-number colour matrix: `color = list(body r,g,b, crest r,g,b, core r,g,b)`. dm_lists() folds alpha into the
matrix (alpha 255), so it doesn't depend on how BYOND mixes alpha var with a matrix colour.

## DM changes needed
1. sky_nebula.dmi gets the new states (billow1-5, veil1-2, haze) from `nebula.build_images()` (PIL RGBA, opaque). The old
   states (cloud1-3, wisp1-2, haze1-2, band) can stay until the band session replaces `band`.
2. sky_themes.dm nebula entries: element 2 becomes a list (matrix) instead of "#hex". `nebula_art()` already does
   `A.color = cloud[2]`, which takes a matrix as-is. Update the header comment.
3. sky_gen.py `read_themes()` regex only parses "#hex" colours: previews from sky_gen.py will skip matrix entries until it
   parses `list(...)` too (nebula.py's own preview uses its THEMES table).
4. map_view.dm:211 touches nebula layers; check it doesn't assume a hex colour.

## Round 2 (2026-11-20): on the galaxy band
- Gas, veils and haze lie along stars.py's band. `band_fields()` takes `stars.band_shape(960, 301)` at half scale, so a
  480 nebula tile drawn 2x is the band's 960 repeat. The band's rift cuts the gas, and haze B is now a seam on the band's
  middle line, so haze needs a real third matrix row.
- New state billow6 (gold's own, so it no longer shares billow4 with verdant). Thin facing-light edge rims, lit lips on dust
  lanes, unsharp mask for the 2x draw, roll-off by the packed-channel sum (`roll_packed`), so tints never clip.
- DM needs, on top of 1-4:
  5. Nebula layers turned by `band_angle` (`set_angle`), on the same 960 origin as the band layer.
  6. Headings along x only. THEMES now uses (+-1, 0) or (0, 0).
  7. Nebula speed close to the band layer's, so the gas stays on the band while walking (~0.1 vs galaxy 0.04 now).
- Previews: sky2_nebula_<theme>.png (v2 band + stars, turned to BAND_ANGLE[theme]) and sky2_nebula_<theme>_v1v2.png
  (round 1 | round 2).

## API
- build_states(n=480) -> {state: float (n,n,3) 0..1}; build_images() -> {state: PIL RGBA}
- billow_state(n, seed, cover, light, dust, pillars, core, reach, hole, blister), veil_state(n, seed, heading, cover), haze_state(n, seed)
- THEMES {theme: [(state, (body, crest, core) hex, alpha, speed, minutes, heading)]}; tone_matrix(), tint(), dm_matrix(), dm_lists()
- preview(): seam report, data/previews/sky2_nebula_<theme>.png (+ _ab strip, + _states.png / _states_rgb.png diagnostics)

## Round 3 (2026-11-20, after GPU FREE): final palettes
- Veils rebuilt: shock-front arcs (one level of a smooth band-wise field), bundles of thin strands measured in pixels,
  lit along one long stretch each (open arcs, no closed isoline loops); R strands, G the same front just behind, B a
  one-sided trailing glow. Old filament veil kept as fibre_veil_state (unused).
- billow3 is now a gas wall with a small cluster (core 0.3, hole 22), so violet/rose don't repeat the cavity motif.
- Gold veil alpha 110. nebula_dm_lists.txt here = final `nebula.py dm`.

## Round 4 (2026-11-21): installed
- Sparser band mask (floor 0.12), haze alphas down ~25%, stronger edge rims, crest textured by the billow octaves
  (no flat glow blobs), quiet veil 95. Preview tints the band from sky_themes.dm (`band_tint()`).
- Built with build_v2.py into data/sky_v2_stage_nebula; ONLY sky_nebula.dmi installed. sky_themes.dm: nebula lines
  only (6 changed: the hazes and quiet's veil).
- Sheet: data/previews/sky2_nebula_r5_before_after.png (round 3 | now). lookkit stats: contrast 0.17-0.22 -> 0.18-0.26,
  light+white 1.6-4.8% -> 2.4-10%.
