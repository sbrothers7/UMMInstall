import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:path/path.dart' as p;

import 'context.dart';

String _loaderName(Method m) =>
    m == Method.ml ? 'MelonLoader' : 'Unity Mod Manager';

/// The installed loader's method: the recorded one unless the loader on
/// disk contradicts it.
Method currentMethod(GameFacts f) => installedMethod(
  recorded: AmmRecord.load(f.gamePath).method,
  loader: f.loader,
  isV2: f.isV2,
  appleSilicon: f.appleSilicon,
  hasArm64Slice: f.hasArm64Slice,
);

/// Prints the not-found error; true when the game is there.
bool gameFound(Ctx c, GameFacts f) {
  if (!f.found) {
    c.out.log(LogLevel.error, 'ADOFAI not found (looked in ${f.gamePath}).');
  }
  return f.found;
}

/// `amm install [--ml|--native|--rosetta]`. With a loader present it only
/// prints the status.
Future<int> install(Ctx c, {Method? method}) async {
  final f = await c.facts();
  if (!gameFound(c, f)) return 1;
  if (f.loader != LoaderKind.none) {
    final current = currentMethod(f);
    printStatus(c, f, current);
    if (method != null && method != current) {
      c.out.line('To switch, run: amm reinstall --${method.name}');
    }
    return 0;
  }
  final d = resolveInstall(
    f,
    requested: method,
    fallback: c.config.defaultMethod,
  );
  switch (d) {
    case Refuse(:final message):
      c.out.log(LogLevel.error, message);
      return 1;
    case Proceed(:final method, :final confirm):
      if (confirm != null && !c.out.confirm(confirm, yes: c.yes)) return 1;
      return _installMethod(c, f, method);
  }
}

/// `amm reinstall [--ml|--native|--rosetta]`: the same loader again, or a
/// switch to another one.
Future<int> reinstall(Ctx c, {Method? method}) async {
  final f = await c.facts();
  if (!gameFound(c, f)) return 1;
  if (f.loader == LoaderKind.none) {
    c.out.line('No loader installed; installing.');
    return install(c, method: method);
  }
  final current = currentMethod(f);
  final target = method ?? current;
  if (target == current) {
    if (!c.out.confirm(
      'Reinstall ${_loaderName(current)} (${current.name})? Mods stay in place.',
      yes: c.yes,
    )) {
      return 1;
    }
    final code = await _uninstallCurrent(c, f, current);
    return code != 0 ? code : _installMethod(c, f, current);
  }
  // Rosetta strips the arm64 slice, so ml/native can't go on until Steam
  // restores it; resolveInstall would refuse, so this comes first.
  if (current == Method.rosetta &&
      !f.isV2 &&
      f.appleSilicon &&
      !f.hasArm64Slice) {
    if (!c.out.confirm(
      'Switch from ${current.name} to ${target.name}? This uninstalls '
      '${current.name}; you then verify game files in Steam.',
      yes: c.yes,
    )) {
      return 1;
    }
    final code = await _uninstallCurrent(c, f, current);
    if (code != 0) return code;
    c.out.line(
      'Verify game files in Steam to restore the arm64 slice: '
      'steam://validate/${SteamConfig.appId}',
    );
    c.out.line('Then run: amm install --${target.name}');
    return 0;
  }
  // Resolve before uninstalling so a refusal changes nothing.
  final d = resolveInstall(
    f,
    requested: target,
    fallback: c.config.defaultMethod,
  );
  switch (d) {
    case Refuse(:final message):
      c.out.log(LogLevel.error, message);
      return 1;
    case Proceed(:final method, :final confirm):
      final extra = confirm == null ? '' : ' $confirm';
      if (!c.out.confirm(
        'Switch from ${current.name} to ${method.name}? This uninstalls '
        '${current.name}, installs ${method.name}, then offers to move your '
        'mods.$extra',
        yes: c.yes,
      )) {
        return 1;
      }
      final code = await _uninstallCurrent(c, f, current);
      if (code != 0) return code;
      return _installMethod(c, f, method);
  }
}

/// `amm uninstall`: removes the loader, leaves the mods where they are.
Future<int> uninstall(Ctx c) async {
  final f = await c.facts();
  if (!gameFound(c, f)) return 1;
  if (f.loader == LoaderKind.none) {
    c.out.line('No mod loader installed.');
    return 0;
  }
  final current = currentMethod(f);
  if (!c.out.confirm(
    'Remove ${_loaderName(current)} from ${f.gamePath}? Mods stay in place.',
    yes: c.yes,
  )) {
    return 1;
  }
  return _uninstallCurrent(c, f, current);
}

/// `amm status`: reads the disk only.
Future<int> status(Ctx c) async {
  final f = await c.facts();
  if (!gameFound(c, f)) return 1;
  printStatus(c, f, currentMethod(f));
  return 0;
}

