"""Sets each department window's theme in tgui-next routes.js. Windows that already have a theme keep it."""
import re

DEPTS = {
    'medical': '''chem_dispenser chemical_filter chem_heater chem_master chem_press reaction_chamber chem_splitter chem_synthesizer
        cloning_console cryo dna_console limb_grower medical_kiosk medical_records operating_computer pandemic sleeper autodoc
        chem_pressure chem_radioactive chem_bluespace chem_centrifuge chem_reagent_analysis chem_reagent_forge smoke_machine
        prototype_cloning crew acclimator''',
    'engineering': '''apc apc_control power_monitor smes solar_control gravity_generator particle_accelerator portable_generator
        thermoelectric_generator turbine_computer rcd_access blueprints airlock_electronics station_alert telecomms_logs
        telecomms_machine telecomms_monitor ntnet_relay magnet_controller sat_control computer_fabricator airlock_maker
        master_multitool''',
    'atmos': '''airalarm atmos_alert atmos_control atmos_filter atmos_mixer atmos_pump canister portable_pump portable_scrubber
        space_heater tanks tank_dispenser thermomachine pipe_dispenser rpd airlock_controller scrubber_pack''',
    'security': '''brig_timer gulag_console gulag_item_reclaimer labor_claim_console prisoner_console security_records gun_locker
        camera_console implantchair scanner_gate porta_turret turret_control implant_pad''',
    'science': '''rdconsole rd_fabricator exosuit_fabricator nanite_chamber_control nanite_cloud_control nanite_program_hub
        nanite_programmer nanite_remote doppler_array experiment_scanner experimentor research_dashboard robotics_console
        mecha_control circuit_assembly circuit_printer launchpad_console telescience transfer_valve analyzer_history ai_fixer
        intellicard cyborg_frame mech_bay_power_console''',
    'cargo': '''cargo cargo_express bounty_console ore_redemption_machine ore_silo smelter_console stacking_console mining_vendor
        mint coin_press destination_tagger mulebot mass_driver_console ore_box aux_base''',
    'command': '''comms_console id_console keycard_auth emergency_shuttle_console announcement_system bank_vault vault_controller
        bsa artillery_control message_monitor''',
    'silicon': '''silicon_laws silicon_alerts ai_bot_control ai_vox silicon_pda_log ai_airlock''',
    'service': '''biogenerator seed_extractor plant_dna_manipulator smartvend jukebox food_cart icecream_vat library_console
        library_scanner library_visitor book_reader photocopier holodeck jani_cart bible_style pool_controller''',
}

p = 'tgui-next/packages/tgui/routes.js'
s = open(p, newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'
changed = []
missing = []
for theme, keys in DEPTS.items():
    for key in keys.split():
        m = re.search(r'(\n  ' + key + r': \{)(.*?)(\n  \},)', s, re.S)
        if not m:
            missing.append(key)
            continue
        body = m.group(2)
        if 'theme:' in body:
            continue
        new = m.group(1) + body + nl + "    theme: '" + theme + "'," + m.group(3)
        s = s[:m.start()] + new + s[m.end():]
        changed.append(key)
open(p, 'w', newline='').write(s)
print('themed', len(changed), 'missing', missing)
