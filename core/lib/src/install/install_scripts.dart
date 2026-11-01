import 'dart:io';
import '../models.dart';
import '../platform/game_paths.dart';

/// Resolves which loader script to run for the current platform + loader.
/// Returns null when a platform/loader combination isn't supported yet.
class InstallScripts {
  static const _base =
      'https://raw.githubusercontent.com/sbrothers7/UMMInstall/v2/';

  /// Native UMM is only scripted on macOS for now; Windows/Linux use MelonLoader.
  static bool get supportsNativeUmm => Platform.isMacOS;

  /// The install script for [m] on [os], or null when unsupported.
  static ScriptCall? install(Method m, {String? os, String? gamePath}) =>
      _call(m, os, gamePath, 'adofai-melonloader.sh', 'adofai-umm.sh',
          'adofai-melonloader.ps1');

  /// The uninstall script for [m] on [os], or null when unsupported.
  static ScriptCall? uninstall(Method m, {String? os, String? gamePath}) =>
      _call(m, os, gamePath, 'adofai-melonloader-uninstall.sh',
          'adofai-umm-uninstall.sh', 'adofai-melonloader-uninstall.ps1');

  static ScriptCall? _call(Method m, String? os, String? gamePath,
      String mlSh, String ummSh, String mlPs) {
    switch (os ?? Platform.operatingSystem) {
      case 'macos':
        return m == Method.ml
            ? ScriptCall('${_base}macos/$mlSh')
            : ScriptCall('${_base}macos/$ummSh', [m.name]);
      case 'linux':
        return m == Method.ml
            ? ScriptCall('${_base}linux/$mlSh', [gamePath ?? GamePaths.gamePath])
            : null;
      case 'windows':
        return m == Method.ml ? ScriptCall('${_base}windows/$mlPs') : null;
    }
    return null;
  }
}

/// A script URL plus the arguments to pass it.
class ScriptCall {
  final String url;
  final List<String> args;
  const ScriptCall(this.url, [this.args = const []]);

  @override
  bool operator ==(Object other) =>
      other is ScriptCall &&
      other.url == url &&
      other.args.length == args.length &&
      [for (var i = 0; i < args.length; i++) args[i] == other.args[i]]
          .every((e) => e);

  @override
  int get hashCode => Object.hash(url, Object.hashAll(args));

  @override
  String toString() => 'ScriptCall($url, $args)';
}
