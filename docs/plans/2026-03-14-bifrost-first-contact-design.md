# Bifrost "First Contact" POC Design

Cross-game chat between Terasology and DestinationSol via Nakama, proving federated game connectivity without requiring multiplayer in DestinationSol.

## Motivation

Bifrost aims to connect independent game engines into a federated metaverse. The biggest conceptual hurdle is the assumption that connected games must each have full multiplayer support. This POC disproves that by linking a multiplayer game (Terasology) with a single-player game (DestinationSol) through a shared backend — demonstrating that even solo experiences can participate in a cross-game social layer.

The approach is analogous to games like Dark Souls, where single-player sessions have an online component (player hints, invasions) without traditional multiplayer.

## Architecture

```
┌─────────────────────┐         ┌─────────────────┐
│     Terasology      │         │ DestinationSol  │
│                     │         │                 │
│ NakamaSubSystem     │         │ NakamaClient     │
│  ├─ device auth     │         │  ├─ device auth  │
│  ├─ join channel    │         │  ├─ join channel │
│  └─ bridge:         │         │  └─ bridge:      │
│    chat events ↔    │         │    console ↔     │
│    nakama channel   │         │    nakama channel│
└────────┬────────────┘         └────────┬────────┘
         │ gRPC                          │ gRPC
         └───────────┐   ┌──────────────┘
                     ▼   ▼
              ┌──────────────┐
              │    Nakama    │
              │   (Nordri)   │
              │              │
              │ chat channel:│
              │ bifrost.lobby│
              └──────┬───────┘
                     │
                  ┌──┴──┐
                  │ PG  │
                  └─────┘
```

Three components:

- **Nakama on Nordri** — basic k8s Deployment + Service with PostgreSQL. Chat channel `bifrost.lobby` is created implicitly when the first client joins.
- **NakamaSubSystem (Terasology)** — optional engine subsystem (similar to DiscordRPCSubSystem). Bridges Gestalt chat events to/from a Nakama channel.
- **NakamaClient (DestinationSol)** — lightweight integration class. Connects on game startup, bridges console input and banner display to the Nakama channel.

## Message Flow

Both games join a Nakama chat channel of type "room" named `bifrost.lobby`. Room channels are open — any authenticated user can join without invitation. Nakama handles fan-out to all subscribers.

### Message format

Plain JSON in Nakama's channel message content field:

```json
{
  "game": "terasology",
  "player": "Alice",
  "text": "Greetings from the voxel world!"
}
```

The `game` field is used for display prefixing and echo filtering (each game ignores messages where `game` matches its own identifier).

### Terasology (inbound)

Incoming messages appear in the existing chat window:

```
[DS] Bob: Read you loud and clear.
```

The NakamaSubSystem injects a Nakama-sourced chat message into the chat system. These messages are tagged internally so the subsystem can distinguish them from locally-originated chat and avoid re-forwarding them outbound. No UI changes needed.

### Terasology (outbound)

The NakamaSubSystem listens for Gestalt chat events, skips any tagged as Nakama-sourced, and forwards the rest to the Nakama channel with `game: "terasology"` and the player's name.

### DestinationSol (inbound)

Incoming messages appear as banner announcements (the same system used for gameplay notifications):

```
[TS] Alice: Greetings from the voxel world!
```

Banners are temporary overlays that fade after a few seconds. For a demo this is ideal — messages appear dramatically over the gameplay.

### DestinationSol (outbound)

A new console command `/say` sends text to the Nakama channel:

```
/say Read you loud and clear.
```

### Echo filtering

Each game ignores messages where `game` matches its own identifier. This prevents the sender seeing their own message twice (once local, once from Nakama broadcast).

### Connection lifecycle

- Connect and authenticate on game startup (if enabled via config flag)
- Join channel immediately after auth
- Maintain connection for game lifetime
- No reconnection logic for POC (restart game if connection drops)
- If Nakama is unreachable at startup, log a warning and continue — the game works normally without the connection

## Authentication

