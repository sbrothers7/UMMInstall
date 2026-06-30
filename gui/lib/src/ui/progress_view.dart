import 'package:flutter/material.dart';

import '../models.dart';
import 'app_scope.dart';

class ProgressView extends StatelessWidget {
  const ProgressView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final isComplete = state.phase == InstallPhase.complete;
    final hasError = state.logEntries.any((e) => e.level == LogLevel.error);
    final canClose = isComplete || hasError;

    final subtitle = switch (state.phase) {
      InstallPhase.complete => state.completeMessage,
      _ => state.subtitle,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.t('ADOFAI Mod Manager', 'ADOFAI 모드 관리자'),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6))),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            itemCount: state.logEntries.length,
            itemBuilder: (context, i) => _LogRow(entry: state.logEntries[i]),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: state.phase == InstallPhase.confirmModMove
              ? _ModMovePrompt()
              : Row(
                  children: [
                    const Spacer(),
                    FilledButton(
                      onPressed: canClose ? () => state.returnToMenu() : null,
                      child: Text(state.t('Go Back', '돌아가기')),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ModMovePrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final n = state.migratableMods.length;
    return Row(
      children: [
        Expanded(
          child: Text(
            state.t(
              'Found $n UMM mod(s) in Mods/. Move them to UMMMods/ so UMMCompat loads them?',
              'Mods/에서 $n개의 UMM 모드를 찾았습니다. UMMCompat가 로드하도록 UMMMods/로 옮길까요?',
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () => state.skipMigratableMods(),
          child: Text(state.t('Keep in Mods/', 'Mods/에 유지')),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => state.moveMigratableMods(),
          child: Text(state.t('Move', '이동')),
        ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    if (entry.progress != null) {
      final value = entry.progress! >= 0 ? entry.progress : null;
      final pct = entry.progress! >= 0
          ? '  ${(entry.progress! * 100).round()}%'
          : '';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  child: Text('↓',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        Text('${entry.message}$pct', style: const TextStyle(fontSize: 14))),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: value, minHeight: 5),
              ),
            ),
          ],
        ),
      );
    }
    if (entry.level == LogLevel.detail) {
      return Padding(
        padding: const EdgeInsets.only(left: 28, top: 2, bottom: 2),
        child: Text(
          entry.message,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }
    final (icon, color) = switch (entry.level) {
      LogLevel.ok => ('✓', const Color(0xFF52CF66)),
      LogLevel.error => ('✕', const Color(0xFFFF6B6B)),
      _ => ('›', Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: Text(icon,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(entry.message,
                style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
