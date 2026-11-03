import 'dart:io';
import 'package:amm_core/amm_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'models.dart';
import 'updater.dart';

/// App-wide state + actions, ported from the macOS `InstallerViewModel`.
class AppState extends ChangeNotifier {
  InstallPhase phase = InstallPhase.updating;
  Language language = Language.en;

  String? gameVersion;
  String subtitle = '';

  /// False on an Intel Mac (and off macOS), where UMM is the classic patch.
  bool appleSilicon = GamePaths.isAppleSilicon();
  String platform = Platform.operatingSystem;

  LoaderType selectedLoader = LoaderType.umm;

  final List<LogEntry> logEntries = [];
  List<String> migratableMods = [];

  // Mods screen: the catalog `amm` uses, and what's on disk (_refreshMods).
  Catalog? catalog;
  String? catalogError; // both sources failed
  UpgradeScan? scan;
  List<InstalledItem> installedItems = [];
  List<ArchivedMod> archivedMods = [];
  String? busySlug; // the card whose operation is running; '*' for Update All
  String? modError;

  bool completeSuccess = false;
  String completeMessage = '';

  // MARK: - Localization

  String t(String en, String ko) => language == Language.ko ? ko : en;

  void setLanguage(Language lang) {
    language = lang;
    notifyListeners();
  }

  // MARK: - Bootstrap

  String? updateTag;
  String? _updateUrl;
  bool get hasUpdate => updateTag != null;

  Future<void> bootstrap() async {
    phase = InstallPhase.updating;
    subtitle = t('Checking for updates…', '업데이트 확인 중…');
    notifyListeners();

    final latest = await Updater.fetchLatest();
    if (latest != null &&
        isNewerVersion(latest.tag, Updater.currentVersion) &&
        Updater.canSelfUpdate()) {
      updateTag = latest.tag;
      _updateUrl = latest.assetUrl;
      subtitle = '';
      notifyListeners(); // UpdatingView shows the update prompt
      return;
    }
    await _afterUpdateCheck();
  }

  Future<void> _afterUpdateCheck() async {
    // Discover the game across Steam libraries (registry / libraryfolders.vdf).
    await GamePaths.detect();

    subtitle = t('Loading mods…', '모드 불러오는 중…');
    notifyListeners();
    await loadCatalog();

    gameVersion = await GamePaths.detectGameVersion();
    subtitle = '';
    _continueBootstrap();
  }

  void skipUpdate() {
    updateTag = null;
    _updateUrl = null;
    _afterUpdateCheck();
  }

  Future<void> performUpdate() async {
    subtitle = t('Updating to $updateTag…', '$updateTag (으)로 업데이트 중…');
    notifyListeners();
    try {
      await Updater.performUpdate(_updateUrl!);
      // The detached helper swaps the install and relaunches once we exit.
      exit(0);
    } catch (_) {
      // Update failed — fall through to normal launch rather than blocking.
      updateTag = null;
      _updateUrl = null;
      await _afterUpdateCheck();
    }
  }

  void _continueBootstrap() {
    if (GamePaths.hasMelonLoader() || GamePaths.isUMMInstalled()) {
      phase = InstallPhase.installed;
    } else if (appleSilicon &&
        !isGameV2 &&
        !GamePaths.hasArm64Slice()) {
      phase = InstallPhase.needsVerify;
    } else {
      phase = InstallPhase.confirm;
    }
    notifyListeners();
  }

  /// Opens Steam's "verify integrity" for ADOFAI to restore the arm64 slice.
  void openSteamVerify() {
    _openUrl('steam://validate/977950');
  }

  /// Re-checks game state after the user verifies files (from needsVerify).
  void recheckVerify() {
    _continueBootstrap();
  }

