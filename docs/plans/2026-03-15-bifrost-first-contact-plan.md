# Bifrost "First Contact" Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bidirectional real-time chat between Terasology and DestinationSol via a shared Nakama server, proving cross-game connectivity without multiplayer in DS.

**Architecture:** Three components — Nakama deployed on Nordri (k8s), a NakamaSubSystem in the Terasology engine bridging Gestalt chat events, and a NakamaClient in DestinationSol bridging the game console and banner display. Both games use the Nakama Java SDK with gRPC transport and device authentication.

**Tech Stack:** Nakama 3.x (Go), PostgreSQL, Nakama Java SDK (`com.heroiclabs.nakama:nakama-java`), Kubernetes (Nordri), Terasology (Java/LWJGL/Gestalt), DestinationSol (Java/LibGDX/Gestalt)

**Spec:** `docs/plans/2026-03-14-bifrost-first-contact-design.md`

---

## Chunk 1: Nakama Deployment

### Task 1: Create k8s manifests for PostgreSQL

**Files:**
- Create: `components/bifrost/k8s/nakama-poc/postgres.yaml`

- [ ] **Step 1: Create the PostgreSQL manifest**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nakama-poc
---
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: nakama-poc
type: Opaque
stringData:
  POSTGRES_USER: nakama
  POSTGRES_PASSWORD: nakama-poc-local
  POSTGRES_DB: nakama_db
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: nakama-poc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: nakama-poc
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports:
            - containerPort: 5432
          envFrom:
            - secretRef:
                name: postgres-credentials
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: postgres-data
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: nakama-poc
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
```

- [ ] **Step 2: Apply and verify PostgreSQL is running**

```bash
kubectl apply -f components/bifrost/k8s/nakama-poc/postgres.yaml
kubectl -n nakama-poc wait --for=condition=available deployment/postgres --timeout=120s
kubectl -n nakama-poc get pods
```

Expected: Pod in Running state.

- [ ] **Step 3: Commit**

```bash
cd components/bifrost
git add k8s/nakama-poc/postgres.yaml
git commit -m "feat: add PostgreSQL k8s manifest for Nakama POC"
```

### Task 2: Create k8s manifests for Nakama

**Files:**
- Create: `components/bifrost/k8s/nakama-poc/nakama.yaml`

- [ ] **Step 1: Create the Nakama manifest**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nakama
  namespace: nakama-poc
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nakama
  template:
    metadata:
      labels:
        app: nakama
    spec:
      initContainers:
        - name: migrate
          image: heroiclabs/nakama:3.25.0
          command: ["/nakama/nakama"]
          args:
            - "migrate"
            - "up"
            - "--database.address=nakama:nakama-poc-local@postgres:5432/nakama_db"
      containers:
        - name: nakama
          image: heroiclabs/nakama:3.25.0
          ports:
            - containerPort: 7349
              name: grpc
            - containerPort: 7350
              name: http
            - containerPort: 7351
              name: console
          env:
            - name: NAKAMA_DATABASE__ADDRESS
              value: "nakama:nakama-poc-local@postgres:5432/nakama_db"
---
apiVersion: v1
kind: Service
metadata:
  name: nakama
  namespace: nakama-poc
spec:
  type: NodePort
  selector:
    app: nakama
  ports:
    - name: grpc
      port: 7349
      targetPort: 7349
    - name: http
      port: 7350
      targetPort: 7350
    - name: console
      port: 7351
      targetPort: 7351
```

- [ ] **Step 2: Apply and verify Nakama is running**

```bash
kubectl apply -f components/bifrost/k8s/nakama-poc/nakama.yaml
kubectl -n nakama-poc wait --for=condition=available deployment/nakama --timeout=120s
kubectl -n nakama-poc get pods
kubectl -n nakama-poc get svc nakama
```

Expected: Nakama pod Running. Note the NodePort assigned to gRPC (7349).

- [ ] **Step 3: Verify Nakama is reachable**

```bash
# Get the NodePort for the HTTP API
NAKAMA_PORT=$(kubectl -n nakama-poc get svc nakama -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
curl http://<nordri-node-ip>:$NAKAMA_PORT/healthcheck
```

Expected: HTTP 200 response.

- [ ] **Step 4: Commit**

```bash
cd components/bifrost
git add k8s/nakama-poc/nakama.yaml
git commit -m "feat: add Nakama k8s manifest for First Contact POC"
```

---

## Chunk 2: Terasology NakamaSubSystem

