import { Achievements } from './interfaces/Achievements';
import { AiAirlock } from './interfaces/AiAirlock';
import { AirAlarm } from './interfaces/AirAlarm';
import { AirlockElectronics } from './interfaces/AirlockElectronics';
import { Apc } from './interfaces/Apc';
import { ApcControl } from './interfaces/ApcControl';
import { Assembly } from './interfaces/Assembly';
import { AtmosAlertConsole } from './interfaces/AtmosAlertConsole';
import { AtmosControlConsole } from './interfaces/AtmosControlConsole';
import { AtmosFilter } from './interfaces/AtmosFilter';
import { AtmosMixer } from './interfaces/AtmosMixer';
import { AtmosPump } from './interfaces/AtmosPump';
import { Biogenerator } from './interfaces/Biogenerator';
import { BluespaceArtillery } from './interfaces/BluespaceArtillery';
import { BorgPanel } from './interfaces/BorgPanel';
import { BrigTimer } from './interfaces/BrigTimer';
import { Canister } from './interfaces/Canister';
import { Cargo, CargoExpress } from './interfaces/Cargo';
import { CellularEmporium } from './interfaces/CellularEmporium';
import { CentcomPodLauncher } from './interfaces/CentcomPodLauncher';
import { ChemAcclimator } from './interfaces/ChemAcclimator';
import { ChemDebugSynthesizer } from './interfaces/ChemDebugSynthesizer';
import { ChemDispenser } from './interfaces/ChemDispenser';
import { ChemFilter } from './interfaces/ChemFilter';
import { ChemHeater } from './interfaces/ChemHeater';
import { ChemMaster } from './interfaces/ChemMaster';
import { ChemPress } from './interfaces/ChemPress';
import { ChemReactionChamber } from './interfaces/ChemReactionChamber';
import { ChemSplitter } from './interfaces/ChemSplitter';
import { ChemSynthesizer } from './interfaces/ChemSynthesizer';
import { CodexGigas } from './interfaces/CodexGigas';
import { ComputerFabricator } from './interfaces/ComputerFabricator';
import { CloningConsole } from './interfaces/CloningConsole';
import { CommsConsole } from './interfaces/CommsConsole';
import { Crayon } from './interfaces/Crayon';
import { CrewConsole } from './interfaces/CrewConsole';
import { Cryo } from './interfaces/Cryo';
import { DisposalUnit } from './interfaces/DisposalUnit';
import { DnaConsole } from './interfaces/DnaConsole';
import { DnaVault } from './interfaces/DnaVault';
import { EngravedMessage } from './interfaces/EngravedMessage';
import { Exosuit } from './interfaces/Exosuit';
import { ExosuitFabricator } from './interfaces/ExosuitFabricator';
import { DestinationTagger, HandTeleporter, ImplantPad, Safe, SecureStorage } from './interfaces/Gadgets';
import { Gps } from './interfaces/Gps';
import { GravityGenerator } from './interfaces/GravityGenerator';
import { GulagItemReclaimer } from './interfaces/GulagItemReclaimer';
import { Holodeck } from './interfaces/Holodeck';
import { IdConsole } from './interfaces/IdConsole';
import { ImplantChair } from './interfaces/ImplantChair';
import { KeycardAuth } from './interfaces/KeycardAuth';
import { LanguageMenu } from './interfaces/LanguageMenu';
import { LibraryConsole, LibraryScanner, LibraryVisitor } from './interfaces/Library';
import { MechBayPowerConsole } from './interfaces/MechBayPowerConsole';
import { MechaControl } from './interfaces/MechaControl';
import { MedicalKiosk } from './interfaces/MedicalKiosk';
import { MessageMonitor } from './interfaces/MessageMonitor';
import { MiningVendor } from './interfaces/MiningVendor';
import { Newscaster } from './interfaces/Newscaster';
import { Paper } from './interfaces/Paper';
import { PaperList } from './interfaces/PaperList';
import { ParticleAccelerator } from './interfaces/ParticleAccelerator';
import { Pda } from './interfaces/Pda';
import { Photocopier } from './interfaces/Photocopier';
import { PipeDispenser } from './interfaces/PipeDispenser';
import { PlantDnaManipulator } from './interfaces/PlantDnaManipulator';
import { MedicalRecords, SecurityRecords } from './interfaces/RecordsConsole';
import { Mint } from './interfaces/Mint';
import { NaniteChamberControl } from './interfaces/NaniteChamberControl';
import { NaniteCloudControl } from './interfaces/NaniteCloudControl';
import { NaniteProgramHub } from './interfaces/NaniteProgramHub';
import { NaniteProgrammer } from './interfaces/NaniteProgrammer';
import { NaniteRemote } from './interfaces/NaniteRemote';
import { NtosArcade } from './interfaces/NtosArcade';
import { NtosMain } from './interfaces/NtosMain';
import { NtosNetDownloader } from './interfaces/NtosNetDownloader';
import { NtosSupermatterMonitor } from './interfaces/NtosSupermatterMonitor';
import { NtosWrapper } from './interfaces/NtosWrapper';
import { NuclearBomb } from './interfaces/NuclearBomb';
import { OperatingComputer } from './interfaces/OperatingComputer';
import { OreBox } from './interfaces/OreBox';
import { OreRedemptionMachine } from './interfaces/OreRedemptionMachine';
import { Pandemic } from './interfaces/Pandemic';
import { PersonalCrafting } from './interfaces/PersonalCrafting';
import { PortableGenerator } from './interfaces/PortableGenerator';
import { PortablePump, PortableScrubber } from './interfaces/PortableAtmos';
import { PowerMonitor } from './interfaces/PowerMonitor';
import { Radio } from './interfaces/Radio';
import { RapidPipeDispenser } from './interfaces/RapidPipeDispenser';
import { RequestsConsole } from './interfaces/RequestsConsole';
import { RoboticsConsole } from './interfaces/RoboticsConsole';
import { SatelliteControl } from './interfaces/SatelliteControl';
import { ScannerGate } from './interfaces/ScannerGate';
import { ShuttleManipulator } from './interfaces/ShuttleManipulator';
import { SmartVend } from './interfaces/SmartVend';
import { Smes } from './interfaces/Smes';
import { SmokeMachine } from './interfaces/SmokeMachine';
import { SolarControl } from './interfaces/SolarControl';
import { SpaceHeater } from './interfaces/SpaceHeater';
import { SpawnersMenu } from './interfaces/SpawnersMenu';
import { StackCrafting } from './interfaces/StackCrafting';
import { StationAlertConsole } from './interfaces/StationAlertConsole';
import { StripMenu } from './interfaces/StripMenu';
import { SuitStorageUnit } from './interfaces/SuitStorageUnit';
import { Tank } from './interfaces/Tank';
import { TankDispenser } from './interfaces/TankDispenser';
import { TelecommsLogs } from './interfaces/TelecommsLogs';
import { TelecommsMachine } from './interfaces/TelecommsMachine';
import { TelecommsMonitor } from './interfaces/TelecommsMonitor';
import { ThermoMachine } from './interfaces/ThermoMachine';
import { ThermoelectricGenerator } from './interfaces/ThermoelectricGenerator';
import { TurbineComputer } from './interfaces/TurbineComputer';
import { Uplink } from './interfaces/Uplink';
import { VaultController } from './interfaces/VaultController';
import { Wires } from './interfaces/Wires';
// hippie start
import { Guardian } from './interfaces/Guardian';
import { Vending } from './interfaces/Vending';
import { Pool } from './interfaces/Pool';
import { ScrubberPack } from './interfaces/ScrubberPack';
import { MasterMultitool } from './interfaces/MasterMultitool';
import { Orbit } from './interfaces/Orbit';
import { DisplaySettings } from './interfaces/DisplaySettings';
import { RdConsole, RdFabricator } from './interfaces/RdConsole';
import { Sleeper } from './interfaces/Sleeper';
import { Autodoc } from './interfaces/Autodoc';
import { Mule } from './interfaces/Mule';
import { EmergencyShuttleConsole } from './interfaces/EmergencyShuttleConsole';
import { LaunchpadConsole, LaunchpadRemote } from './interfaces/Launchpad';
import { GulagConsole, LaborClaimConsole } from './interfaces/LaborCamp';
import { Intellicard, NtosAiRestorer } from './interfaces/AiCard';
import { Eightball, NotificationPanel, SlimeBodySwapper } from './interfaces/GhostAndSlime';
import { ChemBluespace, ChemCentrifuge, ChemPressure, ChemRadioactive, MaterialAnalyser, ReagentForge } from './interfaces/ChemLab';
import { ClockworkSlab } from './interfaces/ClockworkSlab';
import { CameraConsole } from './interfaces/CameraConsole';
import { Preferences } from './interfaces/Preferences';
import { Teleporter } from './interfaces/Teleporter';
import { ArcadeBattle, ArcadeMinesweeper, ArcadeOrion } from './interfaces/Arcade';
import { PortableTurret, TurretControl } from './interfaces/Turrets';
import { Experimentor, RdServerControl } from './interfaces/ResearchMachines';
import { FoodCart, IcecreamVat, MagnetController, StackingConsole } from './interfaces/MiscMachines';
import { NtosCard } from './interfaces/NtosCard';
import { NtnetRelay, NtosConfiguration, NtosFileManager, NtosNetChat, NtosNetDos, NtosNetMonitor, NtosNetTransfer, NtosRevelation, SyndContract } from './interfaces/NtosPrograms';
import { AuxBase, BountyConsole, CoinPress, OreSilo, SmelterConsole } from './interfaces/CargoMining';
import { MassDriverConsole, ShuttleConsole } from './interfaces/ShuttleConsole';
import { AirlockController, BankVault, Holopad, Jukebox, LimbGrower, NavBeacon, SeedExtractor, SlotMachine } from './interfaces/ServiceMachines';
import { AiFixer, AnnouncementSystem, DopplerArray, PrisonerConsole } from './interfaces/SecurityScience';
import { NtosTrafficControl } from './interfaces/NtosTrafficControl';
import { GunLocker, JaniCart } from './interfaces/Storage';
import { CyborgFrame, TransferValve } from './interfaces/Items';
import { SongEditor } from './interfaces/SongEditor';
import { Blueprints, CameraBug, RcdAccess } from './interfaces/Tools';
import { BibleStyle, BookReader, MimeBook, PhotoViewer } from './interfaces/Books';
import { MechSleeper, MechSyringeGun, PaiCard } from './interfaces/MechMedicalPai';
import { ExperimentScanner } from './interfaces/Experiments';
import { LateJoin, Lobby } from './interfaces/Lobby';
import { RoundEnd } from './interfaces/RoundEnd';
// hippie end

