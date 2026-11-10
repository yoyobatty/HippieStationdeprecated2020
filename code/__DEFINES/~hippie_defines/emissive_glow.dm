// How strongly things glow in the dark (emissive_glow_alpha, 0-255). See hippiestation/code/modules/lighting/emissive_glow.dm.
/// Screens, displays, lamps and carried lights: things that are obviously lit
#define EMISSIVE_GLOW_FULL 255
/// Bar signs and the tesla ball: at full strength their letters and arcs blur into one
#define EMISSIVE_GLOW_SIGN 170
/// Indicator lights and small panels: airlocks, air alarms, buttons, intercoms, cameras, chargers, telecomms...
#define EMISSIVE_GLOW_INDICATOR 140
/// Disposal bins
#define EMISSIVE_GLOW_FAINT 110

/// A glow smaller than this many pixels (a camera's lens, a button's lamp) casts no light of its own
#define EMISSIVE_GLOW_LIGHT_MIN_PIXELS 12
