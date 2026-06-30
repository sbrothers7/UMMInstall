import 'dart:io';
import '../models.dart';

/// Resolves which loader script to run for the current platform + loader.
/// Returns null when a platform/loader combination isn't supported yet.
class InstallScripts {
  static const _base =
      'https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/';

  /// Native UMM is only scripted on macOS for now; Windows/Linux use MelonLoader.
  static bool get supportsNativeUmm => Platform.isMacOS;

  static String? installUrl(LoaderType loader) {
    if (Platform.isMacOS) {
      return _base +
          (loader == LoaderType.melonLoader
              ? 'macos/adofai-melonloader.sh'
              : 'macos/adofai-umm.sh');
    }
    if (Platform.isWindows) {
      return loader == LoaderType.melonLoader
          ? '${_base}windows/adofai-melonloader.ps1'
          : null;
    }
    // TODO: Linux scripts.
    return null;
  }

  static String? uninstallUrl({required bool isMelon}) {
    if (Platform.isMacOS) {
      return _base +
          (isMelon
              ? 'macos/adofai-melonloader-uninstall.sh'
              : 'macos/adofai-umm-uninstall.sh');
    }
    if (Platform.isWindows) {
      return isMelon ? '${_base}windows/adofai-melonloader-uninstall.ps1' : null;
    }
    return null;
  }
}
