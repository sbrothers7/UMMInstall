import 'package:flutter/material.dart';

import '../models.dart';
import 'app_scope.dart';
import 'confirm_view.dart';
import 'installed_view.dart';
import 'manage_mods_view.dart';
import 'needs_verify_view.dart';
import 'mod_picker_view.dart';
import 'progress_view.dart';
import 'updating_view.dart';

class ContentView extends StatelessWidget {
  const ContentView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    Widget body;
    switch (state.phase) {
      case InstallPhase.updating:
        body = const UpdatingView();
      case InstallPhase.confirm:
        body = const ConfirmView();
      case InstallPhase.needsVerify:
        body = const NeedsVerifyView();
      case InstallPhase.installed:
        body = const InstalledView();
      case InstallPhase.picker:
        body = const ModPickerView();
      case InstallPhase.manageMods:
        body = const ManageModsView();
      case InstallPhase.installingBrew:
      case InstallPhase.installing:
      case InstallPhase.uninstalling:
      case InstallPhase.migrating:
      case InstallPhase.confirmModMove:
      case InstallPhase.complete:
        body = const ProgressView();
    }

    return Stack(
      children: [
        Positioned.fill(child: body),
        const Positioned(top: 12, right: 18, child: LanguagePicker()),
      ],
    );
  }
}

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    Widget button(Language lang, String label) {
      final selected = state.language == lang;
      return InkWell(
        onTap: () => state.setLanguage(lang),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Language.en, 'EN'),
        Text('  /  ',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.3))),
        button(Language.ko, 'KR'),
      ],
    );
  }
}
