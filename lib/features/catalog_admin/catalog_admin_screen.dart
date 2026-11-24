import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../live_recce/data/catalog_data.dart';
import 'catalog_admin_controller.dart';
import 'installation_form_screen.dart';
import 'media_form_screen.dart';
import 'question_form_screen.dart';

/// The administrator's "Media catalog": the media types, the installation types and the site questions the field person picks from.
/// Everything is read from and written to the server, so the web admin and this screen always show the same catalog.
class CatalogAdminScreen extends StatelessWidget {
  const CatalogAdminScreen({super.key});

  Future<void> _defaults(BuildContext context) async {
    final ctrl = context.read<CatalogAdminController>();
    final ok = await confirmDialog(context, title: 'Load built-in defaults?', message: 'Adds back any built-in media type, installation type or question that was deleted. Nothing you changed or added is touched.', confirmText: 'Load');
    if (!ok || !context.mounted) return;
    final err = await ctrl.loadDefaults();
    if (!context.mounted) return;
    final n = ctrl.lastDefaultsAdded;
    showSnack(context, err ?? (n == 0 ? 'Nothing was missing. Every built-in entry is already there.' : '$n built-in ${n == 1 ? 'entry' : 'entries'} added back.'), error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CatalogAdminController>();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            const Flexible(child: Text('Media catalog', maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (ctrl.loaded && ctrl.data.version > 0) ...[const SizedBox(width: 10), TagChip('v${ctrl.data.version}', color: AdinnColors.info)],
          ]),
          actions: [
            IconButton(key: const Key('catalog-refresh'), tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: ctrl.loading ? null : ctrl.load),
            PopupMenuButton<String>(
              key: const Key('catalog-menu'),
              onSelected: (_) => _defaults(context),
              itemBuilder: (_) => const [PopupMenuItem(value: 'defaults', child: Text('Load built-in defaults'))],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Media'), Tab(text: 'Installation'), Tab(text: 'Questions')]),
        ),
        body: !ctrl.loaded
            ? (ctrl.loading
                ? const Center(child: CircularProgressIndicator())
                : EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not load the catalog', message: ctrl.error ?? 'Try again.', action: FilledButton(onPressed: ctrl.load, child: const Text('Try again'))))
            : Column(children: [
                if (ctrl.loading) const LinearProgressIndicator(minHeight: 2),
                const Expanded(child: TabBarView(children: [_MediaTab(), _InstallationTab(), _QuestionTab()])),
              ]),
      ),
    );
  }
}

/* ---------------------------------------------------------------------------------------------- shared row */

class _AdminTile extends StatelessWidget {
  const _AdminTile({
    required this.id,
    required this.leading,
    required this.title,
    this.subtitle,
    this.chips = const [],
    required this.active,
    required this.onToggle,
    required this.onEdit,
    this.onUp,
    this.onDown,
    required this.onDelete,
  });

  final String id;
  final Widget leading;
  final String title;
  final String? subtitle;
  final List<Widget> chips;
  final bool active;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: Key('tile-$id'),
        borderRadius: BorderRadius.circular(14),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: active ? 1 : 0.55,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  if (subtitle != null && subtitle!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AdinnColors.muted, fontSize: 12.5))),
                  if (chips.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
                ]),
              ),
            ),
            Column(children: [
              Switch(key: Key('active-$id'), value: active, onChanged: onToggle),
              PopupMenuButton<String>(
                key: Key('menu-$id'),
                tooltip: 'More',
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      onEdit();
                    case 'up':
                      onUp?.call();
                    case 'down':
                      onDown?.call();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), dense: true, contentPadding: EdgeInsets.zero)),
                  if (onUp != null) const PopupMenuItem(value: 'up', child: ListTile(leading: Icon(Icons.arrow_upward), title: Text('Move up'), dense: true, contentPadding: EdgeInsets.zero)),
                  if (onDown != null) const PopupMenuItem(value: 'down', child: ListTile(leading: Icon(Icons.arrow_downward), title: Text('Move down'), dense: true, contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: AdinnColors.red), title: Text('Delete', style: TextStyle(color: AdinnColors.red)), dense: true, contentPadding: EdgeInsets.zero)),
                ],
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FilledButton.icon(key: const Key('admin-add'), onPressed: onPressed, icon: const Icon(Icons.add), label: Text(label)),
      );
}

