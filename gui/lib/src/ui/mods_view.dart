import 'package:amm_core/amm_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import 'app_scope.dart';

enum _Tab { browse, installed, updates }

/// Browse / Installed / Updates as a card grid, on the same catalog, record
/// and operations as `amm`.
class ModsView extends StatefulWidget {
  const ModsView({super.key});

  @override
  State<ModsView> createState() => _ModsViewState();
}

class _ModsViewState extends State<ModsView> {
  _Tab _tab = _Tab.browse;
  bool _archived = false;
  String _query = '';
  String? _category;

  bool _matches(String name, CatalogEntry? e) {
    final q = _query.trim().toLowerCase();
    if (_category != null && !(e?.categories.contains(_category) ?? false)) {
      return false;
    }
    if (q.isEmpty) return true;
    return [name, e?.slug, e?.author, e?.summary]
        .any((s) => s != null && s.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final upgrades = state.scan?.upgrades ?? const <Upgrade>[];
    final catalogDown = state.catalogError != null && _tab != _Tab.installed;

    // The current tab's cards, as (name, entry, build) so filtering and the
    // category chips work the same on every tab.
    final List<(String, CatalogEntry?, Widget Function())> cards = switch (_tab) {
      _Tab.browse => [
          for (final e in state.browseEntries)
            (e.name, e, () => _ModCard(entry: e, name: e.name, version: _v(_latest(e)),
                action: _browseAction(context, state, e))),
        ],
      _Tab.updates => [
          for (final u in upgrades)
            (u.entry.name, u.entry, () => _ModCard(entry: u.entry, name: u.entry.name,
                version: '${_v(u.from) ?? '?'} → ${_v(u.to)}',
                action: _updateButton(context, state, u.entry.slug))),
        ],
      _Tab.installed when _archived => [
          for (final a in state.archivedMods)
            (a.name, null, () => _ModCard(name: a.name,
                note: state.t('Archived — data kept', '보관됨 — 데이터 유지'),
                action: _archivedActions(context, state, a))),
        ],
      _Tab.installed => [
          for (final i in state.installedItems)
            (i.name, i.entry, () => _ModCard(entry: i.entry, name: i.name,
                version: _v(i.version),
                note: i.entry == null
                    ? state.t('Not in the catalog', '카탈로그에 없는 모드')
                    : null,
                action: _removeButton(context, state, i))),
        ],
    };
    final categories = {
      for (final (_, e, _) in cards) ...?e?.categories,
    }.toList()
      ..sort();
    final shown = [for (final c in cards) if (_matches(c.$1, c.$2)) c];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.t('Mods', '모드'),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SegmentedButton<_Tab>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(
                      value: _Tab.browse, label: Text(state.t('Browse', '찾아보기'))),
                  ButtonSegment(
                      value: _Tab.installed,
                      label: Text(
                          '${state.t('Installed', '설치됨')} (${state.installedItems.length})')),
                  ButtonSegment(
                      value: _Tab.updates,
                      label: Text('${state.t('Updates', '업데이트')} (${upgrades.length})')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() {
                  _tab = s.first;
                  _archived = false;
                  _category = null;
                }),
              ),
              const Spacer(),
              if (_tab == _Tab.updates && upgrades.isNotEmpty)
                state.busySlug == '*'
                    ? const _Spinner()
                    : FilledButton(
                        onPressed: state.busySlug == null ? state.updateAll : null,
                        child: Text(state.t('Update All', '모두 업데이트')),
                      ),
              if (_tab == _Tab.installed)
                FilterChip(
                  label: Text(
                      '${state.t('Archived', '보관됨')} (${state.archivedMods.length})'),
                  selected: _archived,
                  onSelected: (v) => setState(() => _archived = v),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: state.t('Search mods', '모드 검색'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final c in [null, ...categories])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(c == null ? state.t('All', '전체') : _capitalize(c),
                                style: const TextStyle(fontSize: 12)),
                            selected: _category == c,
                            onSelected: (_) => setState(() => _category = c),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final w in state.catalog?.warnings ?? const <String>[])
            _Notice(icon: Icons.info_outline, text: w),
          if (_tab == _Tab.browse && state.unavailableJalib.isNotEmpty)
            _JalibBanner(names: state.unavailableJalib.map((e) => e.name).join(', ')),
          if (state.modError != null)
            _Notice(
              icon: Icons.error_outline,
              text: state.modError!,
              error: true,
              onClose: state.dismissModError,
            ),
          Expanded(
            child: catalogDown
                ? _ErrorState(message: state.catalogError!)
                : shown.isEmpty
                    ? _empty(context, state)
                    : GridView(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisExtent: 168,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        children: [for (final c in shown) c.$3()],
                      ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: state.busySlug == null ? state.returnToMenu : null,
                child: Text(state.t('Go Back', '돌아가기')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, AppState state) {
    final text = _query.isNotEmpty || _category != null
        ? state.t('No mods match.', '일치하는 모드가 없습니다.')
        : switch (_tab) {
            _Tab.browse => state.t('No mods available.', '사용할 수 있는 모드가 없습니다.'),
            _Tab.updates => state.t('All mods are up to date.', '모든 모드가 최신입니다.'),
            _Tab.installed when _archived =>
              state.t('No archived mods.', '보관된 모드가 없습니다.'),
            _Tab.installed => state.t('No mods installed.', '설치된 모드가 없습니다.'),
          };
    return Center(child: Text(text, style: _subtle(context)));
  }

  static String? _latest(CatalogEntry e) => e.theirs?.version ?? e.ours?.version;

  /// "utility" → "Utility"; short ones like "ui" read as acronyms.
  static String _capitalize(String s) => s.length <= 2
      ? s.toUpperCase()
      : s[0].toUpperCase() + s.substring(1);

  /// "1.2.0" → "v1.2.0"; leaves "v1.0" and "?" alone.
  static String? _v(String? s) =>
      s != null && s.startsWith(RegExp(r'\d')) ? 'v$s' : s;

  Widget _browseAction(BuildContext context, AppState state, CatalogEntry e) {
    if (state.upgradeFor(e.slug) != null) return _updateButton(context, state, e.slug);
    if (state.isInstalled(e.slug)) {
      return OutlinedButton(
        onPressed: null,
        style: _compact(context, OutlinedButton.styleFrom(
            disabledForegroundColor: const Color(0xFF7FD18B))),
        child: Text('✓ ${state.t('Installed', '설치됨')}'),
      );
    }
    if (state.busySlug == e.slug) return const _Spinner();
    return FilledButton(
      onPressed: state.busySlug == null ? () => state.installMod(e.slug) : null,
      style: _compact(context, FilledButton.styleFrom()),
      child: Text(state.t('Install', '설치')),
    );
  }

  Widget _updateButton(BuildContext context, AppState state, String slug) {
    if (state.busySlug == slug) return const _Spinner();
    return FilledButton(
      onPressed: state.busySlug == null ? () => state.updateMod(slug) : null,
      style: _compact(context, FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE0B45A),
          foregroundColor: const Color(0xFF241A05))),
      child: Text(state.t('Update', '업데이트')),
    );
  }

  Widget _removeButton(BuildContext context, AppState state, InstalledItem i) =>
      TextButton(
        onPressed: state.busySlug == null
            ? () => _deleteDialog(
                  context,
                  state,
                  title: state.t('Remove "${i.name}"?', '"${i.name}"을(를) 제거하시겠습니까?'),
                  onKeepData: () => state.removeItem(i, keep: true),
                  onDeletePermanently: () => state.removeItem(i, keep: false),
                )
            : null,
        style: _compact(context, TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error)),
        child: Text(state.t('Remove', '제거')),
      );