### Task 3: Create the subsystem project structure

**Files:**
- Create: `components/terasology/subsystems/Nakama/build.gradle.kts`

- [ ] **Step 1: Create the build file**

```kotlin
// Nakama subsystem - optional Bifrost integration
// Bridges Gestalt chat events to/from a Nakama chat channel

dependencies {
    implementation(project(":engine"))
    annotationProcessor(libs.gestalt.injectjava)
    api("com.heroiclabs.nakama:nakama-java:2.+") // gRPC-based Java SDK
}
```

Note: The `subsystems/` directory has a `subprojects.settings.gradle.kts` that auto-discovers subdirectories, so no settings change is needed. Verify the exact latest nakama-java SDK version on Maven Central before using.

- [ ] **Step 2: Verify the project is picked up by Gradle**

```bash
cd components/terasology
./gradlew projects 2>&1 | grep -i nakama
```

Expected: `:subsystems:Nakama` appears in the project list.

- [ ] **Step 3: Commit**

```bash
cd components/terasology
git add subsystems/Nakama/
git commit -m "feat: add Nakama subsystem project skeleton"
```

### Task 4: Implement NakamaSubSystem

**Files:**
- Create: `components/terasology/subsystems/Nakama/src/main/java/org/terasology/subsystem/nakama/NakamaSubSystem.java`
- Create: `components/terasology/subsystems/Nakama/src/main/java/org/terasology/subsystem/nakama/NakamaConfig.java`

Reference: `components/terasology/subsystems/DiscordRPC/src/main/java/org/terasology/subsystem/discordrpc/DiscordRPCSubSystem.java` for the subsystem pattern.

- [ ] **Step 1: Write a test for NakamaConfig**

Create: `components/terasology/subsystems/Nakama/src/test/java/org/terasology/subsystem/nakama/NakamaConfigTest.java`

```java
package org.terasology.subsystem.nakama;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class NakamaConfigTest {
    @Test
    void defaultsAreDisabled() {
        NakamaConfig config = new NakamaConfig();
        assertFalse(config.isEnabled());
        assertEquals("bifrost.lobby", config.getChannel());
        assertEquals(7349, config.getPort());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd components/terasology
./gradlew :subsystems:Nakama:test
```

Expected: FAIL — class not found.

- [ ] **Step 3: Implement NakamaConfig**

```java
package org.terasology.subsystem.nakama;

/**
 * Configuration for the Nakama subsystem.
 * Read from nakama.cfg in the game's home directory.
 */
public class NakamaConfig {
    private boolean enabled = false;
    private String host = "localhost";
    private int port = 7349;
    private String channel = "bifrost.lobby";
    private String playerName = "";

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }

    public String getHost() { return host; }
    public void setHost(String host) { this.host = host; }

    public int getPort() { return port; }
    public void setPort(int port) { this.port = port; }

    public String getChannel() { return channel; }
    public void setChannel(String channel) { this.channel = channel; }

    public String getPlayerName() { return playerName; }
    public void setPlayerName(String playerName) { this.playerName = playerName; }

    /**
     * Load config from system properties (nakama.enabled, nakama.host, etc.)
     * Falls back to defaults if not set.
     */
    public static NakamaConfig fromSystemProperties() {
        NakamaConfig config = new NakamaConfig();
        config.setEnabled(Boolean.parseBoolean(System.getProperty("nakama.enabled", "false")));
        config.setHost(System.getProperty("nakama.host", "localhost"));
        config.setPort(Integer.parseInt(System.getProperty("nakama.port", "7349")));
        config.setChannel(System.getProperty("nakama.channel", "bifrost.lobby"));
        config.setPlayerName(System.getProperty("nakama.playerName", ""));
        return config;
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd components/terasology
./gradlew :subsystems:Nakama:test
```

Expected: PASS.

- [ ] **Step 5: Implement NakamaSubSystem**

