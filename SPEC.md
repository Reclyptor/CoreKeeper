# SPEC: Core Keeper — a self-contained dedicated server image

**Status:** IMPLEMENTED — v2 (GameOps 1.0.0).
**Drafted:** 2026-09-12
**Deliverable:** `ghcr.io/reclyptor/corekeeper`, built on [GameOps](https://github.com/Reclyptor/GameOps).

---

## 1. Purpose

Run the Core Keeper dedicated server as a single container that looks after itself: scheduled
backups, Steam-driven updates applied in place, Discord notifications including the **Game ID** in relay mode
players need to join, and player join/leave events — with nothing to configure beyond a world
name.

Core Keeper is the toolkit's hardest case: the server has **no control channel at all**. No RCON,
no REST API, no console input. It can be told nothing; it can only be observed (its log,
`GameInfo.txt`) and signalled. This image is the proof that the GameOps contract degrades
honestly instead of pretending.

### Non-goals
- **Not a mod manager.** mod.io mod installation is out of scope.
- **Not arm64.** Core Keeper ships x86-64 only; box64 emulation is out of scope.
- **Not a port publisher by default.** The default network mode is Steam Datagram Relay: players
  join by Game ID and no inbound port exists. Direct-connect mode is opt-in by setting `PORT`.

---

## 2. Hard constraints

| # | Constraint |
|---|---|
| K1 | **Never start as root.** uid/gid `1000:1000` (`steam`). SteamCMD runs as that user with `HOME=/home/steam`. |
| K2 | **Declare what the game cannot do.** `game_save`, `game_broadcast` and `game_players` return `2`. The toolkit then: relies on autosave plus the settled-file guard for backups; counts players from join/leave events; and, for updates, waits for an empty server up to `UPDATE_FORCE_AFTER_MINUTES` with the Discord `UPDATE_PRE` message as the only warning. |
| K3 | **The Game ID is stable.** Generated once, kept in `/data/gameid`, announced on Discord after every launch in relay mode (direct-connect players get the address in the START message instead). Players never need a new one after a restart or an update. |
| K4 | **Stop is a signal.** `SIGTERM` reaches the server through the launch wrapper; whether the world is flushed on it is measured by the smoke test and recorded in §5, not assumed. |
| K5 | **Everything is on the volume.** The server install (`/data/server`) and the world (`/data/world`) both live under `DATA_DIR`, so a container replacement never re-downloads 1–2 GB. |

---

## 3. The image

`debian:trixie-slim` with the i386 architecture enabled for SteamCMD's 32-bit binary
(`lib32gcc-s1`, `lib32stdc++6`), `xvfb` and `libxi6` (the headless Unity build still opens a
display), and a `steam` user (1000:1000). SteamCMD is downloaded from Valve at build time into
`/home/steam/steamcmd` and self-updated once so the first boot does not. The server is installed
at first boot by SteamCMD — Steamworks redistributable app `1007` and the dedicated server app
`1963720` — into `/data/server`. Nothing else is installed; the toolkit does HTTP, JSON and
archiving itself.

| Path | Contents |
|---|---|
| `/data/server` | The game, installed and updated by SteamCMD (`GAME_DIR`) |
| `/data/world` | World data (`-datapath`) |
| `/data/gameid` | The persisted Game ID |
| `/backups` | Archives of `world/` |
| `/opt/gameops`, `/opt/game` | Toolkit and adapter |

## 4. The adapter

| Contract function | Core Keeper implementation |
|---|---|
| `game_install` | `steam_install` of `1007` + `1963720` when `CoreKeeperServer` is absent; ensure the Game ID exists. |
| `game_version` | `buildid` from `appmanifest_1963720.acf`. |
| `game_update_available` / `game_update_apply` | `steam_update_available` on depot `1963722`; apply = `steam_install` again. |
| `game_start_cmd` | `launch.sh` wrapper: clears the X lock, starts `Xvfb :99`, runs `CoreKeeperServer -batchmode -logfile … -world … -worldname … -gameid … -datapath /data/world …` with `LD_LIBRARY_PATH` pointing at SteamCMD's `linux64/` for `steamclient.so`, forwards `SIGTERM`, tears Xvfb down, exits with the server's code. Stale `GameID.txt`/`GameInfo.txt` are removed first. |
| `game_ready` | `Started session with info` in the log; in relay mode, on the first sighting of `GameInfo.txt` per launch, sends the `GAMEID` notification with the Game ID. |
| `game_healthy` | Process alive and `GameInfo.txt` present (no port to probe in SDR mode). |
| `game_save` / `game_broadcast` / `game_players` | `2` — unsupported. |
| `game_shutdown` | The toolkit default: `SIGTERM`. |
| `game_events` | Log tail: `[userid:<id>] player <name> connected islocalplayer=…` → `JOIN`; `Disconnected from userid:<id> with reason …` → `LEAVE`, name resolved through a per-launch id→name map. |
| `game_backup_paths` | `world`. |

The server log goes to stdout (`-logfile /dev/stdout`, the default), so the toolkit's console log
carries it and `follow_log` needs no special path; `LOGFILE` overrides.

## 5. Verification

- `tests/*.bats` (inside the built image): parameter compilation, Game ID generation, validation
  and persistence, `GameInfo.txt` parsing, the JOIN/LEAVE parser against fixture lines, build-id
  and update detection from manifest fixtures, `game_install`'s SteamCMD invocation.
- `tests/smoke.sh` (real SteamCMD install): session up → Game ID announced and persisted → health →
  backup holds `world/` → live Steam update check → `SIGTERM` exits 0 → **reports whether the
  world's newest file mtime advanced on `SIGTERM`**. Result recorded below after the first run.

### Measured: save on SIGTERM
First smoke run, build `23543502`, 2026-09-13: the newest file under `/data/world` advanced from
mtime `1789273231` to `1789273242` across `docker stop` (SIGTERM forwarded by `launch.sh`, exit
code 0). **The server does flush its data directory on SIGTERM**, so the toolkit's default
`game_shutdown` is sufficient and no settled-file wait before signalling is needed. Observed
session output: `Started session with info: …` in the log and `GameInfo.txt` containing
`GameID: <id>` next to the executable; with no players the data directory held only
`Admins.json ServerConfig.json modloader mods` — the world file itself appears once the world has
state to save.