  Widget _archivedActions(BuildContext context, AppState state, ArchivedMod a) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: state.busySlug == null ? () => state.restoreMod(a) : null,
            style: _compact(context, TextButton.styleFrom()),
            child: Text(state.t('Restore', '복원')),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
            tooltip: state.t('Delete permanently', '영구 삭제'),
            onPressed: state.busySlug != null ? null : () => _deleteDialog(
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
      );

  /// Smaller buttons for cards. The label style starts from the theme's so
  /// it keeps the Korean font fallback.
  static ButtonStyle _compact(BuildContext context, ButtonStyle s) => s.copyWith(
        visualDensity: VisualDensity.compact,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
        textStyle: WidgetStatePropertyAll(Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
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

TextStyle _subtle(BuildContext context) => TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
    );

/// One mod: letter tile, name, author, summary, categories (or what it
/// needs), version and downloads, and its [action].
class _ModCard extends StatelessWidget {
  final CatalogEntry? entry;
  final String name;
  final String? version;
  final String? note; // replaces the summary when there's no catalog entry
  final Widget action;

  const _ModCard({
    this.entry,
    required this.name,
    this.version,
    this.note,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final e = entry;
    final cats = e?.categories ?? const <String>[];
    final needs = [
      for (final d in e?.dependencies ?? const <String>[])
        state.catalog?.find(d)?.name ?? d,
    ];
    final details = [
      ?version,
      if (e?.downloads case final n?) '⬇ $n',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LetterTile(name: name),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    if (e?.author case final a?)
                      Text(state.t('by $a', '제작: $a'),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: _subtle(context)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note ?? e?.summary ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 6),
          if (needs.isNotEmpty)
            Text(state.t('Needs ${needs.join(', ')}', '필요: ${needs.join(', ')}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFFE0B45A)))
          else
            Wrap(
              spacing: 4,
              children: [
                for (final c in cats.take(2)) _Tag(c),
                if (cats.length > 2) _Tag('+${cats.length - 2}'),
              ],
            ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(details,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: _subtle(context)),
              ),
              action,
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(text, style: _subtle(context).copyWith(fontSize: 10)),
      );
}

/// Stand-in logo: the name's first letter on a colour picked from the name.
/// modlist.org's logo paths don't load outside its site yet.
class _LetterTile extends StatelessWidget {
  final String name;
  const _LetterTile({required this.name});

  static const _colors = [
    Color(0xFF3D6FD8), Color(0xFF8A4FD8), Color(0xFF2FA38A), Color(0xFFD8743D),
    Color(0xFFC94F6D), Color(0xFF4F9BD8), Color(0xFF7A8A3D), Color(0xFF5D6475),
  ];

  @override
  Widget build(BuildContext context) {
    final sum = name.codeUnits.fold(0, (a, b) => a + b);
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _colors[sum % _colors.length],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool error;
  final VoidCallback? onClose;
  const _Notice({required this.icon, required this.text, this.error = false, this.onClose});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = error ? scheme.error : scheme.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color)),
          ),
          if (onClose != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 15,
              icon: const Icon(Icons.close),
              onPressed: onClose,
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.yellow.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.t(
                'Mods that depend on JALib are temporarily unavailable and hidden: $names.',
                'JALib을 필요로 하는 모드는 현재 사용할 수 없어 숨겨졌습니다: $names.',
              ),
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
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
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => state.loadCatalog(),
            child: Text(state.t('Retry', '다시 시도')),
          ),
        ],
      ),
    );
  }
}