```java
package org.terasology.subsystem.nakama;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.heroiclabs.nakama.Client;
import com.heroiclabs.nakama.DefaultClient;
import com.heroiclabs.nakama.Session;
import com.heroiclabs.nakama.SocketClient;
import com.heroiclabs.nakama.api.ChannelMessage;
import com.heroiclabs.nakama.Channel;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.terasology.engine.context.Context;
import org.terasology.engine.core.GameEngine;
import org.terasology.engine.core.subsystem.EngineSubsystem;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Map;
import java.util.UUID;
import java.util.function.Consumer;

/**
 * Optional engine subsystem that bridges Terasology chat to a Nakama
 * chat channel, enabling cross-game messaging for the Bifrost protocol.
 *
 * Enable via system property: -Dnakama.enabled=true -Dnakama.host=192.168.x.x
 */
public class NakamaSubSystem implements EngineSubsystem {
    private static final Logger logger = LoggerFactory.getLogger(NakamaSubSystem.class);
    private static final String GAME_ID = "terasology";
    private static final Map<String, String> GAME_PREFIXES = Map.of(
            "terasology", "TS", "destinationsol", "DS", "minecraft", "MC"
    );

    private NakamaConfig config;
    private Client client;
    private Session session;
    private SocketClient socket;
    private Channel channel;

    // Callback for incoming messages — set by the engine/module that handles chat display
    private Consumer<String> incomingMessageHandler;

    // Flag to prevent re-forwarding messages we injected
    private volatile boolean suppressOutbound = false;

    @Override
    public String getName() {
        return "Nakama";
    }

    @Override
    public void initialise(GameEngine engine, Context rootContext) {
        config = NakamaConfig.fromSystemProperties();
        if (!config.isEnabled()) {
            logger.info("Nakama subsystem disabled (set -Dnakama.enabled=true to enable)");
            return;
        }
        connect();
    }

    private void connect() {
        try {
            String deviceId = getOrCreateDeviceId();
            client = new DefaultClient("defaultkey", config.getHost(), config.getPort(), false);
            session = client.authenticateDevice(deviceId).get();
            logger.info("Nakama: authenticated as {}", session.getUserId());

            socket = client.createSocket();
            socket.connect(session, new com.heroiclabs.nakama.AbstractSocketListener() {
                @Override
                public void onChannelMessage(ChannelMessage message) {
                    handleIncomingMessage(message);
                }
            }).get();

            // Join the shared chat channel
            channel = socket.joinChat(config.getChannel(), com.heroiclabs.nakama.ChannelType.ROOM).get();
            logger.info("Nakama: joined channel '{}'", config.getChannel());

        } catch (Exception e) {
            logger.warn("Nakama: connection failed, continuing without cross-game chat", e);
            cleanup();
        }
    }

    private void handleIncomingMessage(ChannelMessage message) {
        try {
            JsonObject content = JsonParser.parseString(message.getContent()).getAsJsonObject();
            String game = content.has("game") ? content.get("game").getAsString() : "";
            // Echo filter: ignore our own game's messages
            if (GAME_ID.equals(game)) {
                return;
            }
            String player = content.has("player") ? content.get("player").getAsString() : "???";
            String text = content.has("text") ? content.get("text").getAsString() : "";
            String prefix = "[" + GAME_PREFIXES.getOrDefault(game, game.toUpperCase().substring(0, Math.min(game.length(), 2))) + "]";
            String formatted = prefix + " " + player + ": " + text;

            if (incomingMessageHandler != null) {
                suppressOutbound = true;
                try {
                    incomingMessageHandler.accept(formatted);
                } finally {
                    suppressOutbound = false;
                }
            }
        } catch (Exception e) {
            logger.warn("Nakama: failed to parse incoming message", e);
        }
    }

    /**
     * Send a chat message to the Nakama channel.
     * Called by the chat system when a local player sends a message.
     * Returns true if the message was sent, false if suppressed or not connected.
     */
    public boolean sendChatMessage(String playerName, String text) {
        if (suppressOutbound || socket == null || channel == null) {
            return false;
        }
        try {
            JsonObject content = new JsonObject();
            content.addProperty("game", GAME_ID);
            content.addProperty("player", playerName);
            content.addProperty("text", text);
            socket.writeChatMessage(channel.getId(), content.toString()).get();
            return true;
        } catch (Exception e) {
            logger.warn("Nakama: failed to send message", e);
            return false;
        }
    }

    /**
     * Register a handler for incoming cross-game messages.
     * The handler receives a pre-formatted string like "[DS] Bob: Hello"
     */
    public void setIncomingMessageHandler(Consumer<String> handler) {
        this.incomingMessageHandler = handler;
    }

    public boolean isConnected() {
        return socket != null && channel != null;
    }

    @Override
    public void preShutdown() {
        cleanup();
    }

    private void cleanup() {
        if (socket != null) {
            try { socket.disconnect(); } catch (Exception ignored) {}
            socket = null;
        }
        channel = null;
        session = null;
        client = null;
    }

    private String getOrCreateDeviceId() {
        String id = System.getProperty("nakama.deviceId", "");
        if (!id.isEmpty()) {
            return id;
        }
        // Persist device ID to a file so we get the same Nakama user across restarts
        Path idFile = Paths.get(System.getProperty("user.home"), ".bifrost", "device-id");
        try {
            if (Files.exists(idFile)) {
                id = Files.readString(idFile).trim();
                if (!id.isEmpty()) {
                    return id;
                }
            }
            id = UUID.randomUUID().toString();
            Files.createDirectories(idFile.getParent());
            Files.writeString(idFile, id);
            logger.info("Nakama: created device ID {}", id);
        } catch (IOException e) {
            id = UUID.randomUUID().toString();
            logger.warn("Nakama: could not persist device ID, using ephemeral {}", id);
        }
        return id;
    }
}
```