/// What `amm status` prints, and `amm install` when a loader is already there.
void printStatus(Ctx c, GameFacts f, Method current) {
  final missing = missingLoaderFiles(f);
  final launch = SteamConfig.launchOptionsSet();
  final archived = ModStore.scanArchived().length;
  final rows = [
    ('Game:', f.gamePath),
    (
      'Version:',
      f.version ??
          (f.major != null ? 'v${f.major} (exact version unknown)' : 'unknown'),
    ),
    (
      'Loader:',
      switch (f.loader) {
        LoaderKind.none => 'none',
        LoaderKind.melonLoader => 'MelonLoader (ml)',
        // Linux has no UMM methods to tell apart.
        LoaderKind.umm when f.os == 'linux' => 'Unity Mod Manager',
        LoaderKind.umm => 'Unity Mod Manager (${current.name})',
      },
    ),
    ('Files:', missing.isEmpty ? 'complete' : 'missing: ${missing.join(', ')}'),
    if (f.loader == LoaderKind.melonLoader)
      (
        'Launch options:',
        launch == null
            ? 'Steam config not found'
            : (launch ? 'set' : 'not set'),
      ),
    if (f.appleSilicon)
      ('arm64 slice:', f.hasArm64Slice ? 'present' : 'stripped'),
    (
      'Mods:',
      '${ModStore.scanInstalled().length} installed'
          '${archived > 0 ? ', $archived archived' : ''}',
    ),
  ];
  final w = rows.map((r) => r.$1.length).reduce((a, b) => a > b ? a : b);
  for (final (label, value) in rows) {
    c.out.line('${label.padRight(w)} $value');
  }
}

Future<int> _runLoaderScript(
  Ctx c,
  ScriptCall? call,
  Method m,
  String failed,
) async {
  if (call == null) {
    c.out.line("${m.name} isn't supported on this platform.");
    return 1;
  }
  final code = await c.runScript(
    call: call,
    onLog: c.out.log,
    onSubtitle: c.out.subtitle,
  );
  if (code != 0) {
    c.out.log(LogLevel.error, failed);
    return 1;
  }
  return 0;
}

Future<int> _installMethod(Ctx c, GameFacts f, Method m) async {
  c.out.line('Installing ${_loaderName(m)} (${m.name}) into ${f.gamePath}…');
  final code = await _runLoaderScript(
    c,
    InstallScripts.install(m, os: f.os, gamePath: f.gamePath),
    m,
    'Install failed.',
  );
  if (code != 0) return code;
  _afterInstall(c, f, m);
  return 0;
}

Future<int> _uninstallCurrent(Ctx c, GameFacts f, Method current) async {
  final code = await _runLoaderScript(
    c,
    InstallScripts.uninstall(current, os: f.os, gamePath: f.gamePath),
    current,
    'Uninstall failed.',
  );
  if (code != 0) return code;
  if (current == Method.ml) {
    final o = SteamConfig.clearLaunchOptions();
    if (o.error != null) {
      c.out.log(LogLevel.error, 'Failed to clear Steam launch options.');
      c.out.log(LogLevel.detail, o.error!);
    } else if (o.updated > 0) {
      c.out.log(LogLevel.ok, 'Cleared Steam launch options.');
      _steamNote(c, o);
    }
  }
  AmmRecord.load(f.gamePath)
    ..method = null
    ..save(f.gamePath);
  return 0;
}

void _steamNote(Ctx c, SteamLaunchOptionsOutcome o) {
  if (o.steamRunning) {
    c.out.log(
      LogLevel.info,
      'Fully quit and reopen Steam for it to take effect.',
    );
  }
}

/// Launch options (ml), the offer to move mods between `Mods/` and
/// `UMMMods/`, and the record update.
void _afterInstall(Ctx c, GameFacts f, Method m) {
  final record = AmmRecord.load(f.gamePath);
  final mods = p.join(f.gamePath, 'Mods');
  final ummMods = p.join(f.gamePath, 'UMMMods');

  void move(List<String> names, String from, String to, String question) {
    if (names.isEmpty || !c.out.confirm(question, yes: c.yes)) return;
    final moved = ModStore.moveMods(
      names,
      p.join(f.gamePath, from),
      p.join(f.gamePath, to),
      onError: (name, e) {
        c.out.log(LogLevel.error, "Couldn't move $name.");
        c.out.log(LogLevel.detail, e.toString());
      },
    );
    record.movePaths(from, to, moved);
    c.out.log(LogLevel.ok, 'Moved ${moved.length} mod(s).');
  }

  if (m == Method.ml) {
    final helper = p.join(f.gamePath, 'setup_helper.sh');
    final o = SteamConfig.setLaunchOptions(helper);
    if (o.noConfig) {
      c.out.log(
        LogLevel.info,
        "Couldn't set Steam launch options automatically — set them manually:",
      );
      c.out.log(LogLevel.detail, '"$helper" %command%');
    } else if (o.error != null) {
      c.out.log(LogLevel.error, 'Failed to set Steam launch options.');
      c.out.log(LogLevel.detail, o.error!);
    } else if (o.updated > 0) {
      c.out.log(LogLevel.ok, 'Steam launch options set.');
      _steamNote(c, o);
    }
    final names = ModStore.findUmmMods(mods);
    move(
      names,
      'Mods',
      'UMMMods',
      'Move ${names.length} UMM mod(s) from Mods/ to UMMMods/ so UMMBridge loads them?',
    );
  } else {
    final dirs = Directory(ummMods).existsSync()
        ? [
            for (final e in Directory(ummMods).listSync())
              if (e is Directory) p.basename(e.path),
          ]
        : <String>[];
    move(
      dirs,
      'UMMMods',
      'Mods',
      'Move ${dirs.length} mod(s) from UMMMods/ back to Mods/?',
    );
    final hasDll =
        Directory(mods).existsSync() &&
        Directory(mods).listSync().any(
          (e) => e is File && p.extension(e.path).toLowerCase() == '.dll',
        );
    if (hasDll) {
      c.out.line("MelonLoader mods in Mods/ won't load under UMM.");
    }
  }
  record.method = m;
  record.save(f.gamePath);
}
