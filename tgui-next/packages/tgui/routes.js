import { AbductorConsole, AbductorExperiment, GlandDispenser } from './interfaces/Abductor';
import { Achievements } from './interfaces/Achievements';
import { AdminAlerts } from './interfaces/AdminAlerts';
import { AdminFind } from './interfaces/AdminFind';
import { DebugCounts } from './interfaces/DebugCounts';
import { DebugProfiler } from './interfaces/DebugProfiler';
import { AdminBeakers, AdminDynamic, AdminEvents, AdminSoundEmitter } from './interfaces/AdminFun';
import { AdminHub } from './interfaces/AdminHub';
import { AdminIndividualLog, AdminInvestigate, AdminLogFiles, AdminPlaytime, AdminSdqlResults, AdminUpgradeReport, PlayerPlaytime } from './interfaces/AdminLogs';
import { RoundStatus, TeamListing, TraitorPanel } from './interfaces/AdminPages';
import { AdminGamePanel, AdminOneClickAntag, AdminPlayers, AdminStationGoals } from './interfaces/AdminPanels';
import { AdminPlayerPanel } from './interfaces/AdminPlayerPanel';
import { AdminEditLog, AdminPermissions, AdminRelatedAccounts, PlayerNotes } from './interfaces/AdminRecords';
import { AdminDelLog, AdminReport } from './interfaces/AdminReports';
import { AdminList, AdminSecrets } from './interfaces/AdminSecrets';
import { AdminSpawner, JobSlots, OutfitEditor, OutfitManager } from './interfaces/AdminTools';
import { AntagTips, ApprenticeContract, ArcaneTome, GangTool, MalfModules, PiratePad, RadLaser, TeleportScroll } from './interfaces/AntagWindows';
import { BotPanel } from './interfaces/BotPanel';
import { CrewManifest } from './interfaces/CrewManifest';
import { GriefUndo } from './interfaces/GriefUndo';
import { StationLooks } from './interfaces/StationLooks';
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
import { BanWindow } from './interfaces/BanWindow';
import { Biogenerator } from './interfaces/Biogenerator';
import { BluespaceArtillery } from './interfaces/BluespaceArtillery';
import { BorgPanel } from './interfaces/BorgPanel';
import { BotCrew } from './interfaces/BotCrew';
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
import { GameMenu } from './interfaces/GameMenu';
import { CardHand, Locator, Newspaper, Valentine } from './interfaces/ItemsReading';
import { AnalyzerHistory, ArtilleryControl, ExosuitMaint, PrototypeCloning, Telescience } from './interfaces/MachinesMore';
import { MindNotes } from './interfaces/MindNotes';
import { PaiOs, PaiRecruit, SiliconPdaLog } from './interfaces/PaiOs';
import { HtmlNotice, PlayerPolls } from './interfaces/PlayerPolls';
import { AirlockMaker, SandboxPanel } from './interfaces/Sandbox';
import { AiBotControl, AiVox, SiliconAlerts } from './interfaces/SiliconWindows';
import { TguiPrompt } from './interfaces/TguiPrompt';
import { VotePanel } from './interfaces/VotePanel';
import { CircuitAssembly } from './interfaces/CircuitAssembly';
import { CircuitCode } from './interfaces/CircuitCode';
import { CircuitPrinter } from './interfaces/CircuitPrinter';
import { Gps } from './interfaces/Gps';
import { GravityGenerator } from './interfaces/GravityGenerator';
import { GulagItemReclaimer } from './interfaces/GulagItemReclaimer';
import { HelpWindow } from './interfaces/HelpWindow';
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
import { PlayerProfile } from './interfaces/PlayerProfile';
import { Questions } from './interfaces/Questions';
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
import { Tickets } from './interfaces/Tickets';
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
import { Keybindings } from './interfaces/KeybindPanel';
import { RdConsole, RdFabricator } from './interfaces/RdConsole';
import { Sleeper } from './interfaces/Sleeper';
import { Autodoc } from './interfaces/Autodoc';
import { Mule } from './interfaces/Mule';
import { EmergencyShuttleConsole } from './interfaces/EmergencyShuttleConsole';
import { LaunchpadConsole, LaunchpadRemote } from './interfaces/Launchpad';
import { GulagConsole, LaborClaimConsole } from './interfaces/LaborCamp';
import { Intellicard, NtosAiRestorer } from './interfaces/AiCard';
import { Eightball, NotificationPanel, SlimeBodySwapper } from './interfaces/GhostAndSlime';
import { MaterialAnalyser, ReagentForge } from './interfaces/ChemLab';
import { ChemBluespace, ChemCentrifuge, ChemPressure, ChemRadioactive } from './interfaces/ChemInstruments';
import { ClockworkSlab } from './interfaces/ClockworkSlab';
import { CameraConsole } from './interfaces/CameraConsole';
import { Preferences } from './interfaces/Preferences';
import { Teleporter } from './interfaces/Teleporter';
import { ArcadeBattle, ArcadeMinesweeper } from './interfaces/Arcade';
import { ArcadeOrion } from './interfaces/OrionTrail';
import { PortableTurret, TurretControl } from './interfaces/Turrets';
import { Experimentor } from './interfaces/ResearchMachines';
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
import { BorerChems } from './interfaces/BorerChems';
import { MechSleeper, MechSyringeGun, PaiCard } from './interfaces/MechMedicalPai';
import { ExperimentScanner } from './interfaces/Experiments';
import { LateJoin, Lobby } from './interfaces/Lobby';
import { RoundEnd } from './interfaces/RoundEnd';
import { RoundStats } from './interfaces/RoundStats';
import { StationMap } from './interfaces/StationMap';
import { BotCrewMonitor } from './interfaces/BotCrewMonitor';
import { DiseaseMenu } from './interfaces/DiseaseMenu';
import { LogSearch } from './interfaces/LogSearch';
import { ResearchDashboard } from './interfaces/ResearchDashboard';
import { SiliconLaws } from './interfaces/SiliconLaws';
import { Spellbook } from './interfaces/Spellbook';
// hippie end

