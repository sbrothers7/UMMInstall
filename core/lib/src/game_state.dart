import 'dart:io';

import 'models.dart';
import 'platform/game_paths.dart';
import 'package:path/path.dart' as p;

enum LoaderKind { none, melonLoader, umm }

/// A snapshot of the machine and game, the input to the method rules.
class GameFacts {
  final String os;
  final bool found;
  final String gamePath;
  final String? version;
  final int? major;
  final bool appleSilicon;
  final bool hasArm64Slice;
  final LoaderKind loader;

  const GameFacts({
    required this.os,
    required this.found,
    required this.gamePath,
    required this.version,
    required this.major,
    required this.appleSilicon,
    required this.hasArm64Slice,
    required this.loader,
  });

  bool get isV2 => major == 2;

  /// Runs game discovery, then reads the current state from [GamePaths].
  static Future<GameFacts> detect() async {
    await GamePaths.detect();
    return GameFacts(
      os: Platform.operatingSystem,
      found: GamePaths.gameExists(),
      gamePath: GamePaths.gamePath,
      version: await GamePaths.detectGameVersion(),
      major: await GamePaths.detectGameMajor(),
      appleSilicon: GamePaths.isAppleSilicon(),
      hasArm64Slice: GamePaths.hasArm64Slice(),
      loader: GamePaths.hasMelonLoader()
          ? LoaderKind.melonLoader
          : GamePaths.isUMMInstalled()
          ? LoaderKind.umm
          : LoaderKind.none,
    );
  }
}

sealed class Decision {
  const Decision();
}

/// Install with [method]; if [confirm] is set, ask the user first.
class Proceed extends Decision {
  final Method method;
  final String? confirm;
  const Proceed(this.method, {this.confirm});
}

class Refuse extends Decision {
  final String message;
  const Refuse(this.message);
}

/// Decides which method may be used, where `requested ?? fallback` is the
/// wanted one.
Decision resolveInstall(
  GameFacts f, {
  Method? requested,
  required Method fallback,
}) {
  final m = requested ?? fallback;
  if (f.os != 'macos' && f.os != 'linux') {
    return const Refuse('amm supports macOS and Linux only.');
  }
  if (f.os == 'linux') {
    return m == Method.ml
        ? const Proceed(Method.ml)
        : const Refuse('On Linux only MelonLoader is supported. Use --ml.');
  }
  if (f.isV2) {
    if (requested == Method.ml || requested == Method.native) {
      return const Refuse(
        'MelonLoader and native UMM are untested on game v2. Use --rosetta.',
      );
    }
    return const Proceed(Method.rosetta);
  }
  if (m == Method.native && !f.appleSilicon) {
    return const Refuse('Native UMM needs an Apple Silicon Mac.');
  }
  if ((m == Method.ml || m == Method.native) &&
      f.appleSilicon &&
      !f.hasArm64Slice) {
    return const Refuse(
      'The game has lost its arm64 slice. Verify game files in Steam '
      '(steam://validate/977950), then try again.',
    );
  }
  if (m == Method.rosetta) {
    return Proceed(
      Method.rosetta,
      // An Intel Mac runs the x64 game as is: the same patch, no Rosetta.
      confirm: f.appleSilicon
          ? 'UMM under Rosetta is untested on game v3. It strips the arm64 '
                'slice, so you must verify game files in Steam before --ml or '
                '--native work again. Continue?'
          : 'UMM via the classic patch is untested on game v3. Continue?',
    );
  }
  return Proceed(m);
}

/// Guesses the method of an existing install from the loader found.
Method inferMethod({
  required LoaderKind loader,
  required bool isV2,
  required bool appleSilicon,
  required bool hasArm64Slice,
}) {
  if (loader == LoaderKind.umm) {
    return isV2 || !appleSilicon || !hasArm64Slice
        ? Method.rosetta
        : Method.native;
  }
  return Method.ml;
}

/// The method of an existing install: [recorded] when it agrees with the
/// loader on disk, else [inferMethod]'s guess.
Method installedMethod({
  required Method? recorded,
  required LoaderKind loader,
  required bool isV2,
  required bool appleSilicon,
  required bool hasArm64Slice,
}) {
  if (recorded != null &&
      (recorded == Method.ml) == (loader == LoaderKind.melonLoader)) {
    return recorded;
  }
  return inferMethod(
    loader: loader,
    isV2: isV2,
    appleSilicon: appleSilicon,
    hasArm64Slice: hasArm64Slice,
  );
}

/// MelonLoader files that are absent under the game folder.
List<String> missingLoaderFiles(GameFacts f) {
  if (f.loader != LoaderKind.melonLoader) return [];
  final bootstrap = f.os == 'macos'
      ? 'MelonLoader.Bootstrap.dylib'
      : 'MelonLoader.Bootstrap.so';
  return [
    for (final n in ['MelonLoader', 'setup_helper.sh', 'UMMMods', bootstrap])
      if (FileSystemEntity.typeSync(p.join(f.gamePath, n)) ==
          FileSystemEntityType.notFound)
        n,
  ];
}
