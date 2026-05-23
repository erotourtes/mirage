<script lang="ts">
  import { resolve } from "$app/paths";

  const links = [
    {
      href: resolve("/collaborative-editor"),
      label: "collaborative-editor",
      description: "local-first editor communication channel",
    },
    {
      href: resolve("/collaborative-game"),
      label: "collaborative-game",
      description: "many-client text game on a shared Mirage document",
    },
  ];
</script>

<svelte:head>
  <title>Mirage Demos</title>
  <meta name="description" content="Mirage demo index." />
</svelte:head>

<main class="min-h-svh bg-neutral-950 font-mono text-neutral-100">
  <section class="mx-auto flex min-h-svh w-full max-w-4xl flex-col px-4 py-4">
    <header
      class="flex items-center justify-between border border-neutral-700 bg-neutral-950 px-3 py-2"
    >
      <a class="text-sm font-bold text-cyan-300" href={resolve("/")}>mirage</a>
      <div class="text-xs text-neutral-500">/</div>
    </header>

    <nav
      class="mt-3 border border-neutral-700 bg-neutral-950"
      aria-label="Demo links"
    >
      <div
        class="border-b border-neutral-700 px-3 py-2 text-xs text-neutral-400"
      >
        channels
      </div>

      <ul>
        {#each links as link (link.href)}
          <li class="border-b border-neutral-800 last:border-b-0">
            <a
              class="grid gap-1 px-3 py-3 text-sm hover:bg-neutral-900 focus-visible:bg-neutral-900 focus-visible:outline-2 focus-visible:outline-cyan-300"
              href={link.href}
            >
              <span class="text-cyan-300">#{link.label}</span>
              <span class="text-xs text-neutral-500">{link.description}</span>
            </a>
          </li>
        {/each}
      </ul>
    </nav>
  </section>
</main>
