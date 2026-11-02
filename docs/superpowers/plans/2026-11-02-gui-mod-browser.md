# GUI Mod Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the GUI's mod checklist and Manage Mods screen with a card-grid "Mods" screen (Browse / Installed / Updates) driven by the same catalog, record and `ModOps` logic as `amm`, and add `amm install --mod` (keeping `mi`).

**Architecture:** All mod logic stays in `amm_core` (`Catalog`, `ModOps`, `AmmRecord`, `ModStore`). Core gains the card fields from modlist.org and one helper that groups on-disk mods into Installed-tab items. The GUI's `AppState` swaps its mods.json-only `ModRegistry`/`ModDownloader` path for `Catalog` + `ModOps`, and a new `ModsView` renders the grid. The CLI change is argument parsing only.

**Tech Stack:** Dart 3.12 (core, cli; `package:test`, `package:args`), Flutter 3.47 (gui, Material 3 dark).

**Spec:** `docs/superpowers/specs/2026-11-02-gui-mod-browser-design.md`

## Global Constraints

- Every user-visible GUI string goes through `state.t('<English>', '<Korean>')`.
- No new package dependencies in core, cli or gui.
- GUI holds no mod logic of its own: installs use `ModOps.plan` + `ModOps.install`, updates `ModOps.upgrade`, removal `ModOps.remove` (recorded) or `ModStore.archive`/`ModStore.delete` (unrecorded file), all saving the shared `AmmRecord`.
- Edit files in the style around them; do not run `dart format` over whole files that weren't formatted before (it rewrites unrelated lines).
- Must pass: `dart test` in `core` and `cli` on macOS; `flutter analyze` in `gui`; the same core/cli tests on x64 Linux (container script below).
- Card grid is 3 columns at the default 800×600 window.

## Review Focus

1. **One catalog source down** (modlist.org unreachable): Browse shows the mods.json entries with no author/downloads/categories, plus a one-line notice; nothing crashes on the missing fields.
2. **Hand-added mod folder whose Info.json `Id` matches a catalog entry:** Browse shows it as ✓ Installed; the Installed tab shows one card for it with catalog info; Remove acts on that folder path only.
3. **Recorded mod with several paths** (e.g. a MelonLoader dll plus files elsewhere): the Installed tab shows one card, not one per path; Remove deletes or archives all of them and drops the record entry.
4. **A dependency fails to install:** the error shows, buttons re-enable, mods that did install stay recorded and show ✓ Installed.
5. **Record entry whose files were deleted by hand:** shows as not installed (Install button) — `AmmRecord.load` already drops it; nothing in the GUI re-adds it.

Tests for 1–3 land in Tasks 1–2; 4–5 are checked by hand in Task 6.

---

### Task 1: Card fields from modlist.org

**Files:**
- Modify: `core/lib/src/modlist.dart` (`ModlistMod` + `fromJson`)
- Modify: `core/lib/src/catalog.dart` (`CatalogEntry` getters)
- Test: `core/test/modlist_test.dart`, `core/test/catalog_test.dart`

**Interfaces:**
- Produces: `ModlistMod.author` (`String?`, from `authorId.username`), `ModlistMod.downloads` (`int`, default 0), `ModlistMod.categories` (`List<String>`, default empty). `CatalogEntry.author` (`String?`), `CatalogEntry.downloads` (`int?`, null for mods.json-only), `CatalogEntry.categories` (`List<String>`, empty for mods.json-only).

- [ ] **Step 1: Write the failing tests**

In `modlist_test.dart`, extend the `quartz` fixture with `'authorId': {'username': 'koren.cs'}`, `'downloads': 317`, `'categories': ['utility', 'gameplay']`, and add:

```dart
test('fromJson reads author, downloads and categories', () {
  final m = ModlistMod.fromJson(quartz);
  expect(m.author, 'koren.cs');
  expect(m.downloads, 317);
  expect(m.categories, ['utility', 'gameplay']);
});
```

Extend the existing "tolerates missing fields" test with `expect(m.author, isNull); expect(m.downloads, 0); expect(m.categories, isEmpty);`.

In `catalog_test.dart`:

```dart
test('card fields come from modlist.org and are absent for mods.json-only', () {
  final c = Catalog.merge(
    [const Mod(id: 'Ours', slug: 'ours', url: 'u')],
    [const ModlistMod(slug: 'q', name: 'Q', author: 'a', downloads: 5, categories: ['ui'])],
  );
  expect(c.find('q')!.author, 'a');
  expect(c.find('q')!.downloads, 5);
  expect(c.find('q')!.categories, ['ui']);
  expect(c.find('ours')!.author, isNull);
  expect(c.find('ours')!.downloads, isNull);
  expect(c.find('ours')!.categories, isEmpty);
});
```

- [ ] **Step 2: Run to see them fail**

