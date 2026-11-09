# TGS event scripts

Scripts for hosting the game with [tgstation-server](https://github.com/tgstation/tgstation-server) 6.x (tested with
6.19.2; the game speaks DMAPI 7.4.0). TGS runs a script from the instance's `Configuration/EventScripts` folder when
its event happens: `.bat` on Windows, `.sh` on Linux. Copy the ones for your OS there; TGS doesn't read this folder.

| Script | Event | What it does |
| --- | --- | --- |
| `PostCompile.bat` / `.sh` | after each compile | Runs `smoke_boot.ps1` / `.sh` **from the new build**: boots it headless and fails the deploy unless it gets through initialization, so a build that can't start never goes live. Prints the boot's runtime errors to the TGS job log. |
| `PreCompile.sh` | before each compile (Linux) | Puts `librust_g.so` in the build: the prebuilt i686 library from the rust-g release in `dependencies.sh` (`RUST_G_VERSION`), cached in `cache/` here. Windows needs nothing: the DLLs are committed. |
| `InstallDeps.sh`, `WatchdogLaunch.sh` | (Linux) | The 32-bit runtime libraries, curl and python3. Tries `sudo -n`; without passwordless sudo it prints the `apt-get` line to run yourself. |
| `HippieUpdate.bat` + `HippieUpdate.ps1` / `HippieUpdate.sh` | custom event `HippieUpdate` | The in-game **Update Server** verb (+SERVER): pulls the tracked branch from GitHub into TGS's repository (test merges stay, a merge conflict stops it), starts a deploy, and tells the game how it went. Live next round. |

The update scripts run from EventScripts rather than from the game's code, so a test merge can't change what runs
with the TGS login.

## Setting up an instance

Run TGS under a Windows or Linux user of its own, never your own account: every time TGS starts it deletes that user's
`Documents\BYOND\cache` (`~/.byond/cache`) and `cfg\trusted.txt`. On Windows, TGS 6.19 also needs admin rights (it
makes symlinks); the installer's service handles that.

1. **Repository:** clone this repo, tracking the branch you deploy.
2. **Deployment:** project name `hippiestation` (the repo also has the unused `tgstation.dme`); API validation security
   level **Trusted** (native libraries and `shell()` need it).
3. **Game server:** security level **Trusted**. Health checks and the startup timeout can stay at their defaults.
4. **Static files:** put `data` (logs, saves, bans and notes without a database) and `config` (your edited copy) in
   `GameStaticFiles`, so they survive deploys.
5. **EventScripts:** copy the scripts for your OS. For Update Server also copy `hippie_update.example.json` as
   `hippie_update.json` and fill it in: the TGS address and a TGS user that has, on this instance, only
   Repository: Read, Update branch and Deployment: Read, Compile. Set `"instance"` to the instance's ID (shown in the
   TGS web panel); left `null`, the script looks it up by the instance's folder, which needs a user that can list instances.
6. **Chat (Discord):** add a chat bot and its channels in TGS. Mark staff channels as admin channels: ahelps, ban alerts and
   round start/end for admins go there. Give the public channel a tag and set the same tag as `CHAT_ANNOUNCE_NEW_GAME`
   in `config/config.txt`: the round start and round end notices (embeds) go there.
7. **Discord admin commands** (`status`, `ahelp`, `namecheck`, `adminwho`, `sdql`) only run for a Discord account linked
   to a game admin with the rights, which needs the database: the admin uses Link Discord Account in game, then
   `verify <ckey>` in Discord. `SECURE_CHAT_COMMANDS 0` in `config/hippiestation_config.txt` turns the check off.

TGS posts its own deployment notices (started, finished, failed) to chat channels marked for updates.

## Trying a script by hand

- Smoke boot: `powershell -File tools\tgs_scripts\smoke_boot.ps1 -GameDir <folder with the .dmb> -DreamDaemon "C:\Program Files (x86)\BYOND\bin\dd.exe"`
  or `DREAMDAEMON=/path/to/DreamDaemon tools/tgs_scripts/smoke_boot.sh <folder>`. It boots whichever `.dmb` it finds first.
- Update: `HippieUpdate.ps1 -GameDir <a scratch folder> -Ckey test` with `TGS_INSTANCE_ROOT` set or `"instance"` filled in;
  the result lands in `<scratch folder>\data\tgs_update.json`. It really pulls and deploys.
