<script lang="ts">
  import { resolve } from "$app/paths";
  import { onMount } from "svelte";
  import { createDemoDocument } from "$lib/mirage/client";

  type LoadState = "loading" | "ready" | "error";

  let loadState = $state<LoadState>("loading");
  let text = $state("");
  let length = $state("0");
  let stateVectorBytes = $state(0);
  let updateBytes = $state(0);
  let errorMessage = $state("");
  let statusClass = $derived(
    loadState === "ready"
      ? "bg-cyan-400 text-zinc-950"
      : loadState === "loading"
        ? "bg-amber-300 text-zinc-950"
        : "bg-red-400 text-white",
  );

  onMount(() => {
    let cancelled = false;

    async function runDemo() {
      try {
        const doc = await createDemoDocument();
        doc.insert(doc.length, " The Svelte shell is ready.");

        const stateVector = doc.encodeStateVector();
        const update = doc.encodeUpdate();

        if (!cancelled) {
          text = doc.toString();
          length = doc.length.toString();
          stateVectorBytes = stateVector.byteLength;
          updateBytes = update.byteLength;
          loadState = "ready";
        }

        doc.destroy();
      } catch (error) {
        if (!cancelled) {
          errorMessage = error instanceof Error ? error.message : String(error);
          loadState = "error";
        }
      }
    }

    void runDemo();

    return () => {
      cancelled = true;
    };
  });
</script>

<svelte:head>
  <title>Mirage WASM Demo</title>
  <meta
    name="description"
    content="A SvelteKit and Tailwind demo shell for the Mirage WebAssembly module."
  />
</svelte:head>

<main class="min-h-svh bg-zinc-950 text-zinc-100">
  <section
    class="mx-auto flex min-h-svh w-full max-w-6xl flex-col px-5 py-6 sm:px-8 lg:px-10"
  >
    <header
      class="flex items-center justify-between border-b border-white/10 pb-5"
    >
      <a
        href={resolve("/")}
        class="text-sm font-semibold tracking-[0.18em] text-cyan-300 uppercase"
        >Mirage</a
      >
      <nav
        class="flex gap-1 text-sm text-zinc-300"
        aria-label="Primary navigation"
      >
        <a
          class="rounded-md px-3 py-2 transition hover:bg-white/10 hover:text-white"
          href={resolve("/")}>Demo</a
        >
      </nav>
    </header>

    <div
      class="grid flex-1 items-center gap-10 py-10 lg:grid-cols-[1.05fr_0.95fr] lg:py-14"
    >
      <div class="max-w-2xl">
        <p
          class="mb-4 text-sm font-medium tracking-[0.2em] text-cyan-300 uppercase"
        >
          SvelteKit + TypeScript + Tailwind
        </p>
        <h1
          class="text-4xl leading-tight font-semibold text-white sm:text-5xl lg:text-6xl"
        >
          Mirage WebAssembly demo
        </h1>
        <p class="mt-6 max-w-xl text-base leading-7 text-zinc-300 sm:text-lg">
          The first page loads the Zig-built WASM module, creates a Mirage
          document, writes text, and reads encoded sync data through a typed
          wrapper.
        </p>
      </div>

      <section
        class="rounded-lg border border-white/10 bg-zinc-900/80 shadow-2xl shadow-cyan-950/30"
        aria-label="Mirage runtime status"
      >
        <div class="border-b border-white/10 px-5 py-4">
          <div class="flex items-center justify-between gap-4">
            <h2 class="text-lg font-semibold text-white">Runtime Check</h2>
            <span
              class={`rounded-full px-3 py-1 text-xs font-medium ${statusClass}`}
            >
              {loadState}
            </span>
          </div>
        </div>

        <div class="space-y-5 p-5">
          {#if loadState === "error"}
            <p
              class="rounded-md border border-red-400/40 bg-red-950/40 p-4 text-sm text-red-100"
            >
              {errorMessage}
            </p>
          {:else}
            <div>
              <p
                class="mb-2 text-xs font-medium tracking-[0.16em] text-zinc-500 uppercase"
              >
                Document text
              </p>
              <p
                class="min-h-24 rounded-md bg-zinc-950 p-4 font-mono text-sm leading-6 text-zinc-100"
              >
                {loadState === "loading" ? "Loading Mirage WASM..." : text}
              </p>
            </div>

            <div class="grid gap-3 sm:grid-cols-3">
              <div class="rounded-md bg-zinc-950 p-4">
                <p class="text-xs text-zinc-500">Length</p>
                <p class="mt-2 text-2xl font-semibold text-white">{length}</p>
              </div>
              <div class="rounded-md bg-zinc-950 p-4">
                <p class="text-xs text-zinc-500">State vector</p>
                <p class="mt-2 text-2xl font-semibold text-white">
                  {stateVectorBytes} B
                </p>
              </div>
              <div class="rounded-md bg-zinc-950 p-4">
                <p class="text-xs text-zinc-500">Update</p>
                <p class="mt-2 text-2xl font-semibold text-white">
                  {updateBytes} B
                </p>
              </div>
            </div>
          {/if}
        </div>
      </section>
    </div>
  </section>
</main>
