import 'package:flutter/material.dart';

import 'app_scope.dart';

class ModPickerView extends StatelessWidget {
  const ModPickerView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final allSelected = state.selectedMods.length == state.visibleMods.length &&
        state.visibleMods.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.t('ADOFAI Mod Installer', 'ADOFAI 모드 설치기'),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            state.t('Select mods to install', '설치할 모드를 선택하세요'),
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 12),
          if (state.modsError != null)
            Expanded(child: _ErrorState(message: state.modsError!))
          else ...[
            if (state.unavailableJalibMods.isNotEmpty) ...[
              _JalibBanner(
                names: state.unavailableJalibMods.map((m) => m.id).join(', '),
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => state.setAllSelected(!allSelected),
                child: Text(allSelected
                    ? state.t('Deselect All', '모두 해제')
                    : state.t('Select All', '모두 선택')),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final mod in state.visibleMods)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: state.selectedMods.contains(mod.id),
                      onChanged: (_) => state.toggleMod(mod.id),
                      title: Text(mod.id, style: const TextStyle(fontSize: 14)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => state.returnToMenu(),
                child: Text(state.t('Go Back', '돌아가기')),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => state.startInstall(skipMods: true),
                child: Text(state.t('Skip Mods', '모드 건너뛰기')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: state.selectedMods.isEmpty
                    ? null
                    : () => state.startInstall(),
                child: Text(state.t('Install', '설치')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JalibBanner extends StatelessWidget {
  final String names;
  const _JalibBanner({required this.names});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.yellow.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.t(
                'Mods that depend on JALib are temporarily unavailable and hidden: $names.',
                'JALib을 필요로 하는 모드는 현재 사용할 수 없어 숨겨졌습니다: $names.',
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

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 32),
          const SizedBox(height: 12),
          Text(
            state.t("Couldn't load the mod list.", '모드 목록을 불러오지 못했습니다.'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6))),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => state.reloadMods(),
            child: Text(state.t('Retry', '다시 시도')),
          ),
        ],
      ),
    );
  }
}
