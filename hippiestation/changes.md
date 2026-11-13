# Differences with /tg/

The best practice to have while coding is to keep everything modularized, or the most possible. Sometimes, through,
 it's not possible and you're required to edit some files inside the code folder, which is /tg/'s code. This file is intended to have a list of the files changed.

# Sorted alphabetically filepath-wise.

## code/__DEFINES/diseases.dm
## code/__DEFINES/MC.dm
## code/__DEFINES/misc.dm
## code/__DEFINES/mobs.dm
## code/__DEFINES/role_preferences.dm
## code/__DEFINES/rust_g.dm (rust-g 7.0.0's file as released; was a cut-down copy. The SQL defines moved out of ~hippie_defines/sql.dm into it)
## code/__DEFINES/tgs.dm (TGS DMAPI 7.4.0, the upstream file as released; was 5.2.7)
## code/__HELPERS/\_logging.dm
## code/__HELPERS/AStar.dm
## code/__HELPERS/game.dm (get_hearers_in_view(): radios found once, a hearer added once, each tile and range remembered for the tick; get_mobs_in_radio_ranges() doesn't ask a radio with nobody but radios in reach)
## code/__HELPERS/icons.dm
## code/__HELPERS/mobs.dm
## code/__HELPERS/radiation.dm
## code/__HELPERS/roundend.dm
## code/__HELPERS/text.dm
## code/__HELPERS/unsorted.dm
## code/_onclick/adjacent.dm (ClickCross() copies a pile's contents first, LOOP_CONTENTS)
## code/_onclick/hud/parallax.dm (out of the .dme: rewritten whole as hippiestation/code/_onclick/hud/parallax.dm, the sky's layers come from the round's theme and slide with the eye's glide)
## code/\_onclick/item_attack.dm
## code/controllers/configuration/entries/dbconfig.dm
## code/controllers/failsafe.dm
## code/controllers/master.dm
## code/controllers/subsystem.dm
## code/controllers/subsystem/air.dm
## code/controllers/subsystem/assets.dm
## code/controllers/subsystem/blackbox.dm
## code/controllers/subsystem/dbcore.dm (out of the .dme: rewritten whole as hippiestation/code/controllers/subsystem/dbcore.dm, rust_g instead of BSQL)
## code/controllers/subsystem/discord.dm
## code/controllers/subsystem/explosions.dm (shaped explosions through hippiestation/code/controllers/subsystem/explosions_shape.dm; Check Bomb Impact; spread over ticks; blame; realistic blasts through hippiestation/code/modules/explosion_realism/: air, sealed rooms, glass past the damage, sounds, fragments)
## code/controllers/subsystem/garbage.dm
## code/controllers/subsystem/input.dm
## code/controllers/subsystem/job.dm
## code/controllers/subsystem/mapping.dm
## code/controllers/subsystem/machines.dm (fire() walks its run by index and cuts it once)
## code/controllers/subsystem/mobs.dm
## code/controllers/subsystem/stickyban.dm
## code/controllers/subsystem/throwing.dm (finalize() calls end_flight(): glide, look and landing, hippiestation/code/modules/throwing/throw_flight.dm)
## code/controllers/subsystem/ticker.dm
## code/controllers/subsystem/timer.dm
## code/controllers/subsystem/vote.dm
## code/datums/brain_damage/imaginary_friend.dm (the friend's picture is set up async and is never an AI's or a cyborg's)
## code/datums/components/chasm.dm (is_safe() by locate(), no copy of the tile's contents)
## code/datums/components/material_container.dm
## code/datums/components/squeak.dm (a pile of squeaky things squeaks once for each thing that comes onto it)
## code/datums/datumvars.dm
## code/datums/diseases/\_MobProcs.dm
## code/datums/elements/atmos_sensitive.dm
## code/datums/helper_datums/getrev.dm
## code/datums/hud.dm
## code/datums/mutations/actions.dm
## code/datums/mutations/body.dm
## code/datums/progressbar.dm
## code/datums/status_effects/neutral.dm
## code/datums/status_effects/status_effect.dm
## code/datums/tgs_event_handler.dm
## code/datums/wires/airlock.dm
## code/datums/world_topic.dm
## code/game/atoms_movable.dm (doMove() skips no_cross_checks like Move(); throw_at() keeps gentle and starts the flight, safe_throw_at() passes gentle on, hippiestation/code/modules/throwing/)
## code/game/gamemodes/changeling/changeling.dm !Should be modularized. Can be done easily.
## code/game/gamemodes/game_mode.dm
## code/game/gamemodes/traitor/traitor.dm !Should be modularized. Can be done easily.
## code/game/machinery/\_machinery.dm
## code/game/machinery/buttons.dm
## code/game/machinery/camera/camera.dm
## code/game/machinery/computer/atmos_control.dm (out of the .dme: rewritten whole as hippiestation/code/game/machinery/computer/atmos_control.dm, tg's later tank sensors and consoles: the sensor holds its tank's injector and vent, linked by multitool or by sharing a sealed tank, and the consoles drive them directly instead of by radio)
## code/game/machinery/computer/cloning.dm
## code/game/machinery/computer/communications.dm (the alert swipe reads a worn ID; a change locks the level for a minute, communications_tgui.dm)
## code/game/machinery/computer/security.dm
## code/game/machinery/doors/airlock.dm
## code/game/machinery/doors/airlock_types.dm !Should be modularized. Can be done easily.
## code/game/machinery/doors/brigdoors.dm
## code/game/machinery/flasher.dm
## code/game/machinery/telecomms/broadcasting.dm
## code/game/machinery/telecomms/telecomunications.dm
## code/game/mecha/equipment/tools/mining_tools.dm
## code/game/objects/effects/decals/cleanable.dm (a decal that never merges skips the walk of the tile's decals)
## code/game/objects/effects/effect_system/effects_other.dm
## code/game/objects/effects/effect_system/effects_smoke.dm
## code/game/objects/effects/portals.dm (tile engine neighbour cache, tile_engine.dm)
## code/game/objects/empulse.dm !Should be modularized. Can be done easily.
## code/game/objects/items.dm
## code/game/objects/items/crayons.dm
## code/game/objects/items/defib.dm
## code/game/objects/items/devices/flashlight.dm !Should be modularized. Can be done easily.
## code/game/objects/items/devices/radio/radio.dm
## code/game/objects/items/devices/scanners.dm (health analyser reports blast lung, explosion_realism/blast_injuries.dm)
## code/game/objects/items/robot/robot_items.dm
## code/game/objects/items/stacks/rods.dm
## code/game/objects/items/stacks/sheets/glass.dm
## code/game/objects/items/stacks/stack.dm
## code/game/objects/items/stunbaton.dm
## code/game/objects/items/tools/wirecutters.dm !Should be modularized. Can be done easily.
## code/game/objects/obj_defense.dm
## code/game/objects/structures/barsigns.dm
## code/game/objects/structures/grille.dm
## code/game/objects/structures/window.dm
## code/game/sound.dm (playsound_local() dulls everything while a blast has the ears ringing, explosion_realism/blast_senses.dm)
## code/game/turfs/change_turf.dm
## code/game/turfs/open.dm
## code/game/turfs/open/lava.dm (is_safe() by locate(), no copy of the tile's contents)
## code/game/turfs/open/space/space.dm (set_starlight() retints the camera pictures' starlight copies, map_view.dm; space put back at runtime tells the tile engine, tile_engine.dm)
## code/game/turfs/turf.dm (Enter() skips non-dense items; Exit() skips BYOND's built-in and asks only structures, doors and proximity fields)
## code/game/world.dm !Needs modularization! This stuff is crap.
## code/modules/admin/admin.dm
## code/modules/admin/admin_investigate.dm (investigate_log() writes through the log writer's thread)
## code/modules/admin/admin_ranks.dm
## code/modules/admin/admin_verbs.dm
## code/modules/admin/chat_commands.dm
## code/modules/admin/create_poll.dm
## code/modules/admin/ipintel.dm
## code/modules/admin/IsBanned.dm
## code/modules/admin/permissionedit.dm
## code/modules/admin/secrets.dm
## code/modules/admin/sql_ban_system.dm
## code/modules/admin/sql_message_system.dm
## code/modules/admin/stickyban.dm
## code/modules/admin/topic.dm
## code/modules/admin/verbs/adminhelp.dm (MessageNoRecipient() cleans its text: a follow-up ahelp reached admins' chat as HTML)
## code/modules/admin/verbs/beakerpanel.dm (a verb hands over to hippie's window: verbs run tg's definition)
## code/modules/admin/verbs/debug.dm (verbs hand over to hippie's windows: verbs run tg's definition)
## code/modules/admin/verbs/individual_logging.dm
## code/modules/admin/verbs/mapping.dm (verbs hand over to hippie's windows: verbs run tg's definition)
## code/modules/admin/verbs/one_click_antag.dm
## code/modules/admin/verbs/randomverbs.dm (a verb hands over to hippie's window: verbs run tg's definition)
## code/modules/antagonists/abductor/equipment/abduction_gear.dm
## code/modules/antagonists/changeling/powers/mutations.dm
## code/modules/antagonists/clockcult/clock_items/clockwork_armor.dm
## code/modules/antagonists/cult/blood_magic.dm
## code/modules/antagonists/morph/morph.dm
## code/modules/asset_cache/asset_list.dm
## code/modules/atmospherics/environmental/LINDA_fire.dm (hotspots tell the tile engine when it keeps LINDA's state, tile_engine.dm)
## code/modules/atmospherics/environmental/LINDA_system.dm (tile engine neighbour cache; shut doors' tiles pick their side, door_seals.dm)
## code/modules/atmospherics/environmental/LINDA_turf_tile.dm (a group's turfs skip the overlay update when nothing shows; update_visuals() makes no list for plain air)
## code/modules/atmospherics/machinery/atmosmachinery.dm
## code/modules/atmospherics/machinery/components/binary_devices/dp_vent_pump.dm (pipe air marked for the tile engine, pipe_engine.dm)
## code/modules/atmospherics/machinery/components/components_base.dm (update_parents() marks pipe air for the tile engine, pipe_engine.dm)
## code/modules/atmospherics/machinery/components/trinary_devices/mixer.dm (pipe air marked for the tile engine, pipe_engine.dm)
## code/modules/atmospherics/machinery/components/unary_devices/thermomachine.dm (pipe air marked for the tile engine, pipe_engine.dm)
## code/modules/atmospherics/machinery/components/unary_devices/vent_pump.dm
## code/modules/atmospherics/machinery/components/unary_devices/vent_scrubber.dm (idle when there's nothing to do; auto_use_power() looks the area up once)
## code/modules/atmospherics/machinery/datum_pipeline.dm (networks only processed when queued; reconcile_gases rewrite; the tile engine evens networks out, pipe_engine.dm)
## code/modules/atmospherics/machinery/pipes/pipes.dm (pipe air marked for the tile engine, pipe_engine.dm)
## code/modules/awaymissions/capture_the_flag.dm
## code/modules/awaymissions/corpse.dm
## code/modules/client/client_procs.dm
## code/modules/client/darkmode.dm
## code/modules/client/preferences.dm
## code/modules/client/preferences_savefile.dm
## code/modules/client/verbs/ooc.dm
## code/modules/clothing/clothing.dm
## code/modules/discord/tgs_commands.dm
## code/modules/error_handler/error_handler.dm (world/Error() tells Bot Shift, a code sweep and the round's runtime ledger of each runtime)
## code/modules/food_and_drinks/drinks/drinks.dm !Should be modularized. Can be done easily.
## code/modules/food_and_drinks/drinks/drinks/drinkingglass.dm
## code/modules/food_and_drinks/food/snacks_meat.dm (a monkey cube asks the monkey cap before a monkey is made)
## code/modules/holodeck/computer.dm (floorcheck() keeps the holodeck's turfs in a list instead of reading the area every 2 s)
## code/modules/hydroponics/grown/banana.dm !Should be modularized. Can be done easily.
## code/modules/integrated_electronics/subtypes/input.dm
## code/modules/integrated_electronics/subtypes/manipulation.dm
## code/modules/integrated_electronics/subtypes/smart.dm
## code/modules/jobs/job_exp.dm
## code/modules/keybindings/bindings_client.dm (keyDown() ignores a key already held: a held key could come in twice, through a tgui window and from the map)
## code/modules/keybindings/setup.dm
## code/modules/library/lib_machines.dm
## code/modules/library/random_books.dm
## code/modules/lighting/lighting_corner.dm (the tone curve in update_objects(): light past the knee eases toward full instead of being cut off at 1, see ~hippie_defines/lighting_tone.dm)
## code/modules/mapping/map_template.dm (tile engine neighbour cache, tile_engine.dm)
## code/modules/mapping/space_management/space_reservation.dm
## code/modules/mining/equipment/survival_pod.dm !Should be modularized. Can be done easily.
## code/modules/mob/dead/new_player/new_player.dm
## code/modules/mob/dead/new_player/poll.dm
## code/modules/mob/living/blood.dm
## code/modules/mob/living/brain/brain_item.dm
## code/modules/mob/living/carbon/alien/alien.dm !Should be modularized. Can be done easily.
## code/modules/mob/living/carbon/carbon.dm (throw_item() goes by plan_throw(): aim, strength and the toss, hippiestation/code/modules/throwing/throw_skill.dm)
## code/modules/mob/living/carbon/carbon_defense.dm
## code/modules/mob/living/carbon/death.dm !Should be modularized. Can be done easily.
## code/modules/mob/living/carbon/human/examine.dm
## code/modules/mob/living/carbon/human/human.dm !Should be modularized. Can be done easily.
## code/modules/mob/living/carbon/human/human_defense.dm
## code/modules/mob/living/carbon/human/say.dm
## code/modules/mob/living/carbon/human/species.dm
## code/modules/mob/living/carbon/human/species_types/jellypeople.dm
## code/modules/mob/living/carbon/human/species_types/shadowpeople.dm
## code/modules/mob/living/carbon/life.dm
## code/modules/mob/living/carbon/monkey/monkey.dm !Should be modularized. Can be done easily.
## code/modules/mob/living/carbon/update_icons.dm
## code/modules/mob/living/living.dm 
## code/modules/mob/living/living_defense.dm
## code/modules/mob/living/say.dm
## code/modules/mob/living/silicon/ai/ai.dm
## code/modules/mob/living/silicon/pai/pai_shell.dm
## code/modules/mob/living/silicon/robot/robot.dm
## code/modules/mob/living/simple_animal/bot/bot.dm (scan() shuffles and checks only what's of the type it's after; an EMP'd bot destroyed before it comes back on stays off)
## code/modules/mob/living/simple_animal/bot/ed209bot.dm
## code/modules/mob/living/simple_animal/bot/medbot.dm
## code/modules/mob/living/simple_animal/friendly/dog.dm
## code/modules/mob/living/simple_animal/hostile/headcrab.dm
## code/modules/mob/living/simple_animal/hostile/hostile.dm (GainPatience() on a mob being deleted; DestroyObjectsInDirection() looks only at dense machines and structures; FindHidden() with the target gone)
## code/modules/mob/living/simple_animal/hostile/jungle/leaper.dm
## code/modules/mob/living/simple_animal/hostile/megafauna/drake.dm (crush, fire line and lava fall spread a crowd over ticks)
## code/modules/mob/living/simple_animal/hostile/retaliate/retaliate.dm (keyed enemies, Retaliate() once a second, allies told only new enemies)
## code/modules/mob/living/simple_animal/slime/slime.dm
## code/modules/mob/mob.dm (visible_message() and audible_message() skip the search for hearers when no client is in range)
## code/modules/mob/mob_helpers.dm
## code/modules/mob/mob_movement.dm !Horrible code alert, how did this even get merged?
## code/modules/photography/camera/camera.dm (the tiles in sight as a keyed set)
## code/modules/photography/camera/camera_image_capturing.dm (top of a pile only; flat icons kept by appearance)
## code/modules/power/apc.dm (an outage tells the area once; a healthy APC skips its no-op autoset(), percent() and poweralert() calls)
## code/modules/power/turbine.dm (the console's power readout before the turbine first runs)
## code/modules/reagents/chem_splash.dm !Could probably be improved to avoid cutting out the whole tg proc
## code/modules/reagents/chemistry/holder.dm !Same as above.
## code/modules/reagents/chemistry/reagents/alcohol_reagents.dm
## code/modules/reagents/chemistry/reagents/food_reagents.dm
## code/modules/reagents/chemistry/reagents/other_reagents.dm
## code/modules/reagents/chemistry/reagents/pyrotechnic_reagents.dm (thermite isn't put on turfs its component refuses)
## code/modules/reagents/chemistry/reagents/toxin_reagents.dm
## code/modules/reagents/chemistry/recipes/pyrotechnics.dm !Same as above.
## code/modules/reagents/chemistry/recipes/slime_extracts.dm (delete_extract() on an extract already gone)
## code/modules/reagents/reagent_containers.dm !Could be modularized. (a thrown container that's caught doesn't splash the catcher)
## code/modules/research/rdconsole.dm (research_node() says which points are short)
## code/modules/shuttle/emergency.dm
## code/modules/spells/spell.dm
## code/modules/surgery/bodyparts/bodyparts.dm
## code/modules/surgery/bodyparts/head.dm
## code/modules/surgery/helpers.dm
## code/modules/surgery/organs/lungs.dm
## code/modules/surgery/organs/vocal_cords.dm
## code/modules/tgs/ (TGS DMAPI 7.4.0, the upstream files as released; was 5.2.7)
## code/modules/unit_tests/reagent_recipe_collisions.dm