  void _openUrl(String url) {
    try {
      if (Platform.isMacOS) {
        Process.run('open', [url]);
      } else if (Platform.isWindows) {
        Process.run('cmd', ['/c', 'start', '', url]);
      } else {
        Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  /// mods.json merged with modlist.org; one source down is a warning.
  Future<void> loadCatalog() async {
    try {
      catalog = await Catalog.load();
      catalogError = null;
    } catch (e) {
      catalog = null;
      catalogError = e.toString();
    }
    _refreshMods();
  }

  // MARK: - Derived state

  bool get isGameV2 => gameVersion?.startsWith('2.') ?? false;

  bool get hasMelonLoader => GamePaths.hasMelonLoader();
  bool get isUMMInstalled => GamePaths.isUMMInstalled();

  String get modsInstallPath =>
      hasMelonLoader ? GamePaths.melonModsPath : GamePaths.ummModsPath;

  /// The game build for catalog filtering; null (show everything) when the
  /// version is unknown.
  bool? get _v2 => gameVersion == null ? null : isGameV2;

  /// Mods for the detected game build, most downloaded first (mods.json-only
  /// ones have no count and go last). JALib-dependent mods work only under
  /// MelonLoader on macOS (the fork UMMBridge); elsewhere they're hidden and
  /// named in the banner.
  List<CatalogEntry> get browseEntries => [
        for (final e in catalog?.entries ?? const <CatalogEntry>[])
          if (e.visibleOn(_v2) && (!e.jalib || _jalibWorks)) e,
      ]..sort((a, b) => switch ((b.downloads ?? -1).compareTo(a.downloads ?? -1)) {
            0 => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            final c => c,
          });

  bool get _jalibWorks => hasMelonLoader && platform == 'macos';

  /// JALib-dependent mods hidden because they can't work here — listed in
  /// the banner.
  List<CatalogEntry> get unavailableJalib => [
        for (final e in catalog?.entries ?? const <CatalogEntry>[])
          if (e.visibleOn(_v2) && e.jalib && !_jalibWorks) e,
      ];

  bool isInstalled(String slug) => scan?.installed.contains(slug) ?? false;

  Upgrade? upgradeFor(String slug) =>
      scan?.upgrades.where((u) => u.entry.slug == slug).firstOrNull;

  ModTarget get _modTarget => ModTarget(
      gameRoot: GamePaths.gamePath,
      isV2: isGameV2,
      gameVersion: gameVersion,
      melon: hasMelonLoader,
      platform: platform);

  String get confirmationText {
    final v = gameVersion ?? '?';
    if (isGameV2) {
      return t(
        'Detected ADOFAI $v (Unity 2022 build).\n\n'
            'This installs Unity Mod Manager. On Apple Silicon the arm64 slice '
            'of the game binary is stripped so Steam launches under Rosetta '
            '(required for Harmony JIT patching on this build).',
        'ADOFAI $v (Unity 2022 빌드) 감지됨.\n\n'
            'Unity Mod Manager를 설치합니다. Apple Silicon에서는 Steam이 Rosetta로 '
            '실행되도록 게임 바이너리의 arm64 슬라이스가 제거됩니다.',
      );
    }
    final detected = gameVersion != null
        ? t('Detected ADOFAI $v.', 'ADOFAI $v 감지됨.')
        : t('ADOFAI version not detected.', 'ADOFAI 버전을 감지하지 못했습니다.');
    final umm = platform == 'linux'
        ? t("UMM — patches the game with UMM's own installer (needs mono and "
                'expect).',
            'UMM — UMM 설치 프로그램으로 게임을 패치합니다 (mono와 expect 필요).')
        : appleSilicon
            ? t('Native UMM — installs Unity Mod Manager directly.',
                '네이티브 UMM — Unity Mod Manager를 직접 설치합니다.')
            : t('UMM — patches the game the classic way (no Rosetta needed on '
                    'an Intel Mac).',
                'UMM — 기존 방식으로 게임을 패치합니다 (Intel Mac에서는 Rosetta가 '
                    '필요 없습니다).');
    return t(
      '$detected Choose a loader below.\n\n'
          '$umm\n'
          'MelonLoader (recommended) — installs MelonLoader + the UMMBridge '
          'plugin; mods load from UMMMods/.',
      '$detected 아래에서 로더를 선택하세요.\n\n'
          '$umm\n'
          'MelonLoader (권장) — MelonLoader와 UMMBridge 플러그인을 설치하며, '
          '모드는 UMMMods/에서 로드됩니다.',
    );
  }

  /// UMM is scripted on macOS and Linux; on Windows the confirm screen offers
  /// MelonLoader only.
  bool get canInstallUmm => InstallScripts.supportsUmm;

  // MARK: - Navigation

  void proceedFromConfirm(LoaderType loader) {
    selectedLoader = loader;
    startInstall();
  }

  // MARK: - Mods screen

  void openMods() {
    modError = null;
    phase = InstallPhase.mods;
    _refreshMods();
  }

  /// Installs [slug] and whatever it needs first, like `amm install --mod`.
  Future<void> installMod(String slug) => _modJob(slug, (at) async {
        final root = GamePaths.gamePath;
        final record = AmmRecord.load(root);
        final plan = ModOps.plan(catalog!, [slug], record);
        if (plan.missing.isNotEmpty) {
          throw ModOpsException(t('Unknown mod(s): ${plan.missing.join(', ')}',
              '알 수 없는 모드: ${plan.missing.join(', ')}'));
        }
        for (final e in plan.order) {
          at(e.slug);
          record.mods[e.slug] = await ModOps.install(e, _modTarget);
          record.save(root);
        }
      });

  Future<void> updateMod(String slug) => _modJob(slug, (at) async {
        final u = upgradeFor(slug);
        if (u != null) await _upgrade(u);
      });

  /// Like `amm upgrade` with no names: one failure doesn't stop the rest.
  Future<void> updateAll() => _modJob('*', (at) async {
        final failed = <String>[];
        for (final u in [...?scan?.upgrades]) {
          try {
            await _upgrade(u);
          } on ModOpsException catch (e) {
            failed.add('${u.entry.slug}: ${e.message}');
          } on ModDownloadException catch (e) {
            failed.add('${u.entry.slug}: ${e.message}');
          }
        }
        if (failed.isNotEmpty) {
          at(''); // the message names each mod already
          throw ModOpsException(failed.join('\n'));
        }
      });

  Future<void> _upgrade(Upgrade u) async {
    final root = GamePaths.gamePath;
    final record = AmmRecord.load(root);
    record.mods[u.entry.slug] = await ModOps.upgrade(u, _modTarget);
    record.save(root);
  }

  /// Runs one Mods-screen operation at a time; a failure shows as
  /// `slug: message` (the slug [job] last passed to `at`), then rescans.
  Future<void> _modJob(
      String busy, Future<void> Function(void Function(String) at) job) async {
    if (busySlug != null) return;
    busySlug = busy;
    modError = null;
    notifyListeners();
    var at = busy;
    String said(String m) => at.isEmpty ? m : '$at: $m';
    try {
      await job((s) => at = s);
    } on ModOpsException catch (e) {
      modError = said(e.message);
    } on ModDownloadException catch (e) {
      modError = said(e.message);
    } catch (e) {
      modError = said('$e');
    }
    busySlug = null;
    _refreshMods();
  }

  /// Removes an Installed-tab item. [keep] archives it (settings preserved,
  /// restorable). A recorded mod goes by slug, so all its paths go and its
  /// record entry is dropped; a file nothing recorded goes by path.
  void removeItem(InstalledItem item, {required bool keep}) {
    if (busySlug != null) return;
    modError = null;
    final root = GamePaths.gamePath;
    try {
      final file = item.file;
      if (file == null) {
        final record = AmmRecord.load(root);
        ModOps.remove(item.slug!, record, root, keep: keep, name: item.name);
        record.save(root);
      } else if (keep) {
        ModStore.archive(file);
      } else {
        ModStore.delete(file.path);
      }
    } catch (e) {
      modError = '${item.name}: $e';
    }
    _refreshMods();
  }

  /// Puts an archived mod back (and, for a recorded one, its record entry).
  void restoreMod(ArchivedMod a) => _archiveJob(a, () {
        final root = GamePaths.gamePath;
        final record = AmmRecord.load(root);
        ModOps.restore(a, record, root);
        record.save(root);
      });

  void deleteArchived(ArchivedMod a) => _archiveJob(a, () => ModStore.deleteArchived(a));

  void _archiveJob(ArchivedMod a, void Function() job) {
    if (busySlug != null) return;
    modError = null;
    try {
      job();
    } on ModOpsException catch (e) {
      modError = '${a.name}: ${e.message}';
    } catch (e) {
      modError = '${a.name}: $e';
    }
    _refreshMods();
  }

  void dismissModError() {
    modError = null;
    notifyListeners();
  }

  /// Rereads the record and the mods folders against the catalog (an empty
  /// one when it didn't load, so the Installed tab still works offline).
  void _refreshMods() {
    final root = GamePaths.gamePath;
    final c = catalog ?? Catalog(const []);
    try {
      final record = AmmRecord.load(root);
      final onDisk = ModStore.scanInstalled();
      scan = ModOps.upgrades(c, record, onDisk, _modTarget);
      installedItems = ModOps.installedItems(c, record, onDisk, root);
      archivedMods = ModStore.scanArchived();
    } catch (e) {
      modError = e.toString();
    }
    notifyListeners();
  }

  /// Returns to the landing screen, re-deriving it from the current loader
  /// state (so e.g. after an install you land on the "installed" menu) and
  /// clearing transient install state.
  void returnToMenu() {
    logEntries.clear();
    migratableMods = [];
    subtitle = '';
    modError = null;
    _continueBootstrap();
  }

  // MARK: - Install

  /// Installs the chosen loader; mods come after, from the Mods screen.
  void startInstall() {
    subtitle = t('Installing…', '설치 중…');
    phase = InstallPhase.installing;
    logEntries.clear();
    notifyListeners();
    _runInstall();
  }

  /// Which install method the GUI's loader choice maps to. An Intel Mac runs
  /// the x64 game as is, so UMM there is the same patch as under Rosetta.
  @visibleForTesting
  Method guiMethod(LoaderType l) => l == LoaderType.melonLoader
      ? Method.ml
      : (isGameV2 || !appleSilicon ? Method.rosetta : Method.native);

  Future<void> _runInstall() async {
    if (hasMelonLoader) {
      log(LogLevel.info, t('MelonLoader detected — skipping loader install.',
          'MelonLoader 감지됨 — 로더 설치를 건너뜁니다.'));
    } else if (isUMMInstalled) {
      log(LogLevel.info, t('Unity Mod Manager already installed — skipping.',
          'Unity Mod Manager가 이미 설치됨 — 건너뜁니다.'));
    } else {
      final name = selectedLoader == LoaderType.melonLoader
          ? 'MelonLoader'
          : 'Unity Mod Manager';
      final call = InstallScripts.install(guiMethod(selectedLoader));
      if (call == null) {
        log(LogLevel.error, t("$name isn't supported on this platform yet.",
            '$name은(는) 아직 이 플랫폼에서 지원되지 않습니다.'));
        _complete(false, t('Installation failed.', '설치 실패.'));
        return;
      }
      log(LogLevel.info, t('Installing $name…', '$name 설치 중…'));
      final code = await ScriptRunner.run(
          call: call, onLog: log, onSubtitle: _setSubtitle);
      if (code != 0) {
        log(LogLevel.error, t('$name installation failed.', '$name 설치 실패.'));
        _complete(false, t('Installation failed.', '설치 실패.'));
        return;
      }
      log(LogLevel.ok, t('$name installed.', '$name 설치 완료.'));
      _recordMethod(guiMethod(selectedLoader));
    }

    // MelonLoader on macOS/Linux injects via setup_helper.sh, which Steam must
    // be pointed at via launch options (Windows uses a proxy dll — no options).
    if (hasMelonLoader && !Platform.isWindows) {
      _applyLaunchOptions();
    }

    _complete(true, t('Installation complete.', '설치 완료.'));
  }

  // MARK: - Uninstall

  void startUninstall() {
    subtitle = t('Uninstalling…', '제거 중…');
    phase = InstallPhase.uninstalling;
    logEntries.clear();
    notifyListeners();
    _runUninstall();
  }

  Future<void> _runUninstall() async {
    final melon = hasMelonLoader;
    final name = melon ? 'MelonLoader' : 'Unity Mod Manager';
    final call = InstallScripts.uninstall(installedMethod(
        recorded: AmmRecord.load(GamePaths.gamePath).method,
        loader: melon ? LoaderKind.melonLoader : LoaderKind.umm,
        isV2: isGameV2,
        appleSilicon: appleSilicon,
        hasArm64Slice: GamePaths.hasArm64Slice()));
    if (call == null) {
      log(LogLevel.error, t("$name uninstall isn't supported on this platform yet.",
          '$name 제거는 아직 이 플랫폼에서 지원되지 않습니다.'));
      _complete(false, t('Uninstall failed.', '제거 실패.'));
      return;
    }
    log(LogLevel.info, t('Uninstalling $name…', '$name 제거 중…'));
    final code =
        await ScriptRunner.run(call: call, onLog: log, onSubtitle: _setSubtitle);
    if (code != 0) {
      log(LogLevel.error, t('$name uninstall failed.', '$name 제거 실패.'));
      _complete(false, t('Uninstall failed.', '제거 실패.'));
      return;
    }
    log(LogLevel.ok, t('$name uninstalled.', '$name 제거 완료.'));
    _recordMethod(null);
    if (melon && !Platform.isWindows) {
      _clearLaunchOptions();
    }
    _complete(true, t('Uninstall complete.', '제거 완료.'));
  }

  // MARK: - Migration (UMM → MelonLoader)

  void startMigration() {
    selectedLoader = LoaderType.melonLoader;
    subtitle = t('Migrating to MelonLoader…', 'MelonLoader로 마이그레이션 중…');
    phase = InstallPhase.migrating;
    logEntries.clear();
    notifyListeners();
    _runMigration();
  }

  Future<void> _runMigration() async {
    final unCall = InstallScripts.uninstall(installedMethod(
        recorded: AmmRecord.load(GamePaths.gamePath).method,
        loader: LoaderKind.umm,
        isV2: isGameV2,
        appleSilicon: appleSilicon,
        hasArm64Slice: GamePaths.hasArm64Slice()));
    final inCall = InstallScripts.install(Method.ml);
    if (unCall == null || inCall == null) {
      log(LogLevel.error, t("Migration isn't supported on this platform yet.",
          '마이그레이션은 아직 이 플랫폼에서 지원되지 않습니다.'));
      _complete(false, t('Migration failed.', '마이그레이션 실패.'));
      return;
    }

    log(LogLevel.info, t('Removing Unity Mod Manager…', 'Unity Mod Manager 제거 중…'));
    var code =
        await ScriptRunner.run(call: unCall, onLog: log, onSubtitle: _setSubtitle);
    if (code != 0) {
      log(LogLevel.error, t('Failed to remove Unity Mod Manager.', 'Unity Mod Manager 제거 실패.'));
      _complete(false, t('Migration failed.', '마이그레이션 실패.'));
      return;
    }
    log(LogLevel.ok, t('Unity Mod Manager removed.', 'Unity Mod Manager 제거 완료.'));

    _setSubtitle(t('Installing MelonLoader…', 'MelonLoader 설치 중…'));
    log(LogLevel.info, t('Installing MelonLoader…', 'MelonLoader 설치 중…'));
    code =
        await ScriptRunner.run(call: inCall, onLog: log, onSubtitle: _setSubtitle);
    if (code != 0) {
      log(LogLevel.error, t('MelonLoader installation failed.', 'MelonLoader 설치 실패.'));
      _complete(false, t('Migration failed.', '마이그레이션 실패.'));
      return;
    }
    log(LogLevel.ok, t('MelonLoader installed.', 'MelonLoader 설치 완료.'));
    _recordMethod(Method.ml);
    if (!Platform.isWindows) {
      _applyLaunchOptions();
    }

    final found = ModStore.findUmmMods(GamePaths.ummModsPath);
    if (found.isEmpty) {
      _complete(true, t('Migration complete.', '마이그레이션 완료.'));
    } else {
      migratableMods = found;
      _setSubtitle(t('Migration almost done…', '마이그레이션 거의 완료…'));
      phase = InstallPhase.confirmModMove;
      notifyListeners();
    }
  }

  void moveMigratableMods() {
    // Load before moving: loading drops entries whose paths are gone.
    final root = GamePaths.gamePath;
    final record = AmmRecord.load(root);
    final moved = ModStore.moveMods(
        migratableMods, GamePaths.ummModsPath, GamePaths.melonModsPath,
        onError: (name, e) {
      log(LogLevel.error, t('Failed to move $name.', '$name 이동 실패.'));
      log(LogLevel.detail, e.toString());
    });
    try {
      record
        ..movePaths('Mods', 'UMMMods', moved)
        ..save(root);
    } catch (e) {
      log(LogLevel.detail, e.toString());
    }
    log(LogLevel.ok, t('Moved ${moved.length} mod(s) to UMMMods/.', '${moved.length}개 모드를 UMMMods/로 이동했습니다.'));
    migratableMods = [];
    _complete(true, t('Migration complete.', '마이그레이션 완료.'));
  }

  void skipMigratableMods() {
    migratableMods = [];
    _complete(
        true,
        t('Migration complete. UMM mods left in Mods/.',
            '마이그레이션 완료. UMM 모드는 Mods/에 남아 있습니다.'));
  }

  // MARK: - Helpers

  void _recordMethod(Method? m) {
    try {
      final root = GamePaths.gamePath;
      AmmRecord.load(root)
        ..method = m
        ..save(root);
    } catch (e) {
      log(LogLevel.detail, e.toString());
    }
  }

  void _applyLaunchOptions() {
    final helper = p.join(GamePaths.gamePath, 'setup_helper.sh');
    final o = SteamConfig.setLaunchOptions(helper);
    if (o.noConfig) {
      log(LogLevel.info, t('Couldn\'t set Steam launch options automatically — set them manually:',
          'Steam 실행 옵션을 자동으로 설정하지 못했습니다 — 수동으로 설정하세요:'));
      log(LogLevel.detail, '"$helper" %command%');
    } else if (o.error != null) {
      log(LogLevel.error, t('Failed to set Steam launch options.', 'Steam 실행 옵션 설정 실패.'));
      log(LogLevel.detail, o.error!);
    } else if (o.updated > 0) {
      log(LogLevel.ok, t('Steam launch options set.', 'Steam 실행 옵션을 설정했습니다.'));
      if (o.steamRunning) {
        log(LogLevel.info, t('Fully quit and reopen Steam for it to take effect.',
            '적용하려면 Steam을 완전히 종료한 후 다시 여세요.'));
      }
    }
  }

  void _clearLaunchOptions() {
    final o = SteamConfig.clearLaunchOptions();
    if (o.updated > 0) {
      log(LogLevel.ok, t('Cleared Steam launch options.', 'Steam 실행 옵션을 지웠습니다.'));
      if (o.steamRunning) {
        log(LogLevel.info, t('Fully quit and reopen Steam for it to take effect.',
            '적용하려면 Steam을 완전히 종료한 후 다시 여세요.'));
      }
    }
  }

  void _setSubtitle(String s) {
    subtitle = s;
    notifyListeners();
  }

  void log(LogLevel level, String message) {
    logEntries.add(LogEntry(level, message));
    notifyListeners();
  }

  void _complete(bool success, String message) {
    completeSuccess = success;
    completeMessage = message;
    phase = InstallPhase.complete;
    notifyListeners();
  }
}
