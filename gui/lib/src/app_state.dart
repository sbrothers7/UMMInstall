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

  List<Mod> mods = [];
  String? modsError;
  final Set<String> selectedMods = {};
  LoaderType selectedLoader = LoaderType.umm;

  final List<LogEntry> logEntries = [];
  List<String> migratableMods = [];

  List<InstalledMod> installedMods = [];
  List<ArchivedMod> archivedMods = [];
  final Set<String> selectedForDelete = {};

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
    await loadMods();

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
    } else if (GamePaths.isAppleSilicon() &&
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

  Future<void> loadMods() async {
    try {
      mods = await ModRegistry.fetch();
      modsError = null;
    } catch (e) {
      mods = [];
      modsError = e.toString();
    }
    notifyListeners();
  }

  void reloadMods() {
    loadMods();
  }

  // MARK: - Derived state

  bool get isGameV2 => gameVersion?.startsWith('2.') ?? false;

  bool get hasMelonLoader => GamePaths.hasMelonLoader();
  bool get isUMMInstalled => GamePaths.isUMMInstalled();

  String get modsInstallPath =>
      hasMelonLoader ? GamePaths.melonModsPath : GamePaths.ummModsPath;

  /// Mods shown in the picker for the detected game version. JALib-dependent
  /// mods are hidden (and surfaced via the banner) while JALib is broken.
  List<Mod> get visibleMods => mods.where((m) {
        if (m.jalib) return false;
        return isGameV2 ? m.v2 : m.v3;
      }).toList();

  /// JALib-dependent mods that would otherwise be available for this game
  /// version — listed in the picker's "unavailable" banner.
  List<Mod> get unavailableJalibMods =>
      mods.where((m) => m.jalib && (isGameV2 ? m.v2 : m.v3)).toList();

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
    return t(
      '$detected Choose a loader below.\n\n'
          'Native UMM — installs Unity Mod Manager directly.\n'
          'MelonLoader (recommended) — installs MelonLoader + the UMMCompat '
          'plugin; mods load from UMMMods/.',
      '$detected 아래에서 로더를 선택하세요.\n\n'
          '네이티브 UMM — Unity Mod Manager를 직접 설치합니다.\n'
          'MelonLoader (권장) — MelonLoader와 UMMCompat 플러그인을 설치하며, '
          '모드는 UMMMods/에서 로드됩니다.',
    );
  }

  /// Native UMM is only scripted on macOS for now; elsewhere the confirm
  /// screen offers MelonLoader only.
  bool get canInstallUmm => InstallScripts.supportsNativeUmm;

  // MARK: - Navigation

  void proceedFromConfirm(LoaderType loader) {
    selectedLoader = loader;
    phase = InstallPhase.picker;
    notifyListeners();
  }

  void proceedFromInstalled() {
    phase = InstallPhase.picker;
    notifyListeners();
  }

  // MARK: - Manage / delete mods

  void openManageMods() {
    installedMods = ModStore.scanInstalled();
    archivedMods = ModStore.scanArchived();
    selectedForDelete.clear();
    phase = InstallPhase.manageMods;
    notifyListeners();
  }

  void toggleDeleteSelection(String path) {
    if (!selectedForDelete.remove(path)) selectedForDelete.add(path);
    notifyListeners();
  }

  /// Permanently removes installed mods from disk.
  void deleteMods(Iterable<String> paths) {
    for (final path in paths) {
      ModStore.delete(path);
    }
    selectedForDelete.removeAll(paths.toSet());
    _refreshMods();
  }

  /// "Keep Data": moves installed mods into the persistent archive so they stop
  /// loading but can be restored later (settings preserved).
  void archiveMods(Iterable<String> paths) {
    final archiveRoot = GamePaths.archivePath;
    Directory(archiveRoot).createSync(recursive: true);
    for (final path in paths) {
      final mod = installedMods.firstWhere(
        (m) => m.path == path,
        orElse: () => InstalledMod(
          name: p.basename(path),
          path: path,
          isDirectory: FileSystemEntity.isDirectorySync(path),
        ),
      );
      ModStore.archive(mod);
    }
    selectedForDelete.removeAll(paths.toSet());
    _refreshMods();
  }

  void restoreMod(ArchivedMod a) {
    ModStore.restore(a);
    _refreshMods();
  }

  void deleteArchived(ArchivedMod a) {
    ModStore.deleteArchived(a);
    _refreshMods();
  }

  void _refreshMods() {
    installedMods = ModStore.scanInstalled();
    archivedMods = ModStore.scanArchived();
    notifyListeners();
  }

  /// Returns to the landing screen, re-deriving it from the current loader
  /// state (so e.g. after an install you land on the "installed" menu) and
  /// clearing transient install state.
  void returnToMenu() {
    logEntries.clear();
    selectedMods.clear();
    migratableMods = [];
    subtitle = '';
    _continueBootstrap();
  }

  void toggleMod(String id) {
    if (!selectedMods.remove(id)) selectedMods.add(id);
    notifyListeners();
  }

  void setAllSelected(bool selected) {
    selectedMods.clear();
    if (selected) selectedMods.addAll(visibleMods.map((m) => m.id));
    notifyListeners();
  }

  // MARK: - Install

  void startInstall({bool skipMods = false}) {
    if (skipMods) selectedMods.clear();
    subtitle = t('Installing…', '설치 중…');
    phase = InstallPhase.installing;
    logEntries.clear();
    notifyListeners();
    _runInstall();
  }

  /// Which install method the GUI's loader choice maps to.
  Method _guiMethod(LoaderType l) => l == LoaderType.melonLoader
      ? Method.ml
      : (isGameV2 ? Method.rosetta : Method.native);

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
      final call = InstallScripts.install(_guiMethod(selectedLoader));
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
      _recordMethod(_guiMethod(selectedLoader));
    }

    // MelonLoader on macOS/Linux injects via setup_helper.sh, which Steam must
    // be pointed at via launch options (Windows uses a proxy dll — no options).
    if (hasMelonLoader && !Platform.isWindows) {
      _applyLaunchOptions();
    }

    final selected = mods.where((m) => selectedMods.contains(m.id)).toList();
    final melon = hasMelonLoader;
    final modsDir = modsInstallPath;
    final failed = <String>[];
    final recorded = <String, RecordEntry>{};
    for (var i = 0; i < selected.length; i++) {
      final mod = selected[i];
      // A live progress-bar log row that morphs into the result line when done.
      final entry = LogEntry(
        LogLevel.info,
        t('Downloading ${mod.id} (${i + 1}/${selected.length})…',
            '${mod.id} 다운로드 중 (${i + 1}/${selected.length})…'),
        progress: -1, // indeterminate until the first ratio arrives
      );
      logEntries.add(entry);
      notifyListeners();

      var lastPct = -1;
      try {
        final placed = await ModDownloader.install(
          mod: mod,
          isGameV2: isGameV2,
          isMelonLoader: melon,
          gameRoot: GamePaths.gamePath,
          modsDir: modsDir,
          onProgress: (f) {
            final pct = (f * 100).round();
            if (pct != lastPct) {
              lastPct = pct;
              entry.progress = f;
              notifyListeners();
            }
          },
        );
        recorded[mod.slug] = RecordEntry(
          source: 'mods.json',
          version: mod.resolvedVersion(isGameV2: isGameV2, isMelonLoader: melon),
          paths: [
            for (final path in placed)
              p.relative(path, from: GamePaths.gamePath).replaceAll(r'\', '/'),
          ],
        );
        entry
          ..progress = null
          ..level = LogLevel.ok
          ..message = t('${mod.id} installed.', '${mod.id} 설치 완료.');
        notifyListeners();
      } catch (e) {
        entry
          ..progress = null
          ..level = LogLevel.error
          ..message = t('${mod.id} failed to install.', '${mod.id} 설치 실패.');
        log(LogLevel.detail, e.toString());
        failed.add(mod.id);
      }
    }
    if (recorded.isNotEmpty) {
      try {
        final root = GamePaths.gamePath;
        final rec = AmmRecord.load(root);
        rec.mods.addAll(recorded);
        rec.save(root);
      } catch (e) {
        log(LogLevel.detail, e.toString());
      }
    }

    _complete(
      failed.isEmpty,
      failed.isEmpty
          ? t('Installation complete.', '설치 완료.')
          : t('Installation finished with errors.', '오류와 함께 설치가 완료되었습니다.'),
    );
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
        appleSilicon: GamePaths.isAppleSilicon(),
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
        appleSilicon: GamePaths.isAppleSilicon(),
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