**Notes for the implementer:**
- The Nakama Java SDK API may differ slightly by version. Check the SDK Javadoc for exact class/method signatures if compilation fails. Pin to a specific version (e.g. `2.9.1`) rather than `2.+` if stability is needed.
- The `suppressOutbound` flag is a simple POC approach to prevent echo loops. For production, use a proper event tag on injected messages.

- [ ] **Step 6: Commit**

```bash
cd components/terasology
git add subsystems/Nakama/
git commit -m "feat: implement NakamaSubSystem with chat bridge"
```

### Task 5: Register the subsystem in the engine

**Files:**
- Modify: `components/terasology/facades/PC/src/main/java/org/terasology/engine/Terasology.java` (in `populateSubsystems()`)
- Modify: `components/terasology/engine/src/main/java/org/terasology/engine/core/TerasologyEngine.java` (in `LEGACY_MODULE_POLLUTERS`)

- [ ] **Step 1: Add NakamaSubSystem to the PC facade**

In `Terasology.java`, find the `populateSubsystems()` method (around line 316). Add alongside the DiscordRPC line:

```java
builder.add(new org.terasology.subsystem.nakama.NakamaSubSystem());
```

- [ ] **Step 2: Add to LEGACY_ENGINE_MODULE_POLLUTERS**

In `TerasologyEngine.java`, find the `LEGACY_ENGINE_MODULE_POLLUTERS` set (around line 113). Add the NakamaSubSystem class name alongside the existing DiscordRPC entry:

```java
private static final Set<String> LEGACY_ENGINE_MODULE_POLLUTERS = Set.of(
        "org.terasology.subsystem.discordrpc.DiscordRPCSubSystem",
        "org.terasology.subsystem.nakama.NakamaSubSystem"
);
```

- [ ] **Step 3: Create NakamaSystem entity system for chat bridge**

Create: `components/terasology/subsystems/Nakama/src/main/java/org/terasology/subsystem/nakama/NakamaSystem.java`