Device authentication for the POC. Each game instance gets a stable device ID (UUID persisted in a local config file). No accounts, no passwords. Nakama creates user records automatically on first connection.

### Player display name

- **Terasology**: Uses the player's existing in-game name.
- **DestinationSol**: Set via config (`nakama.player_name=Bob`). DS has no concept of a player name, so this is provided explicitly. Falls back to a truncated device ID if not configured.

## Deployment

### Nakama on Nordri

Minimal k8s manifests stored in the bifrost repo (e.g. `k8s/nakama-poc/`):

- `postgres.yaml` — single-replica Deployment + Service with a PVC. Credentials (`nakama` user, `nakama_db` database) set via environment variables; password in a k8s Secret.
- `nakama.yaml` — single-replica Deployment + Service (image: `heroiclabs/nakama:3.25.0` or latest 3.x), configured via environment variables to connect to PostgreSQL. Exposes gRPC (7349) port.
- No Ingress — both games connect directly via NodePort or cluster IP on the LAN.

### Terasology configuration

A config file (e.g. `nakama.cfg` or a section in an existing engine config):

```
nakama.enabled=true
nakama.host=192.168.x.x
nakama.port=7349
nakama.channel=bifrost.lobby
```

The subsystem checks `nakama.enabled` on startup and skips initialization if false. No impact on normal gameplay when disabled.

### DestinationSol configuration

Same pattern:

```
nakama.enabled=true
nakama.host=192.168.x.x
nakama.port=7349
nakama.channel=bifrost.lobby
```

If disabled or missing, DS behaves exactly as it does today.

### Nakama Java SDK

The Nakama Java SDK (`com.heroiclabs.nakama:nakama-java`) uses gRPC as its transport protocol. Both games connect to Nakama's gRPC port (7349).

- TS: added to the engine's `build.gradle` (subsystems are engine-level, not module-level)
- DS: added to the project's `build.gradle`
- Both pin the same SDK version, compatible with the deployed Nakama server version

## Scope boundaries

In scope:
- Bidirectional real-time chat between TS and DS via Nakama
- Device authentication
- Basic k8s deployment manifests
- Config-gated opt-in in both games

Not in scope:
- TLS/encryption (local network)
- Reconnection or retry logic
- User-facing settings UI
- Helm chart or ArgoCD integration
- Persistent chat history
- Item linking or transfer

## Stretch goals

### Tier B: Item link display

Alice shift-clicks an item in TS. The NakamaSubSystem serializes item metadata into the channel message:

```json
{
  "game": "terasology",
  "player": "Alice",
  "text": "Check out my pet!",
  "item_link": {
    "name": "Gelatinous Cube",
    "description": "A bouncy green slime friend.",
    "icon_hint": "slime_green"
  }
}
```

DS renders the banner with the item name highlighted. A console command (`/inspect`) shows the description. Read-only, no spawning.

### Tier C: Item materialize

DS interprets `item_link` data and spawns a generic cargo/stasis pod item in the player's inventory. The pod carries the original metadata as display-only properties.

## Future investigation (not designed here)

These Nakama features map well to the legacy Terasology meta server and are worth investigating separately:

- **Module index**: Nakama storage collections (public read, server-authoritative write) could replace the legacy web endpoint for available module versions.
- **Server listing**: Storage or matchmaking API with heartbeat-based expiry could replace the legacy server list.
- **Player identity**: Account linking (device, email, Steam, custom ID) could provide portable player identity across machines.
- **World-bound persistence**: Nakama storage with TTL for the "Baton" transfer pattern described in `components/bifrost/with-nakama-and-agones.md`.

## Demo scenario

Both games running side-by-side on one screen, connected to a Nakama instance on the Nordri cluster.

1. Alice types in Terasology chat: "Greetings from the voxel world!"
2. Bob sees the message as a banner in DestinationSol's HUD.
3. Bob opens the DS console, types `/say Read you loud and clear.`
4. Alice sees `[DS] Bob: Read you loud and clear.` in her TS chat window.

Capture as side-by-side screenshots or a short screen recording.
