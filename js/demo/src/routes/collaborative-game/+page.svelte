<script lang="ts">
  import { resolve } from "$app/paths";
  import { onMount } from "svelte";
  import HistoryModal from "$lib/collaborative-editor/HistoryModal.svelte";
  import { loadMirage } from "$lib/mirage/client";
  import type { DeltaOp, Mirage, MirageDocument } from "@mirage/wasm";
  import type { LoadState } from "$lib/collaborative-editor/types";

  type ClientStatus = "alive" | "disconnected" | "winner";

  type Behavior = {
    name: string;
    progressWeight: number;
    riskWeight: number;
    targetWeight: number;
    holdScoreZone: number;
  };

  type GameClient = {
    id: number;
    name: string;
    color: string;
    doc: MirageDocument;
    x: number;
    y: number;
    targetX: number;
    phase: number;
    score: number;
    status: ClientStatus;
    behavior: Behavior;
  };

  type Platform = {
    id: number;
    x: number;
    y: number;
    width: number;
    speed: number;
  };

  type Cell = { char: string; color: string | null; ownerId: number | null };

  type LeaderboardRow = {
    id: number;
    name: string;
    color: string;
    score: number;
    status: ClientStatus;
    behavior: string;
  };

  const CLIENT_COUNT = 128;
  const MAP_COLUMNS = 64;
  const MAP_ROWS = 20;
  const SCORE_ROWS = 3;
  const MATCH_SECONDS = 30;
  const TICK_MS = 160;
  const CLIENT_SPEED = 9;
  const WAVE_INTERVAL = 1.45;
  const SCORE_LABEL = " score";
  const PLATFORM_COLOR = "#ef4444";
  const SCORE_COLOR = "#fde047";

  const palette = [
    "#22d3ee",
    "#fb7185",
    "#34d399",
    "#f59e0b",
    "#a78bfa",
    "#60a5fa",
    "#f472b6",
    "#bef264",
    "#f87171",
    "#2dd4bf",
    "#c084fc",
    "#fde047",
  ];

  const behaviors: Behavior[] = [
    {
      name: "runner",
      progressWeight: 3.4,
      riskWeight: 0.74,
      targetWeight: 0.08,
      holdScoreZone: 0.45,
    },
    {
      name: "cautious",
      progressWeight: 2.2,
      riskWeight: 1.42,
      targetWeight: 0.12,
      holdScoreZone: 0.8,
    },
    {
      name: "center",
      progressWeight: 2.7,
      riskWeight: 1.05,
      targetWeight: 0.22,
      holdScoreZone: 0.6,
    },
    {
      name: "edge",
      progressWeight: 2.5,
      riskWeight: 1.18,
      targetWeight: 0.18,
      holdScoreZone: 0.72,
    },
    {
      name: "weaver",
      progressWeight: 2.85,
      riskWeight: 1,
      targetWeight: 0.05,
      holdScoreZone: 0.58,
    },
  ];

  class MirageGameSession {
    readonly mainDoc: MirageDocument;
    readonly clients: GameClient[];
    readonly platforms: Platform[] = [];
    readonly snapshots: string[] = [];

    frame = 0;
    elapsed = 0;
    winnerId: number | null = null;

    private documentCells = createEmptyCells();
    private documentText = "";
    private winnerScreenLine = 0;
    private waveTimer = 0;
    private nextPlatformId = 1;
    private nextWaveId = 1;

    constructor(mirage: Mirage) {
      this.mainDoc = mirage.createDocument(0);
      this.documentText = createDocumentText(
        this.documentCells,
        this.elapsed,
        this.winnerId,
      );
      this.snapshots.push(this.documentText);
      this.mainDoc.insert(0, this.documentText);

      const seedUpdate = this.mainDoc.encodeUpdate();
      this.clients = Array.from({ length: CLIENT_COUNT }, (_, index) => {
        const id = index + 1;
        const doc = mirage.createDocument(id);
        const behavior = behaviors[index % behaviors.length];
        doc.applyUpdate(seedUpdate);

        return {
          id,
          name: `client-${String(id).padStart(3, "0")}`,
          color: palette[index % palette.length],
          doc,
          x: 1 + ((index * 9) % (MAP_COLUMNS - 2)),
          y: MAP_ROWS - 1 - (index % 4) * 0.55,
          targetX:
            behavior.name === "edge"
              ? index % 2 === 0
                ? 3
                : MAP_COLUMNS - 4
              : 4 + ((index * 17) % (MAP_COLUMNS - 8)),
          phase: hashFloat(id, 9) * Math.PI * 2,
          score: 0,
          status: "alive",
          behavior,
        };
      });

      this.applyGrid(this.nextGrid());
    }

    destroy(): void {
      this.mainDoc.destroy();
      for (const client of this.clients) {
        client.doc.destroy();
      }
    }

    tick(dt: number): void {
      if (this.winnerId !== null) {
        this.applyWinnerScreenLine();
        return;
      }

      const safeDt = Math.min(dt, Math.max(0, MATCH_SECONDS - this.elapsed));
      this.frame += 1;
      this.elapsed += safeDt;
      this.advancePlatforms(safeDt);
      this.advanceClients(safeDt);

      if (this.elapsed >= MATCH_SECONDS && this.winnerId === null) {
        this.finishByScore();
      }

      if (this.winnerId === null) {
        this.applyGrid(this.nextGrid());
      } else {
        this.applyWinnerScreenLine();
      }
    }

    documentDelta(): DeltaOp[] {
      return [{ insert: this.documentText }];
    }

    documentDeltaAt(snapshotIndex: number): DeltaOp[] {
      return [{ insert: this.snapshots[snapshotIndex] ?? this.documentText }];
    }

    leaderboard(limit = CLIENT_COUNT): LeaderboardRow[] {
      return [...this.clients]
        .sort((left, right) => {
          const statusRank =
            statusSortWeight(right.status) - statusSortWeight(left.status);
          return statusRank || right.score - left.score || left.id - right.id;
        })
        .slice(0, limit)
        .map(({ id, name, color, score, status, behavior }) => ({
          id,
          name,
          color,
          score,
          status,
          behavior: behavior.name,
        }));
    }

    activePlatformCount(): number {
      return this.platforms.length;
    }

    private advancePlatforms(dt: number): void {
      this.waveTimer -= dt;
      if (this.waveTimer <= 0) {
        this.spawnWave();
        this.waveTimer = WAVE_INTERVAL;
      }

      for (const platform of this.platforms) {
        platform.y += platform.speed * dt;
      }

      for (let index = this.platforms.length - 1; index >= 0; index -= 1) {
        if (this.platforms[index].y > MAP_ROWS + 1.5) {
          this.platforms.splice(index, 1);
        }
      }
    }

    private spawnWave(): void {
      const wave = this.nextWaveId;
      this.nextWaveId += 1;

      const gapWidth = 18 + (wave % 6);
      const sweep = wave % 8;
      const center =
        sweep < 4 ? 12 + sweep * 10 : MAP_COLUMNS - 13 - (sweep - 4) * 10;
      const gapStart = clamp(
        Math.round(center - gapWidth / 2),
        4,
        MAP_COLUMNS - 16,
      );
      const gapEnd = Math.min(MAP_COLUMNS - 5, gapStart + gapWidth);
      const speed = 2.45 + (wave % 4) * 0.18;

      this.addPlatform(0, gapStart - 2, speed);
      this.addPlatform(gapEnd + 2, MAP_COLUMNS - gapEnd - 2, speed);
    }

    private addPlatform(x: number, width: number, speed: number): void {
      if (width < 4) return;

      this.platforms.push({
        id: this.nextPlatformId,
        x,
        y: -0.8,
        width,
        speed,
      });
      this.nextPlatformId += 1;
    }

    private advanceClients(dt: number): void {
      for (const client of this.clients) {
        if (client.status !== "alive") continue;

        const move = this.chooseMove(client);
        const previousX = client.x;
        const previousY = client.y;
        const nextX = clamp(
          client.x + move.x * CLIENT_SPEED * dt,
          0,
          MAP_COLUMNS - 1,
        );
        const nextY = clamp(
          client.y + move.y * CLIENT_SPEED * dt,
          0,
          MAP_ROWS - 1,
        );

        if (this.pathHitsPlatform(previousX, previousY, nextX, nextY)) {
          client.x = nextX;
          client.y = nextY;
          client.status = "disconnected";
          continue;
        }

        client.x = nextX;
        client.y = nextY;

        if (client.y < SCORE_ROWS) {
          client.score += dt;
        }
      }
    }

    private finishByScore(): void {
      const candidates = this.clients.filter(
        (client) => client.status === "alive",
      );
      const pool = candidates.length > 0 ? candidates : this.clients;
      const winner = [...pool].sort(
        (a, b) => b.score - a.score || a.id - b.id,
      )[0];

      if (!winner) return;

      winner.status = "winner";
      this.winnerId = winner.id;
    }

    private chooseMove(client: GameClient): { x: number; y: number } {
      const candidates = [
        { x: 0, y: -1 },
        { x: -1, y: -1 },
        { x: 1, y: -1 },
        { x: -1, y: 0 },
        { x: 1, y: 0 },
        { x: 0, y: 1 },
        { x: -1, y: 1 },
        { x: 1, y: 1 },
        { x: 0, y: 0 },
      ];
      let best = candidates[0];
      let bestScore = Number.NEGATIVE_INFINITY;
      const drift =
        client.behavior.name === "weaver"
          ? Math.sin(this.elapsed * 1.6 + client.phase) * 13
          : 0;
      const targetX = clamp(client.targetX + drift, 0, MAP_COLUMNS - 1);

      for (const candidate of candidates) {
        const length = Math.hypot(candidate.x, candidate.y) || 1;
        const vx = candidate.x / length;
        const vy = candidate.y / length;
        const projectedX = clamp(
          client.x + vx * CLIENT_SPEED * 0.66,
          0,
          MAP_COLUMNS - 1,
        );
        const projectedY = clamp(
          client.y + vy * CLIENT_SPEED * 0.66,
          0,
          MAP_ROWS - 1,
        );
        const inScoreRows = projectedY < SCORE_ROWS;
        const progress =
          (MAP_ROWS - projectedY) *
          (inScoreRows
            ? client.behavior.holdScoreZone
            : client.behavior.progressWeight);
        const target =
          -Math.abs(projectedX - targetX) * client.behavior.targetWeight;
        const scoreBonus = inScoreRows ? 34 : 0;
        const crowding = this.crowding(projectedX, projectedY, client.id);
        const danger =
          this.danger(projectedX, projectedY) * client.behavior.riskWeight;
        const ranking = progress + target + scoreBonus - danger - crowding;

        if (ranking > bestScore) {
          bestScore = ranking;
          best = { x: vx, y: vy };
        }
      }

      return best;
    }

    private danger(x: number, y: number): number {
      let danger = 0;

      for (const platform of this.platforms) {
        for (const lookahead of [0, 0.24, 0.52, 0.88, 1.24]) {
          const futureY = platform.y + platform.speed * lookahead;
          const dx =
            x < platform.x
              ? platform.x - x
              : x > platform.x + platform.width
                ? x - (platform.x + platform.width)
                : 0;
          const dy = Math.abs(y - futureY);

          if (dx <= 0.9 && dy <= 0.78) {
            danger += 180 / (lookahead + 0.18);
          } else if (dx <= 3.4 && dy <= 2.4) {
            danger += 22 / (lookahead + 0.34);
          }
        }
      }

      return danger;
    }

    private crowding(x: number, y: number, clientId: number): number {
      let crowding = 0;

      for (const client of this.clients) {
        if (client.id === clientId || client.status !== "alive") continue;

        const distance = Math.hypot(client.x - x, client.y - y);
        crowding += Math.max(0, 1.4 - distance) * 2.2;
      }

      return crowding;
    }

    private hitsPlatform(x: number, y: number): boolean {
      return this.platforms.some(
        (platform) =>
          Math.abs(y - platform.y) <= 0.52 &&
          x >= platform.x - 0.35 &&
          x <= platform.x + platform.width + 0.35,
      );
    }

    private pathHitsPlatform(
      previousX: number,
      previousY: number,
      nextX: number,
      nextY: number,
    ): boolean {
      const distance = Math.max(
        Math.abs(nextX - previousX),
        Math.abs(nextY - previousY),
      );
      const steps = Math.max(2, Math.ceil(distance / 0.22));

      for (let step = 0; step <= steps; step += 1) {
        const ratio = step / steps;
        const x = previousX + (nextX - previousX) * ratio;
        const y = previousY + (nextY - previousY) * ratio;
        if (this.hitsPlatform(x, y)) return true;
      }

      return false;
    }

    private nextGrid(): Cell[][] {
      const cells = createEmptyCells();

      for (const platform of this.platforms) {
        const row = Math.round(platform.y);
        if (row < 0 || row >= MAP_ROWS) continue;

        const start = clamp(Math.round(platform.x), 0, MAP_COLUMNS - 1);
        const end = clamp(start + platform.width, 0, MAP_COLUMNS - 1);
        for (let column = start; column <= end; column += 1) {
          cells[row][column] = {
            char: "=",
            color: PLATFORM_COLOR,
            ownerId: null,
          };
        }
      }

      const occupied: Record<string, number> = {};
      for (const client of this.clients) {
        if (client.status === "disconnected") continue;

        const row = Math.round(client.y);
        const column = Math.round(client.x);
        if (row < 0 || row >= MAP_ROWS || column < 0 || column >= MAP_COLUMNS) {
          continue;
        }

        const key = `${row}:${column}`;
        const count = occupied[key] ?? 0;
        occupied[key] = count + 1;
        cells[row][column] = {
          char:
            count > 0
              ? "*"
              : client.status === "winner"
                ? "W"
                : clientGlyph(client.id),
          color: count > 0 ? SCORE_COLOR : client.color,
          ownerId: client.id,
        };
      }

      return cells;
    }

    private applyGrid(nextCells: Cell[][]): void {
      const nextText = createDocumentText(
        nextCells,
        this.elapsed,
        this.winnerId,
      );
      if (nextText === this.documentText) return;

      this.mainDoc.delete(0, Number(this.mainDoc.length));
      this.mainDoc.insert(0, nextText);
      this.documentCells = nextCells.map((row) =>
        row.map((cell) => ({ ...cell })),
      );
      this.documentText = nextText;
      this.snapshots.push(nextText);
      this.syncClients();
    }

    private applyWinnerScreenLine(): void {
      const winner = this.clients.find((client) => client.id === this.winnerId);
      const lines = winnerDocumentLines(winner, this.elapsed);
      if (this.winnerScreenLine > lines.length) return;

      const winnerText = createWinnerDocumentText(lines, this.winnerScreenLine);

      this.mainDoc.delete(0, Number(this.mainDoc.length));
      this.mainDoc.insert(0, winnerText);
      this.documentCells = createEmptyCells();
      this.documentText = winnerText;
      this.snapshots.push(winnerText);
      this.winnerScreenLine += 1;
      this.syncClients();
    }

    private syncClients(): void {
      for (const client of this.clients) {
        const update = this.mainDoc.encodeUpdate(
          client.doc.encodeStateVector(),
        );
        if (update.byteLength > 0) {
          client.doc.applyUpdate(update);
        }
      }
    }
  }

  let loadState = $state<LoadState>("loading");
  let errorMessage = $state("");
  let session = $state<MirageGameSession | null>(null);
  let documentText = $state("");
  let leaderboard = $state<LeaderboardRow[]>([]);
  let frame = $state(0);
  let elapsed = $state(0);
  let activePlatforms = $state(0);
  let version = $state(0);
  let historyOpen = $state(false);
  let historyRevision = $state(0);
  let paused = $state(false);

  let timer: ReturnType<typeof setInterval> | null = null;

  let maxHistoryRevision = $derived(
    (track(version), session ? session.snapshots.length - 1 : 0),
  );
  let historyDelta = $derived.by(() => {
    track(historyRevision);
    track(maxHistoryRevision);
    if (!session) return [];
    const revision = clamp(historyRevision, 0, maxHistoryRevision);
    return session.documentDeltaAt(revision);
  });

  function track(_value: unknown): void {}

  function createEmptyCells(): Cell[][] {
    return Array.from({ length: MAP_ROWS }, () =>
      Array.from({ length: MAP_COLUMNS }, () => ({
        char: " ",
        color: null,
        ownerId: null,
      })),
    );
  }

  function createDocumentText(
    cells: Cell[][],
    elapsed: number,
    winnerId: number | null,
  ): string {
    const border = `+${"-".repeat(MAP_COLUMNS)}+`;
    const timeLine =
      `time ${elapsed.toFixed(1).padStart(4, " ")} / ${MATCH_SECONDS}s` +
      (winnerId === null
        ? ""
        : `  winner client-${String(winnerId).padStart(3, "0")}`);
    const rows = cells.map((row, index) => {
      const label =
        index < SCORE_ROWS ? SCORE_LABEL : " ".repeat(SCORE_LABEL.length);
      return `|${row.map((cell) => cell.char).join("")}|${label}`;
    });

    return `${timeLine}\n${border}\n${rows.join("\n")}\n${border}`;
  }

  function winnerDocumentLines(
    winner: GameClient | undefined,
    elapsed: number,
  ): string[] {
    const name = winner?.name ?? "client-unknown";
    const score = winner?.score.toFixed(1) ?? "0.0";

    return [
      "##      ##  ####  ##   ##  ##   ##  #######  ######",
      "##  ##  ##   ##   ###  ##  ###  ##  ##       ##   ##",
      "##  ##  ##   ##   #### ##  #### ##  #####    ######",
      "##  ##  ##   ##   ## ####  ## ####  ##       ##  ##",
      " ###  ###   ####  ##   ##  ##   ##  #######  ##   ##",
      "",
      `${name} cleared the document`,
      `score ${score}s in score rows`,
      `time ${elapsed.toFixed(1)} / ${MATCH_SECONDS}s`,
    ];
  }

  function createWinnerDocumentText(
    lines: string[],
    visibleLines: number,
  ): string {
    const border = `+${"-".repeat(MAP_COLUMNS)}+`;
    const rows = createEmptyCells();
    const startRow = 3;

    for (
      let index = 0;
      index < Math.min(visibleLines, lines.length);
      index += 1
    ) {
      const row = rows[startRow + index];
      if (!row) continue;

      const text = lines[index];
      const startColumn = Math.max(
        0,
        Math.floor((MAP_COLUMNS - text.length) / 2),
      );
      for (
        let column = 0;
        column < text.length && startColumn + column < MAP_COLUMNS;
        column += 1
      ) {
        row[startColumn + column] = {
          char: text[column],
          color: null,
          ownerId: null,
        };
      }
    }

    const body = rows
      .map((row) => `|${row.map((cell) => cell.char).join("")}|      `)
      .join("\n");

    return `${border}\n${body}\n${border}`;
  }

  function clientGlyph(clientId: number): string {
    return clientId.toString(36).slice(-1).toUpperCase();
  }

  function statusSortWeight(status: ClientStatus): number {
    if (status === "winner") return 2;
    if (status === "alive") return 1;
    return 0;
  }

  function hashFloat(left: number, right: number): number {
    const value = Math.sin(left * 12.9898 + right * 78.233) * 43758.5453;
    return value - Math.floor(value);
  }

  function clamp(value: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, value));
  }

  function refreshUi(): void {
    if (!session) return;

    documentText = session.documentDelta()[0]?.insert ?? "";
    leaderboard = session.leaderboard();
    frame = session.frame;
    elapsed = session.elapsed;
    activePlatforms = session.activePlatformCount();
    version += 1;

    if (!historyOpen) {
      historyRevision = maxHistoryRevision;
    }
  }

  function startTimer(): void {
    if (timer) clearInterval(timer);

    timer = setInterval(() => {
      if (!session || paused) return;
      session.tick(TICK_MS / 1000);
      refreshUi();
    }, TICK_MS);
  }

  async function createSession(): Promise<void> {
    loadState = "loading";
    errorMessage = "";

    try {
      const mirage = await loadMirage();
      session?.destroy();
      session = new MirageGameSession(mirage);
      paused = false;
      historyOpen = false;
      refreshUi();
      startTimer();
      loadState = "ready";
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : String(error);
      loadState = "error";
    }
  }

  function resetGame(): void {
    void createSession();
  }

  function togglePaused(): void {
    paused = !paused;
  }

  function openHistory(): void {
    historyRevision = maxHistoryRevision;
    historyOpen = true;
  }

  function closeHistory(): void {
    historyOpen = false;
  }

  function setHistoryRevision(revision: number): void {
    historyRevision = revision;
  }

  onMount(() => {
    void createSession();

    return () => {
      if (timer) clearInterval(timer);
      session?.destroy();
    };
  });