class _Intro extends StatelessWidget {
  const _Intro(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(text, style: const TextStyle(color: AdinnColors.muted, fontSize: 13)));
}

Widget _iconBox(String icon, Color color) => Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Icon(catalogIcon(icon), color: color),
    );

/// What a delete or a switch-off does, and the answer of the server shown as a snack.
Future<void> _toggle(BuildContext context, CatalogKind kind, String id, bool on) async {
  final err = await context.read<CatalogAdminController>().setActive(kind, id, on);
  if (err != null && context.mounted) showSnack(context, err, error: true);
}

/// Delete with a confirmation. An entry that boards already use cannot be deleted: the person is offered "Mark inactive" instead.
Future<void> _delete(BuildContext context, {required CatalogKind kind, required String id, required String name, required int used, required String effect}) async {
  final ctrl = context.read<CatalogAdminController>();
  if (used > 0) {
    final inactive = await confirmDialog(
      context,
      title: 'In use: cannot delete',
      message: '$name is used by $used board${used == 1 ? '' : 's'} already, so it cannot be deleted. Mark it inactive instead? It is then not offered for a new board, and the boards that use it keep it.',
      confirmText: 'Mark inactive',
    );
    if (inactive && context.mounted) await _toggle(context, kind, id, false);
    return;
  }
  final ok = await confirmDialog(context, title: 'Delete $name?', message: effect, confirmText: 'Delete', destructive: true);
  if (!ok || !context.mounted) return;
  final err = await ctrl.delete(kind, id);
  if (!context.mounted) return;
  showSnack(context, err ?? '$name deleted.', error: err != null);
}

/// Opens a form page; when it came back saved (true), says so.
Future<void> _open(BuildContext context, WidgetBuilder page, String message) async {
  final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: page));
  if (saved == true && context.mounted) showSnack(context, message);
}

/// The ids of a list after moving the entry at [from] one place up (-1) or down (+1).
List<String> movedIds(List<String> ids, int from, int step) {
  final to = from + step;
  if (to < 0 || to >= ids.length) return ids;
  final out = [...ids];
  out.insert(to, out.removeAt(from));
  return out;
}

Future<void> _move(BuildContext context, CatalogKind kind, List<String> ids, int from, int step) async {
  final err = await context.read<CatalogAdminController>().reorder(kind, movedIds(ids, from, step));
  if (err != null && context.mounted) showSnack(context, err, error: true);
}

/* ---------------------------------------------------------------------------------------------- media */

class _MediaTab extends StatelessWidget {
  const _MediaTab();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CatalogAdminController>();
    final current = ctrl.currentMedia;
    final codes = [for (final m in current) m.code];
    Widget tile(CatalogMedia m, {int? index}) {
      final used = ctrl.usage.ofMedia(m.code);
      final qCount = ctrl.questionsOf('MEDIA', m.code).length;
      return _AdminTile(
        id: m.code,
        leading: _iconBox(m.icon, hexColor(m.color)),
        title: '${m.shortName}  ${m.name}',
        subtitle: m.description,
        chips: [
          TagChip(switch (m.sidedness) { 'DOUBLE' => 'Double side', 'SELECTABLE' => 'Single or double', _ => 'Single side' }),
          if (m.illuminated) const TagChip('Lit', icon: Icons.lightbulb_outline, color: AdinnColors.warning),
          TagChip('${m.installations.length} installation${m.installations.length == 1 ? '' : 's'}', icon: Icons.handyman_outlined),
          TagChip('$qCount question${qCount == 1 ? '' : 's'}', icon: Icons.help_outline),
          if (used > 0) TagChip('$used board${used == 1 ? '' : 's'}', icon: Icons.view_in_ar_outlined, color: AdinnColors.success),
          if (m.legacy) const TagChip('Older type', color: AdinnColors.purple),
          if (!m.active) const TagChip('Inactive', color: AdinnColors.red),
        ],
        active: m.active,
        onToggle: (v) => _toggle(context, CatalogKind.media, m.code, v),
        onEdit: () async => _open(context, (_) => MediaFormScreen(ctrl: ctrl, media: m), '${m.shortName} saved.'),
        onUp: index != null && index > 0 ? () => _move(context, CatalogKind.media, codes, index, -1) : null,
        onDown: index != null && index < codes.length - 1 ? () => _move(context, CatalogKind.media, codes, index, 1) : null,
        onDelete: () => _delete(context,
            kind: CatalogKind.media, id: m.code, name: m.shortName, used: used, effect: 'The media type is removed from the catalog${qCount > 0 ? ', with its $qCount question${qCount == 1 ? '' : 's'}' : ''}. Boards already recorded keep their names and answers.'),
      );
    }

