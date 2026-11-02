# GUI mod browser and `amm install --mod`

## Why

`amm` already works like a package manager: one catalog (mods.json merged with
modlist.org), installs with dependencies, a record of what came from where,
upgrades, and remove-with-archive. The GUI still has the old flow: a checklist
of mod names from mods.json only, offered as part of setting up the loader,
plus a "Manage Mods" screen that deletes or archives files. People who use the
GUI should get the same package-manager behaviour, presented like the
modlist.org app: mod info in cards, arranged in a grid.

Success: someone with the loader installed can open the app, find a mod by
name or category, install it (and whatever it needs) with one click, see what
they have, update it, and remove it, without touching the terminal. What
they do in the GUI and in `amm` stays in sync.

## Goals

### GUI: one "Mods" screen with three tabs

Replaces both the mod picker and Manage Mods. Mockup chosen: option A
("button on every card"), kept in the brainstorm session.

- **Tabs:** Browse, Installed (N), Updates (N).
- **Above the grid:** a search box (matches name, slug, author, summary), and
  category chips (All plus the categories modlist.org uses: utility, visuals,
  ui, gameplay, library…). Search and chips filter whichever tab is showing.
- **Catalog loading:** if one source is unreachable, show the other's mods
  and a small notice (as `amm` prints its warning). If both fail, keep
  today's "Couldn't load the mod list" state with Retry.
- **Grid:** 3 columns at the default 800×600 window. Cards can reflow to fewer
  or more columns as the window resizes (builder's call on breakpoints).
- **Card contents:** logo, name, author, summary (two lines, clipped),
  categories (first two plus "+N"), version, download count, and "Needs X"
  when the mod has dependencies. Fields the source lacks are left out (mods.json-only entries have no author,
  downloads or categories).
- **Card button:**
  - **Install** runs the same steps as `amm install --mod`: dependencies
    first, then the mod, written to the shared record. The button shows
    progress while it runs. Other cards' buttons are disabled until it
    finishes (one operation at a time).
  - **✓ Installed** once it's in.
  - **Update** (yellow, "old → new") when a newer version exists; runs the
    same upgrade as `amm upgrade <slug>`, including its backup and rollback.
  - Failures show on the card or as a snackbar, with the error text; the
    card returns to its previous state.
- **Clicking the card body does nothing** for now (no detail page).

### Installed tab

- Shows every installed mod: ones in the record (with version and source)
  and ones dropped into the Mods folder by hand (no version shown).
- Each card's button is **Remove**, with today's dialog: Keep Data (archive,
  restorable) or Delete Permanently (two clicks to confirm).
- An **Archived** filter on this tab lists archived mods with Restore and
  Delete Permanently, as Manage Mods does today.

### Updates tab

- Cards for mods with a newer version, each with its Update button.
- An **Update All** button (my call), same as `amm upgrade` with no names.

### What stays hidden

- Mods that don't fit the detected game build stay hidden, as today.
- JALib-dependent mods stay hidden, with the existing yellow notice.

### Navigation

- The Installed (loader) screen's "Install Mods" and "Manage Mods" buttons
  become one "Mods" button that opens this screen. Back returns to the
  loader screen.
- First-time setup: after the loader installs, the app lands on the Mods
  screen instead of the old checklist. "Skip Mods" disappears; leaving the
  screen is skipping.

### CLI: `amm install --mod <slug>...`

- New form for installing mods: `amm install --mod <slug>...`. Same
  behaviour as today's `amm modinstall`.
- `amm mi <slug>...` stays as an alias. `amm modinstall` also keeps working
  (my call: costs nothing and avoids breaking scripts), but help shows only
  `install --mod` (mi).
- `--mod` with a loader flag (`--ml`, `--native`, `--rosetta`) is a usage
  error. `--mod` with no slugs is a usage error ("install --mod needs at
  least one mod.").
- Help text, README.md and README.kr.md updated. The TUI's install-mods
  action keeps working (it calls the same function).

## Non-goals

- Mod detail page (full description, changelog, links). Later, maybe.
- Choosing a version or beta branch; installs the latest, as `amm` does.
- Profiles, export/import, enable/disable toggles.
- Changing how `amm` resolves, installs, upgrades or removes mods. The GUI
  reuses that logic; it does not get its own copy.
- `amm uninstall --mod` (removing stays `amm mr`).

## Anti-goals

- The GUI and `amm` disagreeing about what's installed (separate records,
  or the GUI installing mods.json-only like today).
- Breaking existing `amm mi` / `amm modinstall` usage.
- A grid that's cramped or unreadable at the default 800×600 window.

## Constraints

- Flutter GUI on macOS and Linux (Windows runner exists but isn't shipped).
  Dark theme and the app's EN/KR strings: every new string gets both.
- Logic stays in `amm_core`; the GUI only calls it. modlist.org fields the
  cards need (author, downloads, categories, logo path) get added to
  `ModlistMod`/`CatalogEntry` in core.
- All tests (core, cli, gui analyze) pass on macOS and x64 Linux.

## Left to the builder

- **Logos:** modlist.org's API gives a logo path (`/logos/<hash>.png|webp`)
  but that path returns 404 when fetched directly, so there is no known
  working URL yet. Ship with a letter tile (first letter of the name, colour
  derived from the slug). If a working logo URL turns up later, swap it in,
  falling back to the letter tile.
- Card sizing, spacing, and how the progress indicator looks.
- How the GUI matches hand-installed files to catalog entries (reuse
  whatever `ModOps.upgrades` / `ModStore` already do).
- Whether the old `ModDownloader` path and `mods.json`-only install code in
  the GUI can be deleted once nothing calls it (prefer deleting).