The subsystem itself cannot use `@ReceiveEvent` (that's for entity systems). Following the DiscordRPC pattern, we create a `NakamaSystem` registered via `registerSystems()` that handles the Gestalt event bus integration.

```java
package org.terasology.subsystem.nakama;

import org.terasology.engine.entitySystem.entity.EntityRef;
import org.terasology.engine.entitySystem.systems.BaseComponentSystem;
import org.terasology.engine.entitySystem.systems.RegisterSystem;
import org.terasology.engine.logic.chat.ChatMessageEvent;
import org.terasology.engine.network.ClientComponent;
import org.terasology.gestalt.entitysystem.event.ReceiveEvent;

/**
 * Entity system that bridges Gestalt chat events to the NakamaSubSystem.
 * Registered via NakamaSubSystem.registerSystems().
 */
@RegisterSystem
public class NakamaSystem extends BaseComponentSystem {
    private NakamaSubSystem nakamaSubSystem;

    public void setNakamaSubSystem(NakamaSubSystem subsystem) {
        this.nakamaSubSystem = subsystem;
    }

    @ReceiveEvent(components = ClientComponent.class)
    public void onChatMessage(ChatMessageEvent event, EntityRef entity) {
        if (nakamaSubSystem != null && nakamaSubSystem.isConnected()) {
            String playerName = event.getFrom().toString(); // Simplified — get display name from entity
            nakamaSubSystem.sendChatMessage(playerName, event.getMessage());
        }
    }
}
```

Then add `registerSystems()` to `NakamaSubSystem`:

```java
@Override
public void registerSystems(ComponentSystemManager componentSystemManager) {
    if (config != null && config.isEnabled()) {
        NakamaSystem nakamaSystem = new NakamaSystem();
        nakamaSystem.setNakamaSubSystem(this);
        componentSystemManager.register(nakamaSystem);
    }
}
```

And wire inbound messages in `postInitialise()`:

```java
@Override
public void postInitialise(Context context) {
    if (config == null || !config.isEnabled() || !isConnected()) {
        return;
    }
    // Inbound: inject Nakama messages into the local chat system
    // The LocalPlayer and chat display are now available via context
    setIncomingMessageHandler(formatted -> {
        // Send as a console message or inject via ChatMessageEvent
        // For POC, log to the in-game console
        logger.info("Nakama chat: {}", formatted);
        // TODO: Inject into the NUI chat widget. For the POC, the message
        // will appear in the game log. Full chat injection requires accessing
        // the NUI ChatBox or sending a synthetic ChatMessageEvent.
    });
}
```

**Note for implementer:** The exact mechanism to inject a message into the Terasology chat UI depends on whether the NUI chat widget has a public API for adding messages. Search for `ChatBox` or `ChatScreen` in the engine NUI screens. If direct injection is complex, the inbound messages can be displayed via the game console (`Console` in the engine context) as a POC fallback — the outbound direction (capturing local chat via `@ReceiveEvent`) is the higher-value integration.

- [ ] **Step 4: Build the full engine to verify compilation**

```bash
cd components/terasology
./gradlew :facades:PC:build
```

Expected: BUILD SUCCESS. No runtime test yet — that requires the Nakama server.

- [ ] **Step 5: Commit**

```bash
cd components/terasology
git add facades/PC/src/ engine/src/
git commit -m "feat: register NakamaSubSystem in engine startup"
```

---

## Chunk 3: DestinationSol NakamaClient

### Task 6: Add Nakama SDK dependency

**Files:**
- Modify: `components/destinationsol/engine/build.gradle`

- [ ] **Step 1: Add the Nakama Java SDK dependency**

In `engine/build.gradle`, add to the `dependencies` block:

```groovy
implementation 'com.heroiclabs.nakama:nakama-java:2.+'
```

Verify the exact latest version on Maven Central. The SDK pulls in gRPC and Protobuf transitively — check for conflicts with DS's existing Protobuf dependency.

- [ ] **Step 2: Verify the dependency resolves**

```bash
cd components/destinationsol
./gradlew :engine:dependencies | grep nakama
```

Expected: nakama-java appears in the dependency tree.

- [ ] **Step 3: Commit**

```bash
cd components/destinationsol
git add engine/build.gradle
git commit -m "feat: add Nakama Java SDK dependency"
```

### Task 7: Implement NakamaClient

**Files:**
- Create: `components/destinationsol/engine/src/main/java/org/destinationsol/game/chat/NakamaClient.java`
- Create: `components/destinationsol/engine/src/main/java/org/destinationsol/game/chat/NakamaConfig.java`

- [ ] **Step 1: Write a test for NakamaConfig**

Create: `components/destinationsol/engine/src/test/java/org/destinationsol/game/chat/NakamaConfigTest.java`

```java
package org.destinationsol.game.chat;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class NakamaConfigTest {
    @Test
    void defaultsAreDisabled() {
        NakamaConfig config = new NakamaConfig();
        assertFalse(config.isEnabled());
        assertEquals("bifrost.lobby", config.getChannel());
        assertEquals(7349, config.getPort());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd components/destinationsol
./gradlew :engine:test --tests "org.destinationsol.game.chat.NakamaConfigTest"
```

Expected: FAIL — class not found.

- [ ] **Step 3: Implement NakamaConfig**

```java
package org.destinationsol.game.chat;

/**
 * Configuration for the Nakama client integration.
 * Read from system properties for the POC.
 */
public class NakamaConfig {
    private boolean enabled = false;
    private String host = "localhost";
    private int port = 7349;
    private String channel = "bifrost.lobby";
    private String playerName = "";

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }

    public String getHost() { return host; }
    public void setHost(String host) { this.host = host; }

    public int getPort() { return port; }
    public void setPort(int port) { this.port = port; }

    public String getChannel() { return channel; }
    public void setChannel(String channel) { this.channel = channel; }

    public String getPlayerName() { return playerName; }
    public void setPlayerName(String name) { this.playerName = name; }

    public static NakamaConfig fromSystemProperties() {
        NakamaConfig config = new NakamaConfig();
        config.setEnabled(Boolean.parseBoolean(System.getProperty("nakama.enabled", "false")));
        config.setHost(System.getProperty("nakama.host", "localhost"));
        config.setPort(Integer.parseInt(System.getProperty("nakama.port", "7349")));
        config.setChannel(System.getProperty("nakama.channel", "bifrost.lobby"));
        config.setPlayerName(System.getProperty("nakama.playerName", ""));
        return config;
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd components/destinationsol
./gradlew :engine:test --tests "org.destinationsol.game.chat.NakamaConfigTest"
```

Expected: PASS.

- [ ] **Step 5: Implement NakamaClient**

```java
package org.destinationsol.game.chat;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.heroiclabs.nakama.Client;
import com.heroiclabs.nakama.DefaultClient;
import com.heroiclabs.nakama.Session;
import com.heroiclabs.nakama.SocketClient;
import com.heroiclabs.nakama.api.ChannelMessage;
import com.heroiclabs.nakama.Channel;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentLinkedQueue;

/**
 * Lightweight Nakama integration for DestinationSol.
 * Connects to a shared chat channel for cross-game messaging.
 *
 * Enable via: -Dnakama.enabled=true -Dnakama.host=192.168.x.x -Dnakama.playerName=Bob
 */
public class NakamaClient {
    private static final Logger logger = LoggerFactory.getLogger(NakamaClient.class);
    private static final String GAME_ID = "destinationsol";
    private static final Map<String, String> GAME_PREFIXES = Map.of(
            "terasology", "TS", "destinationsol", "DS", "minecraft", "MC"
    );

    private final NakamaConfig config;
    private Client client;
    private Session session;
    private SocketClient socket;
    private Channel channel;

    // Thread-safe queue for incoming messages to be consumed on the game thread
    private final ConcurrentLinkedQueue<String> incomingMessages = new ConcurrentLinkedQueue<>();

    public NakamaClient(NakamaConfig config) {
        this.config = config;
    }

    /**
     * Connect to Nakama and join the chat channel.
     * Call during game startup. Non-blocking after initial connection.
     */
    public void connect() {
        if (!config.isEnabled()) {
            logger.info("Nakama client disabled");
            return;
        }
        try {
            String deviceId = getOrCreateDeviceId();
            client = new DefaultClient("defaultkey", config.getHost(), config.getPort(), false);
            session = client.authenticateDevice(deviceId).get();

            // Set display name if configured
            if (!config.getPlayerName().isEmpty()) {
                client.updateAccount(session, null, config.getPlayerName()).get();
            }

            logger.info("Nakama: authenticated as {}", session.getUserId());

            socket = client.createSocket();
            socket.connect(session, new com.heroiclabs.nakama.AbstractSocketListener() {
                @Override
                public void onChannelMessage(ChannelMessage message) {
                    handleIncomingMessage(message);
                }
            }).get();

            channel = socket.joinChat(config.getChannel(), com.heroiclabs.nakama.ChannelType.ROOM).get();
            logger.info("Nakama: joined channel '{}'", config.getChannel());

        } catch (Exception e) {
            logger.warn("Nakama: connection failed, continuing without cross-game chat", e);
            cleanup();
        }
    }

    private void handleIncomingMessage(ChannelMessage message) {
        try {
            JsonObject content = JsonParser.parseString(message.getContent()).getAsJsonObject();
            String game = content.has("game") ? content.get("game").getAsString() : "";
            if (GAME_ID.equals(game)) {
                return; // Echo filter
            }
            String player = content.has("player") ? content.get("player").getAsString() : "???";
            String text = content.has("text") ? content.get("text").getAsString() : "";
            String prefix = "[" + GAME_PREFIXES.getOrDefault(game, game.toUpperCase().substring(0, Math.min(game.length(), 2))) + "]";
            String formatted = prefix + " " + player + ": " + text;
            incomingMessages.add(formatted);
        } catch (Exception e) {
            logger.warn("Nakama: failed to parse incoming message", e);
        }
    }

    /**
     * Send a chat message. Called from the /say console command.
     */
    public boolean sendMessage(String text) {
        if (socket == null || channel == null) {
            return false;
        }
        try {
            String playerName = config.getPlayerName().isEmpty()
                    ? session.getUserId().substring(0, 8)
                    : config.getPlayerName();

            JsonObject content = new JsonObject();
            content.addProperty("game", GAME_ID);
            content.addProperty("player", playerName);
            content.addProperty("text", text);
            socket.writeChatMessage(channel.getId(), content.toString()).get();
            return true;
        } catch (Exception e) {
            logger.warn("Nakama: failed to send message", e);
            return false;
        }
    }

    /**
     * Poll for incoming messages. Call from the game loop.
     * Returns null if no messages are pending.
     */
    public String pollMessage() {
        return incomingMessages.poll();
    }

    public boolean isConnected() {
        return socket != null && channel != null;
    }

    public void disconnect() {
        cleanup();
    }

    private void cleanup() {
        if (socket != null) {
            try { socket.disconnect(); } catch (Exception ignored) {}
            socket = null;
        }
        channel = null;
        session = null;
        client = null;
    }

    private String getOrCreateDeviceId() {
        String id = System.getProperty("nakama.deviceId", "");
        if (!id.isEmpty()) {
            return id;
        }
        Path idFile = Paths.get(System.getProperty("user.home"), ".bifrost", "device-id");
        try {
            if (Files.exists(idFile)) {
                id = Files.readString(idFile).trim();
                if (!id.isEmpty()) {
                    return id;
                }
            }
            id = UUID.randomUUID().toString();
            Files.createDirectories(idFile.getParent());
            Files.writeString(idFile, id);
            logger.info("Nakama: created device ID {}", id);
        } catch (IOException e) {
            id = UUID.randomUUID().toString();
            logger.warn("Nakama: could not persist device ID, using ephemeral {}", id);
        }
        return id;
    }
}
```

- [ ] **Step 6: Commit**

```bash
cd components/destinationsol
git add engine/src/main/java/org/destinationsol/game/chat/
git add engine/src/test/java/org/destinationsol/game/chat/
git commit -m "feat: implement NakamaClient with chat channel support"
```

### Task 8: Implement the /say console command

**Files:**
- Create: `components/destinationsol/engine/src/main/java/org/destinationsol/game/chat/SayCommandHandler.java`

Reference: `components/destinationsol/engine/src/main/java/org/destinationsol/game/console/commands/ChangeShipCommandHandler.java` for the command pattern.

- [ ] **Step 1: Implement the command handler**

```java
package org.destinationsol.game.chat;

import org.destinationsol.game.console.annotations.Command;
import org.destinationsol.game.console.annotations.CommandParam;
import org.destinationsol.game.console.annotations.RegisterCommands;

/**
 * Console command for sending chat messages via Nakama.
 * Usage: say "Hello from space!"
 *
 * Note: The DS console splits on spaces but preserves quoted strings.
 * Multi-word messages must be quoted: say "Read you loud and clear."
 */
@RegisterCommands
public class SayCommandHandler {

    private static NakamaClient nakamaClient;

    public static void setNakamaClient(NakamaClient client) {
        nakamaClient = client;
    }

    @Command(shortDescription = "Send a message to the Bifrost chat channel")
    public String say(@CommandParam(value = "message") String message) {
        if (nakamaClient == null || !nakamaClient.isConnected()) {
            return "Nakama not connected. Enable with -Dnakama.enabled=true";
        }
        boolean sent = nakamaClient.sendMessage(message);
        return sent ? "Sent: " + message : "Failed to send message";
    }
}
```

**Note for implementer:** The DS console parser splits on spaces but preserves quoted strings (via `PARAM_SPLIT_REGEX` in `ConsoleImpl`). Users must quote multi-word messages: `say "Read you loud and clear."` The quotes are stripped automatically before the parameter reaches the handler.

- [ ] **Step 2: Commit**

```bash
cd components/destinationsol
git add engine/src/main/java/org/destinationsol/game/chat/SayCommandHandler.java
git commit -m "feat: add /say console command for Nakama chat"
```

### Task 9: Wire NakamaClient into DS game startup and display

**Files:**
- Modify: `components/destinationsol/engine/src/main/java/org/destinationsol/SolApplication.java`

- [ ] **Step 1: Initialize NakamaClient on game startup**

In `SolApplication.create()` (or an appropriate initialization point after the module system is loaded), add:

```java
// Nakama integration (optional, POC)
NakamaConfig nakamaConfig = NakamaConfig.fromSystemProperties();
if (nakamaConfig.isEnabled()) {
    NakamaClient nakamaClient = new NakamaClient(nakamaConfig);
    nakamaClient.connect();
    SayCommandHandler.setNakamaClient(nakamaClient);
    // Store reference for game loop polling and shutdown
    this.nakamaClient = nakamaClient;
}
```

Add a field `private NakamaClient nakamaClient;` to the class.

- [ ] **Step 2: Poll for incoming messages in the game loop**

In the `update()` method of SolApplication (around line 256), add message polling. Messages go to both the console (for history) and trigger a banner overlay (for dramatic display during gameplay):

```java
if (nakamaClient != null && nakamaClient.isConnected()) {
    String msg;
    while ((msg = nakamaClient.pollMessage()) != null) {
        // Log to console for history
        if (solGame != null && solGame.getConsole() != null) {
            solGame.getConsole().addMessage(msg);
        }
        // Update the banner for dramatic overlay display
        lastNakamaMessage = msg;
        nakamaMessageTimer = 5.0f; // Show for 5 seconds
    }
}
// Fade the banner timer
if (nakamaMessageTimer > 0) {
    nakamaMessageTimer -= Const.REAL_TIME_STEP;
}
```

Add fields to SolApplication:

```java
private String lastNakamaMessage = "";
private float nakamaMessageTimer = 0f;
```

For the banner overlay, the simplest POC approach is to add a NUI WarnDrawer to the MainGameScreen. In the NUI-based MainGameScreen, use `addWarnDrawer()`:

```java
// In MainGameScreen initialization (or wherever warn drawers are added):
addWarnDrawer("nakamaChat", warnColour, "", new ReadOnlyBinding<Boolean>() {
    @Override
    public Boolean get() {
        return solApplication.getNakamaMessageTimer() > 0;
    }
});
```

Alternatively, if accessing the NUI screen from SolApplication is complex, the console display alone is sufficient for the POC — the console is always visible during gameplay and messages will appear there. The banner is a visual enhancement for the demo.

- [ ] **Step 3: Disconnect on shutdown**

In the `dispose()` method:

```java
if (nakamaClient != null) {
    nakamaClient.disconnect();
}
```

- [ ] **Step 4: Build and verify compilation**

```bash
cd components/destinationsol
./gradlew :engine:build
```

Expected: BUILD SUCCESS.

- [ ] **Step 5: Commit**

```bash
cd components/destinationsol
git add engine/src/
git commit -m "feat: wire NakamaClient into DS startup with console display"
```

---

## Chunk 4: Integration Testing

### Task 10: Manual integration test

This task is entirely manual — verifying the end-to-end flow.

- [ ] **Step 1: Confirm Nakama is running on Nordri**

```bash
kubectl -n nakama-poc get pods
```

Expected: Both `postgres` and `nakama` pods are Running.

Note the Nakama node IP and gRPC NodePort:
```bash
NAKAMA_IP=<nordri-node-ip>
NAKAMA_GRPC_PORT=$(kubectl -n nakama-poc get svc nakama -o jsonpath='{.spec.ports[?(@.name=="grpc")].nodePort}')
echo "Nakama gRPC: $NAKAMA_IP:$NAKAMA_GRPC_PORT"
```

- [ ] **Step 2: Launch Terasology with Nakama enabled**

```bash
cd components/terasology
./gradlew :facades:PC:run -Dnakama.enabled=true -Dnakama.host=$NAKAMA_IP -Dnakama.port=$NAKAMA_GRPC_PORT
```

Start or join a game world. Check the log for "Nakama: joined channel 'bifrost.lobby'".

- [ ] **Step 3: Launch DestinationSol with Nakama enabled**

```bash
cd components/destinationsol
./gradlew :desktop:run -Dnakama.enabled=true -Dnakama.host=$NAKAMA_IP -Dnakama.port=$NAKAMA_GRPC_PORT -Dnakama.playerName=Bob
```

Start a game. Check the log for "Nakama: joined channel 'bifrost.lobby'".

- [ ] **Step 4: Test TS → DS chat**

In Terasology, open chat and type: `Greetings from the voxel world!`

In DestinationSol, open the console. Verify the message appears:
```
[TS] Alice: Greetings from the voxel world!
```

- [ ] **Step 5: Test DS → TS chat**

In DestinationSol, open the console and type: `say "Read you loud and clear."`

In Terasology, verify the message appears in chat:
```
[DS] Bob: Read you loud and clear.
```

- [ ] **Step 6: Capture the demo**

Position both game windows side-by-side on screen. Send messages both ways and capture:
- Screenshots of both windows showing the cross-game chat
- Optionally, a short screen recording of the full exchange

- [ ] **Step 7: Document any adjustments needed**

Note any API mismatches, SDK version issues, or configuration changes discovered during testing. Update the design spec and this plan if needed.
