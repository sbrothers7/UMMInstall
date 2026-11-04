import 'dart:convert';
import 'dart:io';

import 'package:amm_core/amm_core.dart';
import 'package:path/path.dart' as p;

/// User settings in `$XDG_CONFIG_HOME/amm/config.json` (else
/// `~/.config/amm/config.json`).
class Config {
  Method defaultMethod = Method.ml;

  /// Whether amm updates itself and the GUI before a command, once a day.
  bool autoUpdate = true;

  /// When amm last looked for a release on its own.
  DateTime? lastUpdateCheck;

  /// Where [load] read from, so [save] writes back to the same place.
  Map<String, String>? _env;

  static String path({Map<String, String>? env}) {
    env ??= Platform.environment;
    final xdg = env['XDG_CONFIG_HOME'];
    final base = xdg != null && xdg.isNotEmpty
        ? xdg
        : p.join(env['HOME'] ?? '', '.config');
    return p.join(base, 'amm', 'config.json');
  }

  /// A missing or corrupt file gives the defaults.
  static Config load({Map<String, String>? env}) {
    final c = Config().._env = env;
    try {
      final j =
          jsonDecode(File(path(env: env)).readAsStringSync())
              as Map<String, dynamic>;
      c.defaultMethod =
          Method.parse(j['default'] as String? ?? '') ?? Method.ml;
      c.autoUpdate = j['autoUpdate'] as bool? ?? true;
      c.lastUpdateCheck = DateTime.tryParse(
        j['lastUpdateCheck'] as String? ?? '',
      );
    } catch (_) {}
    return c;
  }

  void save({Map<String, String>? env}) {
    final f = File(path(env: env ?? _env));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(
      jsonEncode({
        'default': defaultMethod.name,
        'autoUpdate': autoUpdate,
        if (lastUpdateCheck != null)
          'lastUpdateCheck': lastUpdateCheck!.toUtc().toIso8601String(),
      }),
    );
  }
}