const ROUTES = {
  achievements: {
    component: () => Achievements,
    scrollable: true,
  },
  ai_airlock: {
    component: () => AiAirlock,
    scrollable: false,
  },
  ai_fixer: {
    component: () => AiFixer,
    scrollable: true,
  },
  airalarm: {
    component: () => AirAlarm,
    scrollable: true,
  },
  airlock_controller: {
    component: () => AirlockController,
    scrollable: true,
  },
  airlock_electronics: {
    component: () => AirlockElectronics,
    scrollable: false,
  },
  announcement_system: {
    component: () => AnnouncementSystem,
    scrollable: true,
  },
  apc: {
    component: () => Apc,
    scrollable: false,
  },
  apc_control: {
    component: () => ApcControl,
    scrollable: true,
  },
  assembly: {
    component: () => Assembly,
    scrollable: false,
  },
  atmos_alert: {
    component: () => AtmosAlertConsole,
    scrollable: true,
  },
  atmos_control: {
    component: () => AtmosControlConsole,
    scrollable: true,
  },
  atmos_filter: {
    component: () => AtmosFilter,
    scrollable: false,
  },
  atmos_mixer: {
    component: () => AtmosMixer,
    scrollable: false,
  },
  atmos_pump: {
    component: () => AtmosPump,
    scrollable: false,
  },
  aux_base: {
    component: () => AuxBase,
    scrollable: true,
  },
  bank_vault: {
    component: () => BankVault,
    scrollable: true,
  },
  bible_style: {
    component: () => BibleStyle,
    scrollable: true,
  },
  biogenerator: {
    component: () => Biogenerator,
    scrollable: true,
  },
  blueprints: {
    component: () => Blueprints,
    scrollable: true,
  },
  book_reader: {
    component: () => BookReader,
    scrollable: true,
  },
  borgopanel: {
    component: () => BorgPanel,
    scrollable: true,
  },
  bounty_console: {
    component: () => BountyConsole,
    scrollable: true,
  },
  brig_timer: {
    component: () => BrigTimer,
    scrollable: false,
  },
  bsa: {
    component: () => BluespaceArtillery,
    scrollable: false,
  },
  camera_bug: {
    component: () => CameraBug,
    scrollable: true,
  },
  canister: {
    component: () => Canister,
    scrollable: false,
  },
  cargo: {
    component: () => Cargo,
    scrollable: true,
  },
  cargo_express: {
    component: () => CargoExpress,
    scrollable: true,
  },
  cellular_emporium: {
    component: () => CellularEmporium,
    scrollable: true,
  },
  centcom_podlauncher: {
    component: () => CentcomPodLauncher,
    scrollable: false,
  },
  acclimator: {
    component: () => ChemAcclimator,
    scrollable: false,
  },
  chem_dispenser: {
    component: () => ChemDispenser,
    scrollable: true,
  },
  chemical_filter: {
    component: () => ChemFilter,
    scrollable: true,
  },
  chem_heater: {
    component: () => ChemHeater,
    scrollable: true,
  },
  chem_master: {
    component: () => ChemMaster,
    scrollable: true,
  },
  chem_press: {
    component: () => ChemPress,
    scrollable: false,
  },
  coin_press: {
    component: () => CoinPress,
    scrollable: true,
  },
  cyborg_frame: {
    component: () => CyborgFrame,
    scrollable: true,
  },
  destination_tagger: {
    component: () => DestinationTagger,
    scrollable: false,
  },
  dna_console: {
    component: () => DnaConsole,
    scrollable: true,
  },
  doppler_array: {
    component: () => DopplerArray,
    scrollable: true,
  },
  exosuit: {
    component: () => Exosuit,
    scrollable: true,
    theme: 'mecha',
  },
  exosuit_fabricator: {
    component: () => ExosuitFabricator,
    scrollable: false,
  },
  experiment_scanner: {
    component: () => ExperimentScanner,
    scrollable: true,
  },
  gun_locker: {
    component: () => GunLocker,
    scrollable: true,
  },
  hand_teleporter: {
    component: () => HandTeleporter,
    scrollable: true,
  },
  holopad: {
    component: () => Holopad,
    scrollable: true,
  },
  implant_pad: {
    component: () => ImplantPad,
    scrollable: true,
  },
  jani_cart: {
    component: () => JaniCart,
    scrollable: true,
  },
  jukebox: {
    component: () => Jukebox,
    scrollable: true,
  },
  late_join: {
    component: () => LateJoin,
    scrollable: false,
  },
  library_console: {
    component: () => LibraryConsole,
    scrollable: true,
  },
  library_scanner: {
    component: () => LibraryScanner,
    scrollable: false,
  },
  library_visitor: {
    component: () => LibraryVisitor,
    scrollable: true,
  },
  limb_grower: {
    component: () => LimbGrower,
    scrollable: true,
  },
  lobby: {
    component: () => Lobby,
    scrollable: false,
  },
  mass_driver_console: {
    component: () => MassDriverConsole,
    scrollable: true,
  },
  mech_sleeper: {
    component: () => MechSleeper,
    scrollable: true,
  },
  mech_syringe_gun: {
    component: () => MechSyringeGun,
    scrollable: true,
  },
  mecha_control: {
    component: () => MechaControl,
    scrollable: true,
  },
  message_monitor: {
    component: () => MessageMonitor,
    scrollable: true,
  },
  mime_book: {
    component: () => MimeBook,
    scrollable: true,
  },
  mining_vendor: {
    component: () => MiningVendor,
    scrollable: true,
  },
  nav_beacon: {
    component: () => NavBeacon,
    scrollable: true,
  },
  newscaster: {
    component: () => Newscaster,
    scrollable: true,
  },
  ore_silo: {
    component: () => OreSilo,
    scrollable: true,
  },
  pai_card: {
    component: () => PaiCard,
    scrollable: true,
  },
  paper: {
    component: () => Paper,
    scrollable: true,
  },
  paper_list: {
    component: () => PaperList,
    scrollable: true,
  },
  particle_accelerator: {
    component: () => ParticleAccelerator,
    scrollable: false,
  },
  pda: {
    component: () => Pda,
    scrollable: false,
  },
  photo_viewer: {
    component: () => PhotoViewer,
    scrollable: true,
  },
  photocopier: {
    component: () => Photocopier,
    scrollable: false,
  },
  pipe_dispenser: {
    component: () => PipeDispenser,
    scrollable: true,
  },
  plant_dna_manipulator: {
    component: () => PlantDnaManipulator,
    scrollable: true,
  },
  prisoner_console: {
    component: () => PrisonerConsole,
    scrollable: true,
  },
  rcd_access: {
    component: () => RcdAccess,
    scrollable: true,
  },
  reaction_chamber: {
    component: () => ChemReactionChamber,
    scrollable: true,
  },
  chem_splitter: {
    component: () => ChemSplitter,
    scrollable: false,
  },
  chem_synthesizer: {
    component: () => ChemDebugSynthesizer,
    scrollable: false,
  },
  requests_console: {
    component: () => RequestsConsole,
    scrollable: true,
  },
  robotics_console: {
    component: () => RoboticsConsole,
    scrollable: true,
  },
  roundend_report: {
    component: () => RoundEnd,
    scrollable: false,
  },
  safe: {
    component: () => Safe,
    scrollable: true,
  },
  secure_storage: {
    component: () => SecureStorage,
    scrollable: false,
  },
  security_records: {
    component: () => SecurityRecords,
    scrollable: false,
  },
  seed_extractor: {
    component: () => SeedExtractor,
    scrollable: true,
  },
  shuttle_console: {
    component: () => ShuttleConsole,
    scrollable: true,
  },
  slot_machine: {
    component: () => SlotMachine,
    scrollable: true,
  },
  smelter_console: {
    component: () => SmelterConsole,
    scrollable: true,
  },
  song_editor: {
    component: () => SongEditor,
    scrollable: true,
  },
  stack_crafting: {
    component: () => StackCrafting,
    scrollable: true,
  },
  strip_menu: {
    component: () => StripMenu,
    scrollable: true,
  },
  synthesizer: {
    component: () => ChemSynthesizer,
    scrollable: false,
  },
  codex_gigas: {
    component: () => CodexGigas,
    scrollable: false,
  },
  computer_fabricator: {
    component: () => ComputerFabricator,
    scrollable: false,
  },
  cloning_console: {
    component: () => CloningConsole,
    scrollable: true,
  },
  comms_console: {
    component: () => CommsConsole,
    scrollable: true,
  },
  crayon: {
    component: () => Crayon,
    scrollable: true,
  },
  crew: {
    component: () => CrewConsole,
    scrollable: true,
  },
  cryo: {
    component: () => Cryo,
    scrollable: false,
  },
  disposal_unit: {
    component: () => DisposalUnit,
    scrollable: false,
  },
  dna_vault: {
    component: () => DnaVault,
    scrollable: false,
  },
  engraved_message: {
    component: () => EngravedMessage,
    scrollable: false,
  },
  gps: {
    component: () => Gps,
    scrollable: true,
  },
  gravity_generator: {
    component: () => GravityGenerator,
    scrollable: false,
  },
  gulag_item_reclaimer: {
    component: () => GulagItemReclaimer,
    scrollable: true,
  },
  holodeck: {
    component: () => Holodeck,
    scrollable: true,
  },
  id_console: {
    component: () => IdConsole,
    scrollable: true,
  },
  implantchair: {
    component: () => ImplantChair,
    scrollable: false,
  },
  keycard_auth: {
    component: () => KeycardAuth,
    scrollable: false,
  },
  language_menu: {
    component: () => LanguageMenu,
    scrollable: true,
  },
  mech_bay_power_console: {
    component: () => MechBayPowerConsole,
    scrollable: false,
  },
  medical_kiosk: {
    component: () => MedicalKiosk,
    scrollable: false,
  },
  medical_records: {
    component: () => MedicalRecords,
    scrollable: false,
  },
  mint: {
    component: () => Mint,
    scrollable: false,
  },
  nanite_chamber_control: {
    component: () => NaniteChamberControl,
    scrollable: true,
  },
  nanite_cloud_control: {
    component: () => NaniteCloudControl,
    scrollable: true,
  },
  nanite_program_hub: {
    component: () => NaniteProgramHub,
    scrollable: true,
  },
  nanite_programmer: {
    component: () => NaniteProgrammer,
    scrollable: true,
  },
  nanite_remote: {
    component: () => NaniteRemote,
    scrollable: true,
  },
  ntos_main: {
    component: () => NtosMain,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  ntos_net_downloader: {
    component: () => NtosNetDownloader,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  ntos_traffic_control: {
    component: () => NtosTrafficControl,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  ntos_power_monitor: {
    component: () => PowerMonitor,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  ntos_supermatter_monitor: {
    component: () => NtosSupermatterMonitor,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  nuclear_bomb: {
    component: () => NuclearBomb,
    scrollable: false,
    theme: 'retro',
  },
  ore_redemption_machine: {
    component: () => OreRedemptionMachine,
    scrollable: true,
  },
  ore_box: {
    component: () => OreBox,
    scrollable: true,
  },
  operating_computer: {
    component: () => OperatingComputer,
    scrollable: true,
  },
  pandemic: {
    component: () => Pandemic,
    scrollable: true,
  },
  personal_crafting: {
    component: () => PersonalCrafting,
    scrollable: false,
  },
  portable_generator: {
    component: () => PortableGenerator,
    scrollable: false,
  },
  portable_pump: {
    component: () => PortablePump,
    scrollable: false,
  },
  portable_scrubber: {
    component: () => PortableScrubber,
    scrollable: false,
  },
  power_monitor: {
    component: () => PowerMonitor,
    scrollable: true,
  },
  radio: {
    component: () => Radio,
    scrollable: false,
  },
  rpd: {
    component: () => RapidPipeDispenser,
    scrollable: true,
  },
  sat_control: {
    component: () => SatelliteControl,
    scrollable: false,
  },
  scanner_gate: {
    component: () => ScannerGate,
    scrollable: true,
  },
  shuttle_manipulator: {
    component: () => ShuttleManipulator,
    scrollable: true,
  },
  smartvend: {
    component: () => SmartVend,
    scrollable: true,
  },
  smes: {
    component: () => Smes,
    scrollable: false,
  },
  smoke_machine: {
    component: () => SmokeMachine,
    scrollable: false,
  },
  solar_control: {
    component: () => SolarControl,
    scrollable: false,
  },
  space_heater: {
    component: () => SpaceHeater,
    scrollable: false,
  },
  spawners_menu: {
    component: () => SpawnersMenu,
    scrollable: true,
  },
  station_alert: {
    component: () => StationAlertConsole,
    scrollable: true,
  },
  suit_storage_unit: {
    component: () => SuitStorageUnit,
    scrollable: false,
  },
  tanks: {
    component: () => Tank,
    scrollable: false,
  },
  tank_dispenser: {
    component: () => TankDispenser,
    scrollable: false,
  },
  telecomms_logs: {
    component: () => TelecommsLogs,
    scrollable: true,
  },
  telecomms_machine: {
    component: () => TelecommsMachine,
    scrollable: true,
  },
  telecomms_monitor: {
    component: () => TelecommsMonitor,
    scrollable: true,
  },
  thermoelectric_generator: {
    component: () => ThermoelectricGenerator,
    scrollable: false,
  },
  thermomachine: {
    component: () => ThermoMachine,
    scrollable: false,
  },
  transfer_valve: {
    component: () => TransferValve,
    scrollable: true,
  },
  turbine_computer: {
    component: () => TurbineComputer,
    scrollable: false,
  },
  uplink: {
    component: () => Uplink,
    scrollable: true,
    theme: 'syndicate',
  },
  vault_controller: {
    component: () => VaultController,
    scrollable: false,
  },
  wires: {
    component: () => Wires,
    scrollable: false,
  },
  // hippie start
  guardian: {
    component: () => Guardian,
    scrollable: true,
  },
  vending: {
    component: () => Vending,
    scrollable: true,
  },
  pool_controller: {
    component: () => Pool,
    scrollable: false,
  },
  display_settings: {
    component: () => DisplaySettings,
    scrollable: false,
  },
  scrubber_pack: {
    component: () => ScrubberPack,
    scrollable: true,
  },
  master_multitool: {
    component: () => MasterMultitool,
    scrollable: true,
  },
  orbit: {
    component: () => Orbit,
    scrollable: true,
  },
  rdconsole: {
    component: () => RdConsole,
    scrollable: false,
  },
  rd_fabricator: {
    component: () => RdFabricator,
    scrollable: false,
  },
  sleeper: {
    component: () => Sleeper,
    scrollable: true,
  },
  autodoc: {
    component: () => Autodoc,
    scrollable: true,
  },
  mulebot: {
    component: () => Mule,
    scrollable: true,
  },
  emergency_shuttle_console: {
    component: () => EmergencyShuttleConsole,
    scrollable: true,
  },
  launchpad_console: {
    component: () => LaunchpadConsole,
    scrollable: true,
  },
  launchpad_remote: {
    component: () => LaunchpadRemote,
    scrollable: true,
    theme: 'syndicate',
  },
  gulag_console: {
    component: () => GulagConsole,
    scrollable: true,
  },
  labor_claim_console: {
    component: () => LaborClaimConsole,
    scrollable: true,
  },
  intellicard: {
    component: () => Intellicard,
    scrollable: true,
  },
  ntos_ai_restorer: {
    component: () => NtosAiRestorer,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  notificationpanel: {
    component: () => NotificationPanel,
    scrollable: true,
  },
  eightball: {
    component: () => Eightball,
    scrollable: true,
  },
  slime_swap_body: {
    component: () => SlimeBodySwapper,
    scrollable: true,
  },
  ntnet_relay: {
    component: () => NtnetRelay,
    scrollable: true,
  },
  chem_pressure: {
    component: () => ChemPressure,
    scrollable: true,
  },
  chem_radioactive: {
    component: () => ChemRadioactive,
    scrollable: true,
  },
  chem_bluespace: {
    component: () => ChemBluespace,
    scrollable: true,
  },
  chem_centrifuge: {
    component: () => ChemCentrifuge,
    scrollable: true,
  },
  chem_reagent_analysis: {
    component: () => MaterialAnalyser,
    scrollable: true,
  },
  chem_reagent_forge: {
    component: () => ReagentForge,
    scrollable: true,
  },
  clockwork_slab: {
    component: () => ClockworkSlab,
    scrollable: true,
    theme: 'clockwork',
  },
  ntos_card: {
    component: () => NtosCard,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  ntos_configuration: {
    component: () => NtosConfiguration,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  ntos_file_manager: {
    component: () => NtosFileManager,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  ntos_net_chat: {
    component: () => NtosNetChat,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  ntos_net_monitor: {
    component: () => NtosNetMonitor,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  ntos_net_transfer: {
    component: () => NtosNetTransfer,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  ntos_station_alert: {
    component: () => StationAlertConsole,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  ntos_net_dos: {
    component: () => NtosNetDos,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'syndicate',
  },
  ntos_revelation: {
    component: () => NtosRevelation,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'syndicate',
  },
  arcade_minesweeper: {
    component: () => ArcadeMinesweeper,
    scrollable: true,
  },
  porta_turret: {
    component: () => PortableTurret,
    scrollable: true,
  },
  turret_control: {
    component: () => TurretControl,
    scrollable: true,
  },
  rd_server_control: {
    component: () => RdServerControl,
    scrollable: true,
  },
  experimentor: {
    component: () => Experimentor,
    scrollable: true,
  },
  magnet_controller: {
    component: () => MagnetController,
    scrollable: true,
  },
  stacking_console: {
    component: () => StackingConsole,
    scrollable: true,
  },
  food_cart: {
    component: () => FoodCart,
    scrollable: true,
  },
  icecream_vat: {
    component: () => IcecreamVat,
    scrollable: true,
  },
  arcade_orion: {
    component: () => ArcadeOrion,
    scrollable: true,
  },
  arcade_battle: {
    component: () => ArcadeBattle,
    scrollable: false,
  },
  teleporter: {
    component: () => Teleporter,
    scrollable: true,
  },
  preferences: {
    component: () => Preferences,
    scrollable: false,
  },
  camera_console: {
    component: () => CameraConsole,
    scrollable: false,
  },
  synd_contract: {
    component: () => SyndContract,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'syndicate',
  },
  // hippie end
};

export const getRoute = state => {
  if (process.env.NODE_ENV !== 'production') {
    // Show a kitchen sink
    if (state.showKitchenSink) {
      const { KitchenSink } = require('./interfaces/KitchenSink');
      return {
        component: () => KitchenSink,
        scrollable: true,
      };
    }
  }
  // Refer to the routing table
  return ROUTES[state.config && state.config.interface];
};
