import 'dart:io';
import 'package:flutter/material.dart';
import 'app_scope.dart';

class NeedsVerifyView extends StatelessWidget {
  const NeedsVerifyView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amber),
              const SizedBox(width: 10),
              Text(
                state.t('Game files need verifying', '게임 파일 검증 필요'),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            state.t(
              'The game binary is missing its arm64 slice — likely stripped by a previous v2 Unity Mod Manager install. The native loader needs it back.\n\n'
              'Click "Verify in Steam" to open Steam\'s integrity check (Properties → Installed Files), let it finish, then click Re-check.',
              '게임 바이너리에 arm64 슬라이스가 없습니다 — 이전 v2 Unity Mod Manager 설치로 제거된 것으로 보입니다. 네이티브 로더에는 이 슬라이스가 필요합니다.\n\n'
              '"Steam에서 검증"을 눌러 Steam 무결성 검사(속성 → 설치된 파일)를 실행하고, 완료되면 다시 확인을 누르세요.',
            ),
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              TextButton(
                onPressed: () => exit(0),
                child: Text(state.t('Cancel', '취소')),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => state.recheckVerify(),
                child: Text(state.t('Re-check', '다시 확인')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => state.openSteamVerify(),
                child: Text(state.t('Verify in Steam', 'Steam에서 검증')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