Run: `cd core && dart test test/modlist_test.dart test/catalog_test.dart`
Expected: compile errors (`author` not defined).

- [ ] **Step 3: Implement** the three optional constructor params on `ModlistMod` (defaults `null`, `0`, `const []`), parse them in `fromJson` tolerating missing/null keys, and the three getters on `CatalogEntry` reading `theirs`.

- [ ] **Step 4: Run to see them pass**

Run: `cd core && dart test`
Expected: all pass.

- [ ] **Step 5: Checkpoint** — no commit; the user commits everything at the end.

---

### Task 2: Installed-tab items in core

**Files:**
- Modify: `core/lib/src/mod_ops.dart`
- Test: `core/test/mod_ops_test.dart` (new `group('installedItems', ...)`, reusing the file's `catalog`, `game` and `GamePaths.overrideGamePath` setup)

**Interfaces:**
- Produces:

```dart
/// One card on the GUI's Installed tab.
class InstalledItem {
  final String name;
  /// Record key or catalog match; null for a file nothing knows.
  final String? slug;
  final String? version;
  final CatalogEntry? entry;
  /// Set when no record entry owns it: remove by this path, not by slug.
  final InstalledMod? file;
  const InstalledItem({required this.name, this.slug, this.version, this.entry, this.file});
}

// in ModOps:
static List<InstalledItem> installedItems(
    Catalog c, AmmRecord r, List<InstalledMod> onDisk, String gameRoot);
```

Rules: walk `onDisk`. A file whose game-relative path has a record owner (`r.ownerSlug(rel)`) contributes one item per owner slug (first one wins): `name` = `c.find(slug)?.name ?? slug`, `version` = the record entry's version, `entry` = `c.find(slug)`, `file` = null. Any other file is its own item: `name` = `m.name`, `entry` = the catalog match by Info.json `Id` (same matching `upgrades` uses — extract that into one private helper both call), `slug` = `entry?.slug`, `version` = `ModStore.infoField(m.path, 'Version')`, `file` = `m`. Sort by name, case-insensitive.

- [ ] **Step 1: Write the failing tests**

```dart
group('installedItems', () {
  test('groups a recorded mod into one item with its record version', () {
    Directory(p.join(game, 'Mods', 'B')).createSync(recursive: true);
    File(p.join(game, 'Mods', 'B.dll')).writeAsStringSync('x');
    final r = AmmRecord()
      ..mods['both'] = const RecordEntry(
          source: 'modlist.org', version: '1', paths: ['Mods/B', 'Mods/B.dll']);
    final items = ModOps.installedItems(catalog, r, ModStore.scanInstalled(), game);
    expect(items, hasLength(1));
    expect(items.single.slug, 'both');
    expect(items.single.version, '1');
    expect(items.single.file, isNull);
  });

  test('matches a hand-added folder by Id and keeps its path', () {
    final d = Directory(p.join(game, 'Mods', 'OursDir'))..createSync(recursive: true);
    File(p.join(d.path, 'Info.json')).writeAsStringSync('{"Id":"ours","Version":"0.5"}');
    final item = ModOps.installedItems(catalog, AmmRecord(), ModStore.scanInstalled(), game).single;
    expect(item.slug, 'ours');
    expect(item.entry, isNotNull);
    expect(item.version, '0.5');
    expect(item.file!.path, d.path);
  });

  test('lists an unknown file with no slug', () {
    File(p.join(game, 'Mods', 'Mystery.dll'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final item = ModOps.installedItems(catalog, AmmRecord(), ModStore.scanInstalled(), game).single;
    expect(item.name, 'Mystery.dll');
    expect(item.slug, isNull);
    expect(item.entry, isNull);
  });
});
```

- [ ] **Step 2: Run to see them fail**

Run: `cd core && dart test test/mod_ops_test.dart`
Expected: compile error (`installedItems` not defined).

- [ ] **Step 3: Implement** `InstalledItem` and `ModOps.installedItems` per the rules above; refactor `upgrades` to use the shared Id-matching helper.

- [ ] **Step 4: Run to see them pass**

Run: `cd core && dart test`
Expected: all pass (including the existing `upgrades` tests after the refactor).

- [ ] **Step 5: Checkpoint** — no commit; the user commits everything at the end.

---

### Task 3: `amm install --mod`

**Files:**
- Modify: `cli/lib/src/cli.dart`
- Test: `cli/test/cli_test.dart`
- Modify: `README.md`, `README.kr.md` (command table row)

**Interfaces:**
- Consumes: `modinstall(Ctx c, List<String> slugs)` in `mod_commands.dart` (unchanged; the TUI keeps calling it).
- Produces: `normalize` rewrites `mi` and `modinstall` to `['install', '--mod', ...rest]`.

Behaviour:
- `install` gets a `mod` flag. With `--mod`: no slugs → `usageError('install --mod needs at least one mod.')`; any of `--ml/--native/--rosetta` too → `usageError('Use --mod without --ml, --native or --rosetta.')`; else `modinstall(c, cmd.rest)`.
- The `modinstall` parser command and its two switch arms go away (normalize covers it).
- Help row replaces `modinstall (mi) <slug>...` with `install --mod <slug>... (mi)` and the description `Install mods`, aligned with the other rows.
- README rows: `amm install --mod <mod>` / `mi` — "Install a mod" / "모드 설치".

- [ ] **Step 1: Write the failing tests**

In `cli_test.dart`, change the existing normalize expectation to `expect(normalize(['mi', 'a']), ['install', '--mod', 'a']);` and add `expect(normalize(['modinstall', 'a', 'b']), ['install', '--mod', 'a', 'b']);`. Add, using the file's existing `run` helper:

```dart
test('install --mod needs a mod and no loader flag', () async {
  expect((await run(['install', '--mod'])).$1, 2);
  expect((await run(['install', '--mod', '--ml', 'x'])).$1, 2);
});
```

- [ ] **Step 2: Run to see them fail**

Run: `cd cli && dart test test/cli_test.dart`
Expected: normalize expectations fail.

- [ ] **Step 3: Implement** the parsing changes and help/README rows.

- [ ] **Step 4: Run to see them pass**

Run: `cd cli && dart test`
Expected: all pass.

- [ ] **Step 5: Checkpoint** — no commit; the user commits everything at the end.

---

### Task 4: AppState on the shared catalog

**Files:**
- Modify: `gui/lib/src/app_state.dart`
- Modify: `gui/lib/src/models.dart` (`InstallPhase`)

**Interfaces:**
- Consumes: `Catalog.load()`, `Catalog.warnings`, `CatalogEntry.visibleOn`, `CatalogEntry.jalib`, `ModOps.plan/install/upgrades/upgrade/remove/installedItems`, `InstalledItem` (Task 2), `ModStore.scanInstalled/scanArchived/archive/delete/restore/deleteArchived`, `AmmRecord.load/save`.
- Produces (used by Task 5's `ModsView`):

```dart
Catalog? catalog;                 // null until loaded
String? catalogError;             // both sources failed
UpgradeScan? scan;
List<InstalledItem> installedItems;
List<ArchivedMod> archivedMods;   // existing field, kept
String? busySlug;                 // the card whose operation is running; '*' for Update All
Future<void> loadCatalog();
void openMods();                  // refreshes, sets phase = InstallPhase.mods
List<CatalogEntry> get browseEntries;     // visibleOn(isGameV2) && !jalib
List<CatalogEntry> get unavailableJalib;  // visibleOn(isGameV2) && jalib
bool isInstalled(String slug);            // scan.installed
Upgrade? upgradeFor(String slug);         // scan.upgrades
Future<void> installMod(String slug);
Future<void> updateMod(String slug);
Future<void> updateAll();
void removeItem(InstalledItem item, {required bool keep});
void restoreMod(ArchivedMod a);           // existing, kept
void deleteArchived(ArchivedMod a);       // existing, kept
String? modError;                 // last operation's error text, cleared on next op
```

Changes:
- `InstallPhase.picker` and `InstallPhase.manageMods` become one `InstallPhase.mods`.
- `ModTarget` for operations: `gameRoot: GamePaths.gamePath, isV2: isGameV2, gameVersion: gameVersion, melon: hasMelonLoader, platform: Platform.operatingSystem`.
- `installMod`: plan with `ModOps.plan(catalog!, [slug], record)`, install each entry in order, save the record after each success (as `amm` does), stop at the first failure and set `modError` to `'<slug>: <message>'` for `ModOpsException`/`ModDownloadException`. Always clear `busySlug` and refresh at the end.
- `updateMod`/`updateAll`: `ModOps.upgrade` for the matching `Upgrade`(s), record saved after each; same error handling.
- `removeItem`: `item.file == null` → `ModOps.remove(item.slug!, record, root, keep: keep)` then save; else `ModStore.archive(item.file!)` or `ModStore.delete(item.file!.path)`.
- Refresh = reload record, `ModStore.scanInstalled()`, `ModOps.upgrades(...)`, `ModOps.installedItems(...)`, `ModStore.scanArchived()`, `notifyListeners()`.
- First setup: `proceedFromConfirm(loader)` sets `selectedLoader` and calls `startInstall()` directly (no picker). `startInstall` installs the loader only: delete the mods loop, `skipMods`, `selectedMods`, `toggleMod`, `setAllSelected`, `visibleMods`, `unavailableJalibMods`, `mods`, `modsError`, `loadMods`, `reloadMods`, `proceedFromInstalled`, `openManageMods`, `selectedForDelete`, `toggleDeleteSelection`, `deleteMods`, `archiveMods`, `installedMods`. Delete `ModDownloader`/`ModRegistry` uses in the GUI; leave the core classes (the CLI and `Catalog` use them).
- Ruling: after a successful loader install the app stays on the completion screen (its log holds the Steam launch-option instructions), which gains a **Browse Mods** button calling `openMods()`. The spec says "lands on the Mods screen"; jumping straight there would hide those instructions.

- [ ] **Step 1: Implement** the state changes above.
- [ ] **Step 2: Run** `cd gui && flutter analyze` — expect only errors from views that still reference removed members (fixed in Task 5).
- [ ] **Step 3: Checkpoint** — no commit (the GUI compiles again after Task 5).

---

### Task 5: ModsView card grid

**Files:**
- Create: `gui/lib/src/ui/mods_view.dart`
- Delete: `gui/lib/src/ui/mod_picker_view.dart`, `gui/lib/src/ui/manage_mods_view.dart` (move `_JalibBanner`, `_ErrorState` and `_deleteDialog` into `mods_view.dart`)
- Modify: `gui/lib/src/ui/content_view.dart` (`InstallPhase.mods` → `ModsView`)
- Modify: `gui/lib/src/ui/installed_view.dart` ("Install Mods" + "Manage Mods" → one "Mods"/"모드" button calling `openMods()`)
- Modify: `gui/lib/src/ui/progress_view.dart` (Browse Mods button on a successful completion, next to Go Back)

**Interfaces:**
- Consumes: Task 4's AppState members; `CatalogEntry.name/slug/summary/author/downloads/categories/dependencies/gameVersions` (Task 1).

Layout (mockup A in `.superpowers/brainstorm` / spec):
- Title "Mods"/"모드"; tabs Browse / Installed (N) / Updates (N) (`SegmentedButton` or `TabBar`); search field filtering name, slug, author, summary (case-insensitive); category chips "All" + the categories present in the current tab's entries (`FilterChip`s, single-select).
- `GridView` with `SliverGridDelegateWithMaxCrossAxisExtent` sized so the 800-wide window gives 3 columns.
- Card: letter tile (first letter of name, background colour from `slug.hashCode` over a fixed palette), name, "by <author>" when known, summary (2 lines, ellipsis), first two categories plus "+N", "Needs <names>" when `dependencies` is non-empty, footer with version and "⬇ <downloads>" when known, and the action button.
- Browse button: **Install** (`installMod`), **✓ Installed** (disabled, green), or **Update** (yellow, `from → to`, `updateMod`). While `busySlug != null`, every button is disabled and the busy card shows a small progress indicator in place of its button.
- Installed tab: cards from `installedItems` (catalog info when `entry` is set, otherwise name and version only), button **Remove** → existing two-choice dialog (Keep Data → `removeItem(keep: true)`, Delete Permanently → `removeItem(keep: false)`). An "Archived (N)" toggle switches the grid to `archivedMods` with Restore / Delete Permanently, as Manage Mods had.
- Updates tab: cards for `scan.upgrades` with Update buttons; **Update All** button in the header row when there are any.
- Notices above the grid: catalog warnings (one line each, subtle), the JALib banner when `unavailableJalib` is non-empty, `modError` (error colour, dismissible). `catalogError` replaces the grid with the existing error state + Retry (`loadCatalog`).
- Bottom row: Go Back (`returnToMenu`).

- [ ] **Step 1: Implement** the view and the navigation edits.
- [ ] **Step 2: Run** `cd gui && flutter analyze`. Expected: "No issues found!"
- [ ] **Step 3: Checkpoint** — no commit.

---

### Task 6: Verify

**Files:** none (scratch scripts under the session scratchpad `linux/`).

- [ ] **Step 1:** macOS: `cd core && dart test`, `cd cli && dart test`, `cd gui && flutter analyze`, `bash test_scripts.sh` if present. Expected: all green.
- [ ] **Step 2:** x64 Linux: run the scratchpad `tests.sh` in `ghcr.io/cirruslabs/flutter:stable --platform linux/amd64`. Expected: core and cli "All tests passed!", Linux GUI tests ran (not skipped).
- [ ] **Step 3:** arm64 Linux GUI: extend `run.sh` to create a fake game folder at `$HOME/.local/share/Steam/steamapps/common/A Dance of Fire and Ice` with a `MelonLoader/` dir and a `Mods/` dir containing one hand-added folder (`Info.json` with an `Id` matching a catalog slug), launch under Xvfb, click "Mods" with `xdotool`, screenshot. Expected: grid of cards, 3 columns, the hand-added mod shown ✓ Installed on Browse and listed on Installed.
- [ ] **Step 4:** By hand on the screenshot/log: no overflow stripes, Korean toggle renders the KR strings.
- [ ] **Step 5:** Report results; no push.