    return RefreshIndicator(
      onRefresh: ctrl.load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Intro('The media types the field person picks from when adding a board. Changes reach the phones the next time they open the app. Boards already recorded keep what they were saved with.'),
          _AddButton(label: 'Add media type', onPressed: () async => _open(context, (_) => MediaFormScreen(ctrl: ctrl), 'Media type added.')),
          if (current.isEmpty) const EmptyState(icon: Icons.category_outlined, title: 'No media types', message: 'Add one, or load the built-in defaults from the menu.'),
          for (final (i, m) in current.indexed) tile(m, index: i),
          if (ctrl.legacyMedia.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Older media types', style: TextStyle(fontWeight: FontWeight.w800)),
            const _Intro('Kept so old recces stay readable. They are never offered for a new board.'),
            for (final m in ctrl.legacyMedia) tile(m),
          ],
        ],
      ),
    );
  }
}

/* ---------------------------------------------------------------------------------------------- installation */

class _InstallationTab extends StatelessWidget {
  const _InstallationTab();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CatalogAdminController>();
    final list = ctrl.data.installations;
    final codes = [for (final i in list) i.code];
    return RefreshIndicator(
      onRefresh: ctrl.load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Intro('How a board is fixed. Each media type offers the installation types you tick in its form, and each installation type can ask its own questions.'),
          _AddButton(label: 'Add installation type', onPressed: () async => _open(context, (_) => InstallationFormScreen(ctrl: ctrl), 'Installation type added.')),
          if (list.isEmpty) const EmptyState(icon: Icons.handyman_outlined, title: 'No installation types', message: 'Add one, or load the built-in defaults from the menu.'),
          for (final (i, inst) in list.indexed)
            Builder(builder: (context) {
              final used = ctrl.usage.ofInstallation(inst.code);
              final offeredBy = ctrl.data.media.where((m) => m.installations.contains(inst.code)).length;
              final qCount = ctrl.questionsOf('INSTALLATION', inst.code).length;
              return _AdminTile(
                id: inst.code,
                leading: _iconBox(inst.icon, AdinnColors.red),
                title: inst.name,
                subtitle: inst.description,
                chips: [
                  TagChip(inst.code, icon: Icons.tag),
                  TagChip('$offeredBy media type${offeredBy == 1 ? '' : 's'}', icon: Icons.category_outlined),
                  TagChip('$qCount question${qCount == 1 ? '' : 's'}', icon: Icons.help_outline),
                  if (used > 0) TagChip('$used board${used == 1 ? '' : 's'}', icon: Icons.view_in_ar_outlined, color: AdinnColors.success),
                  if (!inst.active) const TagChip('Inactive', color: AdinnColors.red),
                ],
                active: inst.active,
                onToggle: (v) => _toggle(context, CatalogKind.installations, inst.code, v),
                onEdit: () async => _open(context, (_) => InstallationFormScreen(ctrl: ctrl, installation: inst), '${inst.name} saved.'),
                onUp: i > 0 ? () => _move(context, CatalogKind.installations, codes, i, -1) : null,
                onDown: i < codes.length - 1 ? () => _move(context, CatalogKind.installations, codes, i, 1) : null,
                onDelete: () => _delete(context,
                    kind: CatalogKind.installations,
                    id: inst.code,
                    name: inst.name,
                    used: used,
                    effect: 'It is taken off ${offeredBy == 1 ? 'the 1 media type' : 'the $offeredBy media types'} that offer it${qCount > 0 ? ' and its $qCount question${qCount == 1 ? ' is' : 's are'} deleted' : ''}. Boards already recorded keep their answers.'),
              );
            }),
        ],
      ),
    );
  }
}

/* ---------------------------------------------------------------------------------------------- questions */

class _QuestionTab extends StatefulWidget {
  const _QuestionTab();

