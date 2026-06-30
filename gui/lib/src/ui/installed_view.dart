import 'dart:io';
import 'package:flutter/material.dart';

import 'app_scope.dart';

class InstalledView extends StatelessWidget {
  const InstalledView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final isMelon = state.hasMelonLoader;
    final canMigrate = !isMelon && state.isUMMInstalled;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMelon
                ? state.t('MelonLoader is installed', 'MelonLoader가 설치되어 있습니다')
                : state.t('Unity Mod Manager is installed',
                    'Unity Mod Manager가 설치되어 있습니다'),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            state.gameVersion != null
                ? state.t('Detected ADOFAI ${state.gameVersion}',
                    '감지된 ADOFAI 버전: ${state.gameVersion}')
                : state.t(
                    'ADOFAI version not detected', 'ADOFAI 버전을 감지하지 못했습니다'),
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6)),
          ),
          if (canMigrate) ...[
            const SizedBox(height: 16),
            _MigrationBanner(),
          ],
          const Spacer(),
          if (canMigrate)
            _BigButton(
              icon: Icons.sync,
              label: state.t('Migrate to MelonLoader', 'MelonLoader로 마이그레이션'),
              filled: true,
              onPressed: () => _confirmMigration(context, state),
            ),
          if (canMigrate) const SizedBox(height: 10),
          _BigButton(
            icon: Icons.download,
            label: state.t('Install Mods', '모드 설치'),
            filled: !canMigrate,
            onPressed: () => state.proceedFromInstalled(),
          ),
          const SizedBox(height: 10),
          _BigButton(
            icon: Icons.playlist_remove,
            label: state.t('Manage Mods', '모드 관리'),
            filled: false,
            onPressed: () => state.openManageMods(),
          ),
          const SizedBox(height: 10),
          _BigButton(
            icon: Icons.delete_outline,
            label: isMelon
                ? state.t('Uninstall MelonLoader', 'MelonLoader 제거')
                : state.t('Uninstall Unity Mod Manager', 'Unity Mod Manager 제거'),
            filled: false,
            danger: true,
            onPressed: () => state.startUninstall(),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => exit(0),
              child: Text(state.t('Close', '닫기')),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmMigration(BuildContext context, state) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(state.t(
            'Migrate to MelonLoader?', 'MelonLoader로 마이그레이션하시겠습니까?')),
        content: Text(state.t(
          'This uninstalls Unity Mod Manager and installs MelonLoader + UMMCompat, then offers to move your UMM mods to UMMMods/.',
          'Unity Mod Manager를 제거하고 MelonLoader + UMMCompat를 설치한 후, UMM 모드를 UMMMods/로 옮기도록 안내합니다.',
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(state.t('Cancel', '취소'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              state.startMigration();
            },
            child: Text(state.t('Migrate', '마이그레이션')),
          ),
        ],
      ),
    );
  }
}

class _MigrationBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, color: accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.t(
                "MelonLoader is now recommended over Unity Mod Manager — it's more compatible with the latest ADOFAI.",
                '이제 Unity Mod Manager보다 MelonLoader를 권장합니다 — 최신 ADOFAI와 호환성이 더 좋습니다.',
              ),
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool danger;
  final VoidCallback onPressed;

  const _BigButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
    final style = ButtonStyle(
      alignment: Alignment.centerLeft,
      padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
      minimumSize: WidgetStateProperty.all(const Size.fromHeight(0)),
    );
    final fg = danger ? Theme.of(context).colorScheme.error : null;
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(onPressed: onPressed, style: style, child: child)
          : OutlinedButton(
              onPressed: onPressed,
              style: style.copyWith(
                foregroundColor:
                    fg == null ? null : WidgetStateProperty.all(fg),
              ),
              child: child),
    );
  }
}