const ROUTES = {
  abductor_console: {
    component: () => AbductorConsole,
    scrollable: false,
  },
  abductor_experiment: {
    component: () => AbductorExperiment,
    scrollable: false,
  },
  achievements: {
    component: () => Achievements,
    scrollable: true,
  },
  ai_airlock: {
    component: () => AiAirlock,
    scrollable: false,
    theme: 'silicon',
  },
  ai_fixer: {
    component: () => AiFixer,
    scrollable: true,
    theme: 'science',
  },
  airalarm: {
    component: () => AirAlarm,
    scrollable: true,
    theme: 'atmos',
  },
  airlock_controller: {
    component: () => AirlockController,
    scrollable: true,
    theme: 'atmos',
  },
  airlock_electronics: {
    component: () => AirlockElectronics,
    scrollable: false,
    theme: 'engineering',
  },
  announcement_system: {
    component: () => AnnouncementSystem,
    scrollable: true,
    theme: 'command',
  },
  apc: {
    component: () => Apc,
    scrollable: false,
    theme: 'engineering',
  },
  apc_control: {
    component: () => ApcControl,
    scrollable: true,
    theme: 'engineering',
  },
  assembly: {
    component: () => Assembly,
    scrollable: false,
  },
  atmos_alert: {
    component: () => AtmosAlertConsole,
    scrollable: true,
    theme: 'atmos',
  },
  atmos_control: {
    component: () => AtmosControlConsole,
    scrollable: true,
    theme: 'atmos',
  },
  atmos_filter: {
    component: () => AtmosFilter,
    scrollable: false,
    theme: 'atmos',
  },
  atmos_mixer: {
    component: () => AtmosMixer,
    scrollable: false,
    theme: 'atmos',
  },
  atmos_pump: {
    component: () => AtmosPump,
    scrollable: false,
    theme: 'atmos',
  },
  aux_base: {
    component: () => AuxBase,
    scrollable: true,
    theme: 'cargo',
  },
  ban_window: {
    component: () => BanWindow,
    scrollable: false,
  },
  bank_vault: {
    component: () => BankVault,
    scrollable: true,
    theme: 'command',
  },
  bible_style: {
    component: () => BibleStyle,
    scrollable: true,
    theme: 'service',
  },
  biogenerator: {
    component: () => Biogenerator,
    scrollable: true,
    theme: 'service',
  },
  blueprints: {
    component: () => Blueprints,
    scrollable: true,
    theme: 'engineering',
  },
  book_reader: {
    component: () => BookReader,
    scrollable: true,
    theme: 'service',
  },
  borgopanel: {
    component: () => BorgPanel,
    scrollable: true,
  },
  bot_crew_monitor: {
    component: () => BotCrewMonitor,
    scrollable: true,
  },
  bounty_console: {
    component: () => BountyConsole,
    scrollable: true,
    theme: 'cargo',
  },
  brig_timer: {
    component: () => BrigTimer,
    scrollable: false,
    theme: 'security',
  },
  bsa: {
    component: () => BluespaceArtillery,
    scrollable: false,
    theme: 'command',
  },
  camera_bug: {
    component: () => CameraBug,
    scrollable: true,
  },
  canister: {
    component: () => Canister,
    scrollable: false,
    theme: 'atmos',
  },
  cargo: {
    component: () => Cargo,
    scrollable: true,
    theme: 'cargo',
  },
  cargo_express: {
    component: () => CargoExpress,
    scrollable: true,
    theme: 'cargo',
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
    theme: 'medical',
  },
  admin_find: {
    component: () => AdminFind,
    scrollable: false,
  },
  debug_counts: {
    component: () => DebugCounts,
    scrollable: true,
  },
  debug_profiler: {
    component: () => DebugProfiler,
    scrollable: true,
  },
  grief_undo: {
    component: () => GriefUndo,
    scrollable: false,
  },
  station_looks: {
    component: () => StationLooks,
    scrollable: true,
  },
  chem_dispenser: {
    component: () => ChemDispenser,
    scrollable: true,
    theme: 'medical',
  },
  chemical_filter: {
    component: () => ChemFilter,
    scrollable: true,
    theme: 'medical',
  },
  chem_heater: {
    component: () => ChemHeater,
    scrollable: true,
    theme: 'medical',
  },
  chem_master: {
    component: () => ChemMaster,
    scrollable: true,
    theme: 'medical',
  },
  chem_press: {
    component: () => ChemPress,
    scrollable: false,
    theme: 'medical',
  },
  coin_press: {
    component: () => CoinPress,
    scrollable: true,
    theme: 'cargo',
  },
  cyborg_frame: {
    component: () => CyborgFrame,
    scrollable: true,
    theme: 'science',
  },
  destination_tagger: {
    component: () => DestinationTagger,
    scrollable: false,
    theme: 'cargo',
  },
  dna_console: {
    component: () => DnaConsole,
    scrollable: true,
    theme: 'medical',
  },
  doppler_array: {
    component: () => DopplerArray,
    scrollable: true,
    theme: 'science',
  },
  exosuit: {
    component: () => Exosuit,
    scrollable: true,
    theme: 'mecha',
  },
  exosuit_fabricator: {
    component: () => ExosuitFabricator,
    scrollable: false,
    theme: 'science',
  },
  experiment_scanner: {
    component: () => ExperimentScanner,
    scrollable: true,
    theme: 'science',
  },
  gun_locker: {
    component: () => GunLocker,
    scrollable: true,
    theme: 'security',
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
    theme: 'security',
  },
  jani_cart: {
    component: () => JaniCart,
    scrollable: true,
    theme: 'service',
  },
  jukebox: {
    component: () => Jukebox,
    scrollable: true,
    theme: 'service',
  },
  late_join: {
    component: () => LateJoin,
    scrollable: false,
  },
  library_console: {
    component: () => LibraryConsole,
    scrollable: true,
    theme: 'service',
  },
  library_scanner: {
    component: () => LibraryScanner,
    scrollable: false,
    theme: 'service',
  },
  library_visitor: {
    component: () => LibraryVisitor,
    scrollable: true,
    theme: 'service',
  },
  limb_grower: {
    component: () => LimbGrower,
    scrollable: true,
    theme: 'medical',
  },
  lobby: {
    component: () => Lobby,
    scrollable: false,
  },
  mass_driver_console: {
    component: () => MassDriverConsole,
    scrollable: true,
    theme: 'cargo',
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
    theme: 'science',
  },
  message_monitor: {
    component: () => MessageMonitor,
    scrollable: true,
    theme: 'command',
  },
  mime_book: {
    component: () => MimeBook,
    scrollable: true,
  },
  mining_vendor: {
    component: () => MiningVendor,
    scrollable: true,
    theme: 'cargo',
  },
  nav_beacon: {
    component: () => NavBeacon,
    scrollable: true,
  },
  newscaster: {
    component: () => Newscaster,
    scrollable: true,
  },
  ntos_station_map: {
    component: () => StationMap,
    wrapper: () => NtosWrapper,
    scrollable: false,
    theme: 'ntos',
  },
  ore_silo: {
    component: () => OreSilo,
    scrollable: true,
    theme: 'cargo',
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
    theme: 'engineering',
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
    theme: 'service',
  },
  pipe_dispenser: {
    component: () => PipeDispenser,
    scrollable: true,
    theme: 'atmos',
  },
  plant_dna_manipulator: {
    component: () => PlantDnaManipulator,
    scrollable: true,
    theme: 'service',
  },
  prisoner_console: {
    component: () => PrisonerConsole,
    scrollable: true,
    theme: 'security',
  },
  rcd_access: {
    component: () => RcdAccess,
    scrollable: true,
    theme: 'engineering',
  },
  reaction_chamber: {
    component: () => ChemReactionChamber,
    scrollable: true,
    theme: 'medical',
  },
  chem_splitter: {
    component: () => ChemSplitter,
    scrollable: false,
    theme: 'medical',
  },
  chem_synthesizer: {
    component: () => ChemDebugSynthesizer,
    scrollable: false,
    theme: 'medical',
  },
  requests_console: {
    component: () => RequestsConsole,
    scrollable: true,
  },
  robotics_console: {
    component: () => RoboticsConsole,
    scrollable: true,
    theme: 'science',
  },
  roundend_report: {
    component: () => RoundEnd,
    scrollable: false,
  },
  round_stats: {
    component: () => RoundStats,
    scrollable: true,
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
    theme: 'security',
  },
  seed_extractor: {
    component: () => SeedExtractor,
    scrollable: true,
    theme: 'service',
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
    theme: 'cargo',
  },
  song_editor: {
    component: () => SongEditor,
    scrollable: true,
  },
  stack_crafting: {
    component: () => StackCrafting,
    scrollable: true,
  },
  station_map: {
    component: () => StationMap,
    scrollable: false,
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
    theme: 'engineering',
  },
  cloning_console: {
    component: () => CloningConsole,
    scrollable: true,
    theme: 'medical',
  },
  comms_console: {
    component: () => CommsConsole,
    scrollable: true,
    theme: 'command',
  },
  crayon: {
    component: () => Crayon,
    scrollable: true,
  },
  crew: {
    component: () => CrewConsole,
    scrollable: true,
    theme: 'medical',
  },
  cryo: {
    component: () => Cryo,
    scrollable: false,
    theme: 'medical',
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
    theme: 'engineering',
  },
  gulag_item_reclaimer: {
    component: () => GulagItemReclaimer,
    scrollable: true,
    theme: 'security',
  },
  holodeck: {
    component: () => Holodeck,
    scrollable: true,
    theme: 'service',
  },
  id_console: {
    component: () => IdConsole,
    scrollable: true,
    theme: 'command',
  },
  implantchair: {
    component: () => ImplantChair,
    scrollable: false,
    theme: 'security',
  },
  keycard_auth: {
    component: () => KeycardAuth,
    scrollable: false,
    theme: 'command',
  },
  language_menu: {
    component: () => LanguageMenu,
    scrollable: true,
  },
  mech_bay_power_console: {
    component: () => MechBayPowerConsole,
    scrollable: false,
    theme: 'science',
  },
  medical_kiosk: {
    component: () => MedicalKiosk,
    scrollable: false,
    theme: 'medical',
  },
  medical_records: {
    component: () => MedicalRecords,
    scrollable: false,
    theme: 'medical',
  },
  mint: {
    component: () => Mint,
    scrollable: false,
    theme: 'cargo',
  },
  nanite_chamber_control: {
    component: () => NaniteChamberControl,
    scrollable: false,
    theme: 'science',
  },
  nanite_cloud_control: {
    component: () => NaniteCloudControl,
    scrollable: false,
    theme: 'science',
  },
  nanite_program_hub: {
    component: () => NaniteProgramHub,
    scrollable: false,
    theme: 'science',
  },
  nanite_programmer: {
    component: () => NaniteProgrammer,
    scrollable: false,
    theme: 'science',
  },
  nanite_remote: {
    component: () => NaniteRemote,
    scrollable: false,
    theme: 'science',
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
    theme: 'cargo',
  },
  ore_box: {
    component: () => OreBox,
    scrollable: true,
    theme: 'cargo',
  },
  operating_computer: {
    component: () => OperatingComputer,
    scrollable: true,
    theme: 'medical',
  },
  pandemic: {
    component: () => Pandemic,
    scrollable: true,
    theme: 'medical',
  },
  personal_crafting: {
    component: () => PersonalCrafting,
    scrollable: false,
  },
  portable_generator: {
    component: () => PortableGenerator,
    scrollable: false,
    theme: 'engineering',
  },
  portable_pump: {
    component: () => PortablePump,
    scrollable: false,
    theme: 'atmos',
  },
  portable_scrubber: {
    component: () => PortableScrubber,
    scrollable: false,
    theme: 'atmos',
  },
  power_monitor: {
    component: () => PowerMonitor,
    scrollable: true,
    theme: 'engineering',
  },
  radio: {
    component: () => Radio,
    scrollable: false,
  },
  rpd: {
    component: () => RapidPipeDispenser,
    scrollable: true,
    theme: 'atmos',
  },
  sat_control: {
    component: () => SatelliteControl,
    scrollable: false,
    theme: 'engineering',
  },
  scanner_gate: {
    component: () => ScannerGate,
    scrollable: false,
    theme: 'security',
  },
  shuttle_manipulator: {
    component: () => ShuttleManipulator,
    scrollable: true,
  },
  smartvend: {
    component: () => SmartVend,
    scrollable: true,
    theme: 'service',
  },
  smes: {
    component: () => Smes,
    scrollable: false,
    theme: 'engineering',
  },
  smoke_machine: {
    component: () => SmokeMachine,
    scrollable: false,
    theme: 'medical',
  },
  solar_control: {
    component: () => SolarControl,
    scrollable: false,
    theme: 'engineering',
  },
  space_heater: {
    component: () => SpaceHeater,
    scrollable: false,
    theme: 'atmos',
  },
  spawners_menu: {
    component: () => SpawnersMenu,
    scrollable: false,
  },
  station_alert: {
    component: () => StationAlertConsole,
    scrollable: true,
    theme: 'engineering',
  },
  suit_storage_unit: {
    component: () => SuitStorageUnit,
    scrollable: false,
  },
  tanks: {
    component: () => Tank,
    scrollable: false,
    theme: 'atmos',
  },
  tank_dispenser: {
    component: () => TankDispenser,
    scrollable: false,
    theme: 'atmos',
  },
  telecomms_logs: {
    component: () => TelecommsLogs,
    scrollable: true,
    theme: 'engineering',
  },
  telecomms_machine: {
    component: () => TelecommsMachine,
    scrollable: true,
    theme: 'engineering',
  },
  telecomms_monitor: {
    component: () => TelecommsMonitor,
    scrollable: true,
    theme: 'engineering',
  },
  thermoelectric_generator: {
    component: () => ThermoelectricGenerator,
    scrollable: false,
    theme: 'engineering',
  },
  thermomachine: {
    component: () => ThermoMachine,
    scrollable: false,
    theme: 'atmos',
  },
  transfer_valve: {
    component: () => TransferValve,
    scrollable: true,
    theme: 'science',
  },
  turbine_computer: {
    component: () => TurbineComputer,
    scrollable: false,
    theme: 'engineering',
  },
  uplink: {
    component: () => Uplink,
    scrollable: true,
    theme: 'syndicate',
  },
  vault_controller: {
    component: () => VaultController,
    scrollable: false,
    theme: 'command',
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
    theme: 'service',
  },
  display_settings: {
    component: () => DisplaySettings,
    scrollable: false,
  },
  keybindings: {
    component: () => Keybindings,
    scrollable: true,
  },
  scrubber_pack: {
    component: () => ScrubberPack,
    scrollable: true,
    theme: 'atmos',
  },
  master_multitool: {
    component: () => MasterMultitool,
    scrollable: true,
    theme: 'engineering',
  },
  orbit: {
    component: () => Orbit,
    scrollable: false,
  },
  rdconsole: {
    component: () => RdConsole,
    scrollable: false,
    theme: 'science',
  },
  rd_fabricator: {
    component: () => RdFabricator,
    scrollable: false,
    theme: 'science',
  },
  sleeper: {
    component: () => Sleeper,
    scrollable: true,
    theme: 'medical',
  },
  autodoc: {
    component: () => Autodoc,
    scrollable: false,
    theme: 'medical',
  },
  mulebot: {
    component: () => Mule,
    scrollable: true,
    theme: 'cargo',
  },
  emergency_shuttle_console: {
    component: () => EmergencyShuttleConsole,
    scrollable: true,
    theme: 'command',
  },
  launchpad_console: {
    component: () => LaunchpadConsole,
    scrollable: true,
    theme: 'science',
  },
  launchpad_remote: {
    component: () => LaunchpadRemote,
    scrollable: true,
    theme: 'syndicate',
  },
  gulag_console: {
    component: () => GulagConsole,
    scrollable: true,
    theme: 'security',
  },
  labor_claim_console: {
    component: () => LaborClaimConsole,
    scrollable: true,
    theme: 'security',
  },
  intellicard: {
    component: () => Intellicard,
    scrollable: true,
    theme: 'science',
  },
  ntos_ai_restorer: {
    component: () => NtosAiRestorer,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'ntos',
  },
  notificationpanel: {
    component: () => NotificationPanel,
    scrollable: false,
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
    theme: 'engineering',
  },
  chem_pressure: {
    component: () => ChemPressure,
    scrollable: false,
    theme: 'medical',
  },
  chem_radioactive: {
    component: () => ChemRadioactive,
    scrollable: false,
    theme: 'medical',
  },
  chem_bluespace: {
    component: () => ChemBluespace,
    scrollable: false,
    theme: 'medical',
  },
  chem_centrifuge: {
    component: () => ChemCentrifuge,
    scrollable: false,
    theme: 'medical',
  },
  chem_reagent_analysis: {
    component: () => MaterialAnalyser,
    scrollable: true,
    theme: 'medical',
  },
  chem_reagent_forge: {
    component: () => ReagentForge,
    scrollable: true,
    theme: 'medical',
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
    theme: 'security',
  },
  turret_control: {
    component: () => TurretControl,
    scrollable: true,
    theme: 'security',
  },
  experimentor: {
    component: () => Experimentor,
    scrollable: true,
    theme: 'science',
  },
  magnet_controller: {
    component: () => MagnetController,
    scrollable: true,
    theme: 'engineering',
  },
  stacking_console: {
    component: () => StackingConsole,
    scrollable: true,
    theme: 'cargo',
  },
  food_cart: {
    component: () => FoodCart,
    scrollable: true,
    theme: 'service',
  },
  icecream_vat: {
    component: () => IcecreamVat,
    scrollable: true,
    theme: 'service',
  },
  arcade_orion: {
    component: () => ArcadeOrion,
    scrollable: false,
  },
  arcade_battle: {
    component: () => ArcadeBattle,
    scrollable: false,
  },
  borer_chems: {
    component: () => BorerChems,
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
    theme: 'security',
  },
  disease_menu: {
    component: () => DiseaseMenu,
    scrollable: false,
  },
  gland_dispenser: {
    component: () => GlandDispenser,
    scrollable: false,
  },
  log_search: {
    component: () => LogSearch,
    scrollable: false,
  },
  tickets: {
    component: () => Tickets,
    scrollable: false,
  },
  game_menu: {
    component: () => GameMenu,
    scrollable: false,
  },
  admin_hub: {
    component: () => AdminHub,
    scrollable: false,
  },
  help_window: {
    component: () => HelpWindow,
    scrollable: false,
  },
  questions: {
    component: () => Questions,
    scrollable: false,
  },
  player_profile: {
    component: () => PlayerProfile,
    scrollable: false,
  },
  admin_alerts: {
    component: () => AdminAlerts,
    scrollable: false,
  },
  research_dashboard: {
    component: () => ResearchDashboard,
    scrollable: false,
    theme: 'science',
  },
  silicon_laws: {
    component: () => SiliconLaws,
    scrollable: false,
    theme: 'silicon',
  },
  spellbook: {
    component: () => Spellbook,
    scrollable: false,
  },
  synd_contract: {
    component: () => SyndContract,
    wrapper: () => NtosWrapper,
    scrollable: true,
    theme: 'syndicate',
  },
  tgui_prompt: {
    component: () => TguiPrompt,
    scrollable: false,
  },
  vote_panel: {
    component: () => VotePanel,
    scrollable: true,
  },
  circuit_assembly: {
    component: () => CircuitAssembly,
    scrollable: false,
    theme: 'science',
  },
  circuit_code: {
    component: () => CircuitCode,
    scrollable: false,
  },
  circuit_printer: {
    component: () => CircuitPrinter,
    scrollable: true,
    theme: 'science',
  },
  // hippie end
  crew_manifest: {
    component: () => CrewManifest,
    scrollable: false,
  },
  mind_notes: {
    component: () => MindNotes,
    scrollable: false,
  },
  silicon_alerts: {
    component: () => SiliconAlerts,
    scrollable: false,
    theme: 'silicon',
  },
  ai_bot_control: {
    component: () => AiBotControl,
    scrollable: false,
    theme: 'silicon',
  },
  ai_vox: {
    component: () => AiVox,
    scrollable: false,
    theme: 'silicon',
  },
  pai_os: {
    component: () => PaiOs,
    scrollable: false,
  },
  pai_recruit: {
    component: () => PaiRecruit,
    scrollable: false,
  },
  silicon_pda_log: {
    component: () => SiliconPdaLog,
    scrollable: false,
    theme: 'silicon',
  },
  malf_modules: {
    component: () => MalfModules,
    scrollable: true,
    theme: 'syndicate',
  },
  arcane_tome: {
    component: () => ArcaneTome,
    scrollable: false,
  },
  gang_tool: {
    component: () => GangTool,
    scrollable: true,
  },
  apprentice_contract: {
    component: () => ApprenticeContract,
    scrollable: false,
  },
  teleport_scroll: {
    component: () => TeleportScroll,
    scrollable: false,
  },
  rad_laser: {
    component: () => RadLaser,
    scrollable: true,
    theme: 'syndicate',
  },
  pirate_pad: {
    component: () => PiratePad,
    scrollable: true,
  },
  antag_tips: {
    component: () => AntagTips,
    scrollable: true,
  },
  card_hand: {
    component: () => CardHand,
    scrollable: false,
  },
  newspaper: {
    component: () => Newspaper,
    scrollable: false,
  },
  locator: {
    component: () => Locator,
    scrollable: true,
  },
  valentine: {
    component: () => Valentine,
    scrollable: false,
  },
  exosuit_maint: {
    component: () => ExosuitMaint,
    scrollable: true,
    theme: 'mecha',
  },
  telescience: {
    component: () => Telescience,
    scrollable: true,
    theme: 'science',
  },
  analyzer_history: {
    component: () => AnalyzerHistory,
    scrollable: true,
    theme: 'science',
  },
  prototype_cloning: {
    component: () => PrototypeCloning,
    scrollable: true,
    theme: 'medical',
  },
  artillery_control: {
    component: () => ArtilleryControl,
    scrollable: true,
    theme: 'command',
  },
  bot_panel: {
    component: () => BotPanel,
    scrollable: false,
  },
  player_polls: {
    component: () => PlayerPolls,
    scrollable: true,
  },
  html_notice: {
    component: () => HtmlNotice,
    scrollable: true,
  },
  admin_player_panel: {
    component: () => AdminPlayerPanel,
    scrollable: true,
  },
  admin_secrets: {
    component: () => AdminSecrets,
    scrollable: true,
  },
  admin_list: {
    component: () => AdminList,
    scrollable: true,
  },
  admin_round_status: {
    component: () => RoundStatus,
    scrollable: true,
  },
  admin_traitor_panel: {
    component: () => TraitorPanel,
    scrollable: true,
  },
  admin_team_listing: {
    component: () => TeamListing,
    scrollable: true,
  },
  admin_spawner: {
    component: () => AdminSpawner,
    scrollable: true,
  },
  admin_outfit_manager: {
    component: () => OutfitManager,
    scrollable: true,
  },
  admin_outfit_editor: {
    component: () => OutfitEditor,
    scrollable: true,
  },
  admin_job_slots: {
    component: () => JobSlots,
    scrollable: true,
  },
  admin_players: {
    component: () => AdminPlayers,
    scrollable: true,
  },
  bot_crew: {
    component: () => BotCrew,
    scrollable: true,
  },
  admin_game_panel: {
    component: () => AdminGamePanel,
    scrollable: true,
  },
  admin_one_click_antag: {
    component: () => AdminOneClickAntag,
    scrollable: true,
  },
  admin_station_goals: {
    component: () => AdminStationGoals,
    scrollable: true,
  },
  admin_permissions: {
    component: () => AdminPermissions,
    scrollable: true,
  },
  admin_edit_log: {
    component: () => AdminEditLog,
    scrollable: true,
  },
  admin_related_accounts: {
    component: () => AdminRelatedAccounts,
    scrollable: true,
  },
  player_notes: {
    component: () => PlayerNotes,
    scrollable: true,
  },
  admin_investigate: {
    component: () => AdminInvestigate,
    scrollable: false,
  },
  admin_individual_log: {
    component: () => AdminIndividualLog,
    scrollable: true,
  },
  admin_log_files: {
    component: () => AdminLogFiles,
    scrollable: false,
  },
  admin_sdql_results: {
    component: () => AdminSdqlResults,
    scrollable: true,
  },
  admin_playtime: {
    component: () => AdminPlaytime,
    scrollable: false,
  },
  player_playtime: {
    component: () => PlayerPlaytime,
    scrollable: true,
  },
  admin_upgrade_report: {
    component: () => AdminUpgradeReport,
    scrollable: true,
  },
  admin_dynamic: {
    component: () => AdminDynamic,
    scrollable: true,
  },
  admin_events: {
    component: () => AdminEvents,
    scrollable: true,
  },
  admin_beakers: {
    component: () => AdminBeakers,
    scrollable: true,
  },
  admin_sound_emitter: {
    component: () => AdminSoundEmitter,
    scrollable: true,
  },
  admin_report: {
    component: () => AdminReport,
    scrollable: true,
  },
  admin_del_log: {
    component: () => AdminDelLog,
    scrollable: true,
  },
  sandbox_panel: {
    component: () => SandboxPanel,
    scrollable: true,
  },
  airlock_maker: {
    component: () => AirlockMaker,
    scrollable: true,
    theme: 'engineering',
  },
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