  @override
  State<_QuestionTab> createState() => _QuestionTabState();
}

class _QuestionTabState extends State<_QuestionTab> {
  String _scope = 'COMMON';
  String? _code;

  /// The media or installation code of the group shown (the first one when none was picked yet or the picked one is gone).
  String _scopeCode(CatalogAdminController ctrl) {
    if (_scope == 'COMMON') return '';
    final codes = _scope == 'MEDIA' ? [for (final m in ctrl.data.media) m.code] : [for (final i in ctrl.data.installations) i.code];
    return codes.contains(_code) ? _code! : (codes.firstOrNull ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CatalogAdminController>();
    final code = _scopeCode(ctrl);
    final list = ctrl.questionsOf(_scope, code);
    final uids = [for (final q in list) q.uid];
    final canAdd = _scope == 'COMMON' || code.isNotEmpty;
    return RefreshIndicator(
      onRefresh: ctrl.load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Intro('The material and site questions asked for each board. A board gets the questions of its installation type, then of its media type, then the ones every board gets.'),
          SegmentedButton<String>(
            key: const Key('q-scope'),
            segments: const [
              ButtonSegment(value: 'COMMON', label: Text('Every board')),
              ButtonSegment(value: 'MEDIA', label: Text('Media type')),
              ButtonSegment(value: 'INSTALLATION', label: Text('Installation')),
            ],
            selected: {_scope},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _scope = s.first;
              _code = null;
            }),
          ),
          if (_scope != 'COMMON') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: Key('q-code-$_scope'),
              initialValue: code.isEmpty ? null : code,
              isExpanded: true,
              decoration: InputDecoration(labelText: _scope == 'MEDIA' ? 'Media type' : 'Installation type'),
              items: [
                if (_scope == 'MEDIA')
                  for (final m in ctrl.data.media) DropdownMenuItem(value: m.code, child: Text('${m.shortName}  ${m.name}', maxLines: 1, overflow: TextOverflow.ellipsis))
                else
                  for (final i in ctrl.data.installations) DropdownMenuItem(value: i.code, child: Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _code = v),
            ),
          ],
          const SizedBox(height: 14),
          _AddButton(
            label: 'Add question',
            onPressed: canAdd
                ? () async => _open(context, (_) => QuestionFormScreen(ctrl: ctrl, scope: _scope, scopeCode: code), 'Question added.')
                : null,
          ),
          if (list.isEmpty) const EmptyState(icon: Icons.help_outline, title: 'No questions here', message: 'Add the first question of this group.'),
          for (final (i, q) in list.indexed)
            _AdminTile(
              id: q.uid,
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: AdinnColors.info.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(questionTypes.firstWhere((t) => t.$1 == q.type, orElse: () => questionTypes.first).$3, color: AdinnColors.info),
              ),
              title: q.label,
              chips: [
                TagChip(questionTypeLabel(q.type)),
                TagChip(q.required ? 'Required' : 'Optional', color: q.required ? AdinnColors.red : AdinnColors.muted),
                TagChip(q.id, icon: Icons.tag),
                if (q.type == 'CHOICE') TagChip('${q.options.length} options', icon: Icons.checklist),
                if (q.unit != null) TagChip(q.unit!, icon: Icons.straighten),
                if (q.showIfId != null) TagChip('If ${q.showIfId} = ${q.showIfValue is bool ? ((q.showIfValue as bool) ? 'Yes' : 'No') : q.showIfValue}', icon: Icons.call_split, color: AdinnColors.purple),
                if (!q.active) const TagChip('Inactive', color: AdinnColors.red),
              ],
              active: q.active,
              onToggle: (v) => _toggle(context, CatalogKind.questions, q.uid, v),
              onEdit: () async => _open(context, (_) => QuestionFormScreen(ctrl: ctrl, scope: _scope, scopeCode: code, question: q), 'Question saved.'),
              onUp: i > 0 ? () => _move(context, CatalogKind.questions, uids, i, -1) : null,
              onDown: i < uids.length - 1 ? () => _move(context, CatalogKind.questions, uids, i, 1) : null,
              onDelete: () => _delete(context, kind: CatalogKind.questions, id: q.uid, name: 'this question', used: 0, effect: 'The question is removed from the catalog. Answers already given stay on their boards.'),
            ),
        ],
      ),
    );
  }
}
