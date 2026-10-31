import 'dart:io';
import 'package:flutter/material.dart';

import '../models.dart';
import 'app_scope.dart';

class ConfirmView extends StatelessWidget {
  const ConfirmView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.t('ADOFAI Mod Manager Installer', 'ADOFAI 모드 관리자 설치'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                state.confirmationText,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: () => exit(0),
                child: Text(state.t('Cancel', '취소')),
              ),
              const Spacer(),
              if (state.isGameV2)
                FilledButton(
                  onPressed: () => state.proceedFromConfirm(LoaderType.umm),
                  child: Text(state.t('Proceed', '계속')),
                )
              else if (!state.canInstallUmm)
                // Windows/Linux: MelonLoader is the only scripted loader.
                FilledButton(
                  onPressed: () =>
                      state.proceedFromConfirm(LoaderType.melonLoader),
                  child: Text(state.t('Install MelonLoader', 'MelonLoader 설치')),
                )
              else ...[
                OutlinedButton(
                  onPressed: () => state.proceedFromConfirm(LoaderType.umm),
                  child: Text(state.t('Native UMM', '네이티브 UMM')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () =>
                      state.proceedFromConfirm(LoaderType.melonLoader),
                  child: Text(state.t('MelonLoader', 'MelonLoader')),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