</script>

<svelte:head>
  <title>Collaborative Game | Mirage</title>
  <meta
    name="description"
    content="Text-based multiplayer document game powered by Mirage."
  />
</svelte:head>

<main class="h-svh overflow-hidden bg-neutral-950 font-mono text-neutral-100">
  <section class="mx-auto flex h-full w-full max-w-7xl flex-col px-4 py-4">
    <header
      class="flex items-center justify-between border border-neutral-700 bg-neutral-950 px-3 py-2"
    >
      <a class="text-sm font-bold text-cyan-300" href={resolve("/")}>mirage</a>
      <div class="text-xs text-neutral-500">/collaborative-game</div>
    </header>

    {#if loadState === "loading"}
      <div class="mt-3 border border-neutral-700 p-4 text-sm text-neutral-400">
        loading mirage wasm...
      </div>
    {:else if loadState === "error"}
      <div
        class="mt-3 border border-red-700 bg-red-950 p-4 text-sm text-red-100"
      >
        {errorMessage}
      </div>
    {:else}
      <div
        class="mt-3 grid min-h-0 flex-1 gap-3 lg:grid-cols-[minmax(0,1fr)_18rem]"
      >
        <section
          class="flex min-h-0 min-w-0 flex-col border border-neutral-700 bg-neutral-950"
        >
          <div
            class="flex items-center justify-between gap-3 border-b border-neutral-700 px-3 py-2"
          >
            <div>
              <div class="text-xs text-neutral-400">main document</div>
              <div class="text-xs text-neutral-600">
                {CLIENT_COUNT} clients · {activePlatforms} platforms · frame {frame}
              </div>
            </div>
            <div class="flex items-center gap-2">
              <button
                class="border border-neutral-700 px-3 py-1.5 text-sm text-cyan-300 hover:bg-neutral-900 focus-visible:bg-neutral-900 focus-visible:outline-2 focus-visible:outline-cyan-300"
                type="button"
                onclick={openHistory}
              >
                history
              </button>
              <button
                class="border border-neutral-700 px-3 py-1.5 text-sm text-cyan-300 hover:bg-neutral-900 focus-visible:bg-neutral-900 focus-visible:outline-2 focus-visible:outline-cyan-300"
                type="button"
                onclick={togglePaused}
              >
                {paused ? "resume" : "pause"}
              </button>
              <button
                class="border border-neutral-700 px-3 py-1.5 text-sm text-cyan-300 hover:bg-neutral-900 focus-visible:bg-neutral-900 focus-visible:outline-2 focus-visible:outline-cyan-300"
                type="button"
                onclick={resetGame}
              >
                reset
              </button>
            </div>
          </div>

          <pre
            class="grid min-h-0 flex-1 place-items-center overflow-hidden p-4 text-sm leading-5 text-neutral-200"><code
              >{documentText}</code
            ></pre>

          <div
            class="flex items-center justify-between border-t border-neutral-700 px-3 py-2 text-xs text-neutral-500"
          >
            <span>{elapsed.toFixed(1)}s</span>
            <span>{MATCH_SECONDS}s match · score is time in score rows</span>
            <span>snapshot {maxHistoryRevision}</span>
          </div>
        </section>

        <aside
          class="channel-scrollbar min-h-0 overflow-auto border border-neutral-700 bg-neutral-950"
        >
          <div
            class="border-b border-neutral-700 px-3 py-2 text-xs text-neutral-400"
          >
            clients · {leaderboard.length}
          </div>

          <ol>
            {#each leaderboard as client (client.id)}
              <li class="border-b border-neutral-800 px-3 py-3 last:border-b-0">
                <div class="flex items-center justify-between gap-2">
                  <div class="flex min-w-0 items-center gap-2">
                    <span
                      class="grid size-7 place-items-center border border-neutral-700 text-xs font-bold text-neutral-950"
                      style={`background-color: ${client.color}`}
                    >
                      {clientGlyph(client.id)}
                    </span>
                    <span class="truncate text-sm text-neutral-100">
                      {client.name}
                    </span>
                  </div>
                  <span class="text-xs text-neutral-400">
                    {client.score.toFixed(1)}s
                  </span>
                </div>

                <div class="mt-2 flex items-center justify-between text-xs">
                  <span
                    class={`${
                      client.status === "disconnected"
                        ? "text-red-300"
                        : client.status === "winner"
                          ? "text-yellow-300"
                          : "text-emerald-300"
                    }`}
                  >
                    {client.status}
                  </span>
                  <span class="text-neutral-500">{client.behavior}</span>
                </div>
              </li>
            {/each}
          </ol>
        </aside>
      </div>
    {/if}
  </section>

  <HistoryModal
    open={historyOpen}
    clientName="main document"
    revision={historyRevision}
    maxRevision={maxHistoryRevision}
    delta={historyDelta}
    onClose={closeHistory}
    onRevisionChange={setHistoryRevision}
  />
</main>
