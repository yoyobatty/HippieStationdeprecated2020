# Differences with /tg/

The best practice to have while coding is to keep everything modularized, or the most possible. Sometimes, through,
 it's not possible and you're required to edit some files inside the code folder, which is /tg/'s code. This file is intended to have a list of the files changed.

# Sorted alphabetically filepath-wise.

## code/__DEFINES/diseases.dm
## code/__DEFINES/MC.dm
## code/__DEFINES/misc.dm
## code/__DEFINES/mobs.dm
## code/__DEFINES/role_preferences.dm
## code/__HELPERS/AStar.dm
## code/__HELPERS/icons.dm
## code/__HELPERS/mobs.dm
## code/__HELPERS/radiation.dm
## code/__HELPERS/roundend.dm
## code/__HELPERS/text.dm
## code/__HELPERS/unsorted.dm
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
## code/controllers/subsystem/input.dm
## code/controllers/subsystem/job.dm
## code/controllers/subsystem/mapping.dm
## code/controllers/subsystem/mobs.dm
## code/controllers/subsystem/stickyban.dm
## code/controllers/subsystem/throwing.dm
## code/controllers/subsystem/ticker.dm
## code/controllers/subsystem/timer.dm
## code/controllers/subsystem/vote.dm
## code/datums/datumvars.dm
## code/datums/diseases/\_MobProcs.dm
## code/datums/elements/atmos_sensitive.dm
## code/datums/hud.dm
## code/datums/progressbar.dm
## code/datums/status_effects/neutral.dm
## code/datums/status_effects/status_effect.dm
## code/datums/wires/airlock.dm
## code/game/gamemodes/changeling/changeling.dm !Should be modularized. Can be done easily.
## code/game/gamemodes/game_mode.dm
## code/game/gamemodes/traitor/traitor.dm !Should be modularized. Can be done easily.
## code/game/machinery/\_machinery.dm
## code/game/machinery/computer/cloning.dm
## code/game/machinery/computer/security.dm
## code/game/machinery/doors/airlock_types.dm !Should be modularized. Can be done easily.
## code/game/machinery/doors/brigdoors.dm
## code/game/machinery/telecomms/broadcasting.dm
## code/game/machinery/telecomms/telecomunications.dm
## code/game/objects/effects/effect_system/effects_other.dm
## code/game/objects/effects/effect_system/effects_smoke.dm
## code/game/objects/empulse.dm !Should be modularized. Can be done easily.
## code/game/objects/items.dm
## code/game/objects/items/crayons.dm
## code/game/objects/items/devices/flashlight.dm !Should be modularized. Can be done easily.
## code/game/objects/items/devices/radio/radio.dm
## code/game/objects/items/stacks/rods.dm
## code/game/objects/items/stacks/sheets/glass.dm
## code/game/objects/items/stacks/stack.dm
## code/game/objects/items/tools/wirecutters.dm !Should be modularized. Can be done easily.
## code/game/objects/obj_defense.dm
## code/game/objects/structures/grille.dm
## code/game/turfs/change_turf.dm
## code/game/turfs/open.dm
## code/game/world.dm !Needs modularization! This stuff is crap.
## code/modules/admin/admin.dm
## code/modules/admin/admin_ranks.dm
## code/modules/admin/admin_verbs.dm
## code/modules/admin/create_poll.dm
## code/modules/admin/ipintel.dm
## code/modules/admin/IsBanned.dm
## code/modules/admin/permissionedit.dm
## code/modules/admin/secrets.dm
## code/modules/admin/sql_ban_system.dm
## code/modules/admin/sql_message_system.dm
## code/modules/admin/stickyban.dm
## code/modules/admin/topic.dm
## code/modules/admin/verbs/individual_logging.dm
## code/modules/admin/verbs/one_click_antag.dm
## code/modules/antagonists/clockcult/clock_items/clockwork_armor.dm
## code/modules/antagonists/morph/morph.dm
## code/modules/asset_cache/asset_list.dm
## code/modules/atmospherics/machinery/atmosmachinery.dm
## code/modules/atmospherics/machinery/components/components_base.dm
## code/modules/awaymissions/capture_the_flag.dm
## code/modules/awaymissions/corpse.dm
## code/modules/client/client_procs.dm
## code/modules/client/darkmode.dm
## code/modules/client/preferences.dm
## code/modules/client/preferences_savefile.dm
## code/modules/client/verbs/ooc.dm
## code/modules/clothing/clothing.dm
## code/modules/food_and_drinks/drinks/drinks.dm !Should be modularized. Can be done easily.
## code/modules/food_and_drinks/drinks/drinks/drinkingglass.dm
## code/modules/hydroponics/grown/banana.dm !Should be modularized. Can be done easily.
## code/modules/integrated_electronics/subtypes/input.dm
## code/modules/integrated_electronics/subtypes/manipulation.dm
## code/modules/integrated_electronics/subtypes/smart.dm
## code/modules/jobs/job_exp.dm
## code/modules/keybindings/bindings_client.dm
## code/modules/keybindings/setup.dm
## code/modules/library/lib_machines.dm
## code/modules/library/random_books.dm
## code/modules/mapping/space_management/space_reservation.dm
## code/modules/mining/equipment/survival_pod.dm !Should be modularized. Can be done easily.
## code/modules/mob/dead/new_player/new_player.dm
## code/modules/mob/dead/new_player/poll.dm
## code/modules/mob/living/carbon/alien/alien.dm !Should be modularized. Can be done easily.
## code/modules/mob/living/carbon/carbon_defense.dm
## code/modules/mob/living/carbon/death.dm !Should be modularized. Can be done easily.
## code/modules/mob/living/carbon/human/examine.dm
## code/modules/mob/living/carbon/human/human.dm !Should be modularized. Can be done easily.
## code/modules/mob/living/carbon/human/human_defense.dm
## code/modules/mob/living/carbon/human/say.dm
## code/modules/mob/living/carbon/human/species.dm
## code/modules/mob/living/carbon/human/species_types/jellypeople.dm
## code/modules/mob/living/carbon/life.dm
## code/modules/mob/living/carbon/monkey/monkey.dm !Should be modularized. Can be done easily.
## code/modules/mob/living/carbon/update_icons.dm
## code/modules/mob/living/living.dm 
## code/modules/mob/living/say.dm
## code/modules/mob/living/silicon/ai/ai.dm
## code/modules/mob/living/silicon/pai/pai_shell.dm
## code/modules/mob/living/silicon/robot/robot.dm
## code/modules/mob/living/simple_animal/bot/ed209bot.dm
## code/modules/mob/living/simple_animal/bot/medbot.dm
## code/modules/mob/living/simple_animal/friendly/dog.dm
## code/modules/mob/living/simple_animal/hostile/headcrab.dm
## code/modules/mob/living/simple_animal/slime/slime.dm
## code/modules/mob/mob_helpers.dm
## code/modules/mob/mob_movement.dm !Horrible code alert, how did this even get merged?
## code/modules/photography/camera/camera_image_capturing.dm
## code/modules/reagents/chem_splash.dm !Could probably be improved to avoid cutting out the whole tg proc
## code/modules/reagents/chemistry/holder.dm !Same as above.
## code/modules/reagents/chemistry/reagents/food_reagents.dm
## code/modules/reagents/chemistry/reagents/other_reagents.dm
## code/modules/reagents/chemistry/reagents/toxin_reagents.dm
## code/modules/reagents/chemistry/recipes/pyrotechnics.dm !Same as above.
## code/modules/reagents/reagent_containers.dm !Could be modularized.
## code/modules/shuttle/emergency.dm
## code/modules/spells/spell.dm
## code/modules/surgery/bodyparts/bodyparts.dm
## code/modules/surgery/bodyparts/head.dm
## code/modules/surgery/helpers.dm
## code/modules/surgery/organs/lungs.dm
## code/modules/surgery/organs/vocal_cords.dm
## code/modules/unit_tests/reagent_recipe_collisions.dm
