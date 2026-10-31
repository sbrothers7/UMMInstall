import 'package:flutter/material.dart';

import '../app_state.dart';
import 'app_scope.dart';

class ManageModsView extends StatefulWidget {
  const ManageModsView({super.key});

  @override
  State<ManageModsView> createState() => _ManageModsViewState();
}

class _ManageModsViewState extends State<ManageModsView> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final selectedCount = state.selectedForDelete.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.t('Manage Mods', '모드 관리'),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                  value: false,
                  label: Text(
                      '${state.t('Installed', '설치됨')} (${state.installedMods.length})')),
              ButtonSegment(
                  value: true,
                  label: Text(
                      '${state.t('Archived', '보관됨')} (${state.archivedMods.length})')),
            ],
            selected: {_showArchived},
            onSelectionChanged: (s) => setState(() => _showArchived = s.first),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _showArchived
                ? _archivedList(context, state)
                : _installedList(context, state),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => state.returnToMenu(),
                child: Text(state.t('Go Back', '돌아가기')),
              ),
              const Spacer(),
              if (!_showArchived)
                FilledButton.tonal(
                  onPressed: selectedCount == 0
                      ? null
                      : () => _deleteDialog(
                            context,
                            state,
                            title: state.t('Delete $selectedCount mod(s)?',
                                '$selectedCount개의 모드를 삭제하시겠습니까?'),
                            onKeepData: () =>
                                state.archiveMods(state.selectedForDelete.toList()),
                            onDeletePermanently: () =>
                                state.deleteMods(state.selectedForDelete.toList()),
                          ),
                  child: Text(selectedCount == 0
                      ? state.t('Delete Selected', '선택 삭제')
                      : state.t('Delete Selected ($selectedCount)',
                          '선택 삭제 ($selectedCount)')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _installedList(BuildContext context, AppState state) {
    if (state.installedMods.isEmpty) {
      return _empty(context, state.t('No mods installed.', '설치된 모드가 없습니다.'));
    }
    return ListView(
      children: [
        for (final mod in state.installedMods)
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: state.selectedForDelete.contains(mod.path),
            onChanged: (_) => state.toggleDeleteSelection(mod.path),
            title: Text(mod.name, style: const TextStyle(fontSize: 14)),
            subtitle: Text(mod.isDirectory ? 'folder' : 'dll',
                style: _subtleStyle(context)),
            secondary: IconButton(
              icon: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              tooltip: state.t('Delete', '삭제'),
              onPressed: () => _deleteDialog(
                context,
                state,
                title: state.t('Delete "${mod.name}"?', '"${mod.name}"을(를) 삭제하시겠습니까?'),
                onKeepData: () => state.archiveMods([mod.path]),
                onDeletePermanently: () => state.deleteMods([mod.path]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _archivedList(BuildContext context, AppState state) {
    if (state.archivedMods.isEmpty) {
      return _empty(
          context, state.t('No archived mods.', '보관된 모드가 없습니다.'));
    }
    return ListView(
      children: [
        for (final a in state.archivedMods)
          ListTile(
            dense: true,
            title: Text(a.name, style: const TextStyle(fontSize: 14)),
            subtitle: Text(state.t('Data kept — can be restored', '데이터 유지됨 — 복원 가능'),
                style: _subtleStyle(context)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => state.restoreMod(a),
                  child: Text(state.t('Restore', '복원')),
                ),
                IconButton(
                  icon: Icon(Icons.delete_forever,
                      color: Theme.of(context).colorScheme.error),
                  tooltip: state.t('Delete permanently', '영구 삭제'),
                  onPressed: () => _deleteDialog(
                    context,
                    state,
                    title: state.t('Delete "${a.name}" permanently?',
                        '"${a.name}"을(를) 영구적으로 삭제하시겠습니까?'),
                    body: state.t(
                        'This deletes the archived data for good — it cannot be restored.',
                        '보관된 데이터를 영구적으로 삭제합니다 — 복원할 수 없습니다.'),
                    onKeepData: null,
                    onDeletePermanently: () => state.deleteArchived(a),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _empty(BuildContext context, String text) => Center(
        child: Text(text, style: _subtleStyle(context)),
      );

  TextStyle _subtleStyle(BuildContext context) => TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      );

  /// Delete confirmation. "Keep Data" archives; "Delete Permanently" needs a
  /// second click to confirm.
  void _deleteDialog(
    BuildContext context,
    AppState state, {
    required String title,
    String? body,
    required VoidCallback? onKeepData,
    required VoidCallback onDeletePermanently,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        var armed = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(title),
            content: Text(body ??
                state.t(
                  'Keep Data archives the mod (settings preserved) so you can restore it later.',
                  '데이터 유지를 선택하면 모드를 보관하여 (설정 유지) 나중에 복원할 수 있습니다.',
                )),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(state.t('Cancel', '취소')),
              ),
              if (onKeepData != null)
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onKeepData();
                  },
                  child: Text(state.t('Keep Data', '데이터 유지')),
                ),
              FilledButton(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                      Theme.of(ctx).colorScheme.error),
                ),
                onPressed: () {
                  if (!armed) {
                    setLocal(() => armed = true);
                  } else {
                    Navigator.pop(ctx);
                    onDeletePermanently();
                  }
                },
                child: Text(armed
                    ? state.t('Click again to confirm', '한 번 더 눌러 확인')
                    : state.t('Delete Permanently', '영구 삭제')),
              ),
            ],
          ),
        );
      },
    );
  }
}
