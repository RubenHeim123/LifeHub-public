import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/dialogs.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/vision/models/vision.dart';
import 'package:frontend/features/vision/repositories/vision_repository.dart';
import 'package:frontend/features/vision/screens/goal_plan_screen.dart';
import 'package:frontend/core/services/image_store.dart';

/// Übersicht aller langfristigen Ziele, gruppiert nach Bereichen.
/// Ein Tipp auf ein Ziel öffnet dessen Schritt-für-Schritt-Plan.
class VisionBoardScreen extends StatefulWidget {
  final UserModel user;
  const VisionBoardScreen({super.key, required this.user});

  @override
  State<VisionBoardScreen> createState() => _VisionBoardScreenState();
}

class _VisionBoardScreenState extends State<VisionBoardScreen> {
  late final VisionRepository _repo = context.read<VisionRepository>();
  late final VisionImageStore _images = context.read<VisionImageStore>();
  List<AreaWithGoals> _board = [];
  Map<int, File> _imageFiles = {};
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final board = await _repo.getBoard(widget.user.uid);
    final files = <int, File>{};
    for (final a in board) {
      final file = await _images.resolve(a.area.imagePath);
      if (file != null) files[a.area.id!] = file;
    }
    if (!mounted) return;
    setState(() {
      _board = board;
      _imageFiles = files;
      _loading = false;
    });
  }

  int get _achieved => _board.fold(0, (sum, a) => sum + a.achieved);
  int get _total => _board.fold(0, (sum, a) => sum + a.goals.length);

  // ─── Aktionen ──────────────────────────────────────────────────────────

  Future<void> _addArea() async {
    final values = await showTextFieldsDialog(context,
        title: 'Neuer Bereich', fields: const [DialogField('Name des Bereichs', required: true)]);
    if (values == null) return;
    final colors = visionBoardTemplate.map((t) => t.$2).toList();
    await _repo.createArea(VisionArea(
      userid: widget.user.uid,
      title: values[0]!,
      colorValue: colors[_board.length % colors.length],
    ));
    _load();
  }

  Future<void> _loadTemplate() async {
    setState(() => _busy = true);
    final images = <String?>[];
    for (final (_, _, asset, _) in visionBoardTemplate) {
      if (asset == null) {
        images.add(null);
        continue;
      }
      try {
        images.add(await _images.importAsset(asset));
      } catch (e) {
        debugPrint('Vorlagenbild $asset konnte nicht kopiert werden: $e');
        images.add(null);
      }
    }
    await _repo.createTemplateBoard(widget.user.uid, imagePaths: images);
    if (mounted) setState(() => _busy = false);
    _load();
  }

  Future<void> _addGoal(VisionArea area) async {
    final values = await showTextFieldsDialog(context, title: 'Neues Ziel', fields: const [
      DialogField('Ziel', required: true),
      DialogField('Zusatz (z. B. Kennzahl)'),
    ]);
    if (values == null) return;
    await _repo.createGoal(VisionGoal(areaId: area.id!, userid: widget.user.uid, title: values[0]!, note: values[1]));
    _load();
  }

  /// Name und Bild eines Bereichs bearbeiten.
  Future<void> _editArea(VisionArea area) async {
    final hasImage = _imageFiles.containsKey(area.id);
    final result = await showEditorSheet<(String, String?)>(context, (_) => _AreaSheet(area: area, hasImage: hasImage));
    if (result == null || !mounted) return;
    final (title, imageAction) = result;
    await runGuarded(context, () => _repo.updateArea(_withChanges(area, title: title)));
    if (imageAction == 'pick') {
      await _pickImage(_withChanges(area, title: title));
    } else if (imageAction == 'remove') {
      await _removeImage(_withChanges(area, title: title));
    } else {
      _load();
    }
  }

  Future<void> _editGoal(VisionGoal goal) async {
    final values = await showTextFieldsDialog(context, title: 'Ziel bearbeiten', fields: [
      DialogField('Ziel', initial: goal.title, required: true),
      DialogField('Zusatz (z. B. Kennzahl)', initial: goal.note),
    ]);
    if (values == null || !mounted) return;
    await runGuarded(
      context,
      () => _repo.updateGoal(VisionGoal(
        id: goal.id,
        areaId: goal.areaId,
        userid: goal.userid,
        title: values[0]!,
        note: values[1],
        isAchieved: goal.isAchieved,
        position: goal.position,
      )),
    );
    _load();
  }

  Future<void> _deleteGoal(VisionGoal goal) {
    late VisionDeletion deletion;
    return deleteWithUndo(
      context,
      label: goal.title,
      delete: () async => deletion = await _repo.deleteGoal(goal.id!),
      restore: () => _repo.restoreDeletion(deletion),
      onChanged: _load,
    );
  }

  VisionArea _withChanges(VisionArea area, {String? title, String? imagePath, bool clearImage = false}) => VisionArea(
        id: area.id,
        userid: area.userid,
        title: title ?? area.title,
        imagePath: clearImage ? null : (imagePath ?? area.imagePath),
        colorValue: area.colorValue,
        position: area.position,
      );

  Future<void> _pickImage(VisionArea area) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path == null) return;
      final stored = await _images.importFile(path);
      await _repo.updateArea(_withChanges(area, imagePath: stored));
      await _images.delete(area.imagePath);
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Bild konnte nicht übernommen werden: ${errorText(e)}')));
    }
  }

  Future<void> _removeImage(VisionArea area) async {
    await _repo.updateArea(_withChanges(area, clearImage: true));
    await _images.delete(area.imagePath);
    _load();
  }

  /// Löscht den Bereich mit Zielen und Plänen; „Rückgängig“ stellt alles samt Verknüpfungen wieder her.
  Future<void> _deleteArea(VisionArea area) {
    late VisionDeletion deletion;
    return deleteWithUndo(
      context,
      label: area.title,
      delete: () async => deletion = await _repo.deleteArea(area.id!),
      restore: () => _repo.restoreDeletion(deletion),
      onChanged: _load,
    );
  }

  Future<void> _toggleAchieved(VisionGoal goal) async {
    await _repo.setGoalAchieved(goal.id!, !goal.isAchieved);
    _load();
  }

  Future<void> _openPlan(VisionGoal goal) async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => GoalPlanScreen(user: widget.user, goalId: goal.id!)),
    );
    if (!mounted) return;
    if (result == kDeletedResult) return _deleteGoal(goal);
    _load();
  }

  // ─── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      floatingActionButton: AppFab(label: 'Bereich', heroTag: 'vision-fab', onPressed: _addArea),
      body: SafeArea(
        bottom: false,
        child: _loading || _busy
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : RefreshIndicator(
                color: c.accent,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: pagePadding(context),
                  children: [
                    _header(context),
                    const SizedBox(height: 18),
                    if (_board.isEmpty) _emptyState(context) else _grid(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = AppColors.of(context);
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 11, letterSpacing: 1.2, color: c.muted);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (Navigator.of(context).canPop()) ...[
          RoundIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Zurück', onTap: () => Navigator.of(context).pop()),
          const SizedBox(width: 12),
        ],
        Expanded(child: Text('VISION BOARD // LANGFRISTIGE ZIELE', style: mono)),
        Text('STATUS ${_two(_achieved)} / ${_two(_total)}', style: mono),
      ]),
      const SizedBox(height: 12),
      Divider(height: 1, color: c.line),
      const SizedBox(height: 14),
      const ScreenHeader(title: 'Meine Ziele'),
    ]);
  }

  Widget _emptyState(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const Icon(Icons.flag_outlined, size: 48),
        const SizedBox(height: 12),
        Text('Noch kein Vision Board', style: t.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Lege Bereiche wie „Gesundheit“ oder „Finanzen“ an und sammle darin deine großen Ziele.',
          textAlign: TextAlign.center,
          style: t.bodySmall,
        ),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
          ElevatedButton.icon(onPressed: _addArea, icon: const Icon(Icons.add), label: const Text('Bereich anlegen')),
          OutlinedButton.icon(onPressed: _loadTemplate, icon: const Icon(Icons.auto_awesome_outlined), label: const Text('Vorlage laden')),
        ]),
      ]),
    );
  }

  Widget _grid() {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 14.0;
      final columns = constraints.maxWidth >= 700 ? 2 : 1;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < _board.length; i++)
            SizedBox(
              width: width,
              child: SwipeTile(
                id: 'area-${_board[i].area.id}',
                onEdit: () => _editArea(_board[i].area),
                onDelete: () => _deleteArea(_board[i].area),
                child: _areaCard(context, i + 1, _board[i]),
              ),
            ),
        ],
      );
    });
  }

  Widget _areaCard(BuildContext context, int number, AreaWithGoals entry) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final area = entry.area;
    final color = Color(area.colorValue);
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 12, color: c.muted);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _areaImage(area, number, color, _imageFiles[area.id]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${_two(number)} '),
                TextSpan(text: '// ', style: TextStyle(color: c.dim)),
                TextSpan(text: area.title.toUpperCase()),
              ]),
              style: t.titleMedium?.copyWith(letterSpacing: 0.4),
            ),
          ),
          const SizedBox(width: 8),
          Text('${_two(entry.achieved)}/${_two(entry.goals.length)}', style: mono),
        ]),
        Divider(height: 18, color: c.line),
        for (final g in entry.goals) _goalRow(context, g),
        TextButton.icon(
          style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
          onPressed: () => _addGoal(area),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Ziel hinzufügen'),
        ),
      ]),
    );
  }

  Widget _areaImage(VisionArea area, int number, Color color, File? image) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(fit: StackFit.expand, children: [
          if (image != null)
            Image.file(image, fit: BoxFit.cover, key: ValueKey(image.path))
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.35)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Text(_two(number),
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -1)),
              ),
            ),
          Positioned(
            right: 8,
            bottom: 8,
            child: image == null
                ? FilledButton.tonalIcon(
                    onPressed: () => _pickImage(area),
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: const Text('Bild hinzufügen'),
                  )
                : IconButton.filledTonal(
                    tooltip: 'Bild ändern',
                    onPressed: () => _pickImage(area),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _goalRow(BuildContext context, GoalSummary summary) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final goal = summary.goal;
    return SwipeTile(
      id: 'vision-goal-${goal.id}',
      onEdit: () => _editGoal(goal),
      onDelete: () => _deleteGoal(goal),
      child: InkWell(
      onTap: () => _openPlan(goal),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line.withValues(alpha: 0.5)))),
        child: Row(children: [
          AppCheck(checked: goal.isAchieved, size: 20, onTap: () => _toggleAchieved(goal)),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: goal.title),
                if (goal.note != null)
                  TextSpan(text: '  (${goal.note})', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: c.dim)),
              ]),
              style: t.bodyMedium?.copyWith(
                color: goal.isAchieved ? c.dim : c.text,
                decoration: goal.isAchieved ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (summary.stepsTotal > 0) ...[
            const SizedBox(width: 8),
            Text('${summary.stepsDone}/${summary.stepsTotal}', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: c.muted)),
          ],
          Icon(Icons.chevron_right_rounded, size: 20, color: c.dim),
        ]),
      ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// Name und Bild eines Bereichs. Liefert (Name, Bildaktion: 'pick' | 'remove' | null).
class _AreaSheet extends StatefulWidget {
  final VisionArea area;
  final bool hasImage;
  const _AreaSheet({required this.area, required this.hasImage});

  @override
  State<_AreaSheet> createState() => _AreaSheetState();
}

class _AreaSheetState extends State<_AreaSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.area.title);
  String? _imageAction;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((_title.text.trim(), _imageAction));
  }

  @override
  Widget build(BuildContext context) {
    return EditorSheet(
      formKey: _formKey,
      title: 'Bereich bearbeiten',
      onSave: _save,
      children: [
        TextFormField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Name des Bereichs'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Bitte einen Namen eingeben' : null,
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          AppChip(
            label: widget.hasImage ? 'Bild ändern' : 'Bild hinzufügen',
            selected: _imageAction == 'pick',
            onTap: () => setState(() => _imageAction = _imageAction == 'pick' ? null : 'pick'),
          ),
          if (widget.hasImage)
            AppChip(
              label: 'Bild entfernen',
              selected: _imageAction == 'remove',
              onTap: () => setState(() => _imageAction = _imageAction == 'remove' ? null : 'remove'),
            ),
        ]),
      ],
    );
  }
}
