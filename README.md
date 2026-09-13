# Core Keeper

A self-contained Core Keeper dedicated server image with scheduled backups, in-place auto-updates
from Steam, Discord notifications — including the **Game ID** your friends join with in relay mode — and player
join/leave events. Built on the [GameOps](https://github.com/Reclyptor/GameOps) toolkit.

```sh
mkdir -p data backups && sudo chown -R 1000:1000 data backups
docker run -d --name corekeeper \
  -e WORLD_NAME="Our Cave" -e DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/… \
  -v "$PWD/data:/data" -v "$PWD/backups:/backups" \
  ghcr.io/reclyptor/corekeeper:latest
```

Or use [`compose.yaml`](compose.yaml). The first start installs the server through SteamCMD
(1–2 GB, into `data/server`, once). No ports to open: players join by Game ID through Steam's
relay. The ID is printed in the log, posted to Discord on every start, and kept in `data/gameid`.

## What it does for you

| | |
|---|---|
| **Game ID** | Generated once and persisted, so it survives restarts and updates. In relay mode it is announced on Discord each time the server comes up; in direct-connect mode the START message carries the address instead. |
| **Backups** | Nightly by default: `world/` into `/backups/corekeeper-<timestamp>.tar.gz`, pruned after `BACKUP_RETAIN_DAYS`. The game has no save command, so the archive is taken with a settled-file guard against a mid-autosave copy. `docker exec corekeeper gameops backup` any time. |
| **Updates** | Hourly check of the Steam depot manifest. When a build lands: players are told on Discord (the game cannot broadcast in-game), the server waits for an empty world up to `UPDATE_FORCE_AFTER_MINUTES`, a backup is taken, SteamCMD updates in place, and the server relaunches **inside the same container**. |
| **Notifications** | Discord: online (with the address and join password in direct-connect mode), Game ID (relay mode), offline, crashed, updating/updated, backup, join, leave. Plain text, every message overridable. |
| **Lifecycle** | `SIGTERM` is forwarded to the server. Crashes exit the container with the game's code. Health = process up and session published. |

## Configuration

### Core Keeper

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_NAME` | `Core Keeper` | The name notifications use (the toolkit's; the game itself has no server name). |
| `MAX_PLAYERS` | `10` | |
| `GAME_PASSWORD` | — | Join password, direct-connect mode only. Direct connections always take one: leave this empty and the server generates its own. Either way the START message announces the password in force. |
| `WORLD_NAME` | `Core Keeper Server` | World name, which is what players see. |
| `WORLD_INDEX` | `0` | Which world slot to run. |
| `WORLD_SEED` | *(random)* | Seed for a new world. |
| `HASHED_WORLD_SEED` | — | Hashed seed (v1.1+). |
| `WORLD_MODE` | `0` | `0` Normal, `1` Hard, `2` Creative, `4` Casual. |
| `SEASON` | — | Force a season (`0`–`7`); unset follows the real date. |
| `GAME_ID` | *(generated)* | 15–28 alphanumeric characters. Leave unset to keep the generated one in `/data/gameid`. |
| `ACTIVATE_CONTENT` / `ACTIVATE_ALL_CONTENT` | — / `false` | Enable content bundles on pre-1.1 worlds (irreversible). |
| `ALLOW_ONLY_PLATFORM` | — | Direct-connect only: `1` Steam, `2` Epic, `3` Microsoft, `4` GOG. |
| `LOGFILE` | `/dev/stdout` | Where the server writes its log. |
| `BIND` | `0.0.0.0` | Bind address in direct-connect mode. |
| `PORT` | — | **Setting this switches to direct-connect mode** (UDP; publish the port). Unset = Steam relay, join by Game ID. |

### Backups, updates, notifications

The [GameOps](https://github.com/Reclyptor/GameOps#configuration) variables, identical across every
Reclyptor game image: `BACKUP_CRON`, `BACKUP_RETAIN_DAYS`, `BACKUP_ON_UPDATE`, `UPDATE_CRON`,
`UPDATE_ON_BOOT`, `UPDATE_FORCE_AFTER_MINUTES`, `UPDATE_SKIP_IF_PLAYERS`, `STOP_TIMEOUT`,
`METRICS_PORT`, `DISCORD_WEBHOOK_URL`, `DISCORD_<EVENT>_MESSAGE`, `TZ`, … plus this image's
`DISCORD_GAMEID_MESSAGE` (default `🎮 server_name server Game ID: game_id`), sent in relay mode only.
Backups are verified as they are written; `gameops backup list`, `gameops backup verify latest` and
`gameops restore latest` work from `docker exec`.

Because the game cannot be told anything, three things are worth knowing: there is no in-game
update warning (Discord only); the player count comes from join/leave events, so it is right as
long as the container saw the joins; and there is no save command, so backups rely on the game's
own autosave.

## Volumes and ports

| | |
|---|---|
| `/data` | `server/` (the install), `world/`, `gameid`, `logs/` — uid/gid **1000** |
| `/backups` | Archives. Mount a NAS share here for off-box copies. |
| `9110/tcp` | `/metrics` (Prometheus) and `/healthz` — `METRICS_PORT`, `0` disables |

## Development

```sh
tests/run.sh      # bats, inside the built image
tests/smoke.sh    # real server via SteamCMD: session → Game ID → backup → update check → SIGTERM
```

## License

MIT.
