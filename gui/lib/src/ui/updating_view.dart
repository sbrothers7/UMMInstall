import 'package:flutter/material.dart';
import 'app_scope.dart';

class UpdatingView extends StatelessWidget {
  const UpdatingView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    if (state.hasUpdate) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.system_update_alt, size: 36),
            const SizedBox(height: 14),
            Text(
              state.t('Update available', '업데이트 사용 가능'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              state.t('Version ${state.updateTag} is available.',
                  '버전 ${state.updateTag}을(를) 사용할 수 있습니다.'),
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => state.skipUpdate(),
                  child: Text(state.t('Skip', '건너뛰기')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => state.performUpdate(),
                  child: Text(state.t('Update Now', '지금 업데이트')),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            state.subtitle.isEmpty
                ? state.t('Checking for updates…', '업데이트 확인 중…')
                : state.subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
