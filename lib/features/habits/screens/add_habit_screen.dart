import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/habits/models/habit.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';

class AddHabitScreen extends StatefulWidget {
  final int userid;
  final Habit? habit;

  const AddHabitScreen({super.key, required this.userid, this.habit});

  @override
  State<AddHabitScreen> createState() => _AddHabitScreenState();
}

class _AddHabitScreenState extends State<AddHabitScreen> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  int _colorValue = 4280391411; // AppTheme.primary approx
  int _iconCodePoint = 58249; // Icons.local_fire_department
  String _iconFontFamily = 'MaterialIcons';
  late TextEditingController _iconController;
  List<int> _selectedDays = [1, 2, 3, 4, 5, 6, 7]; // Default: alle Tage

  static const List<String> _dayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  final List<Color> _swatches = [
    const Color(0xFF2196F3), // Blue
    const Color(0xFFE91E63), // Pink
    const Color(0xFF4CAF50), // Green
    const Color(0xFFFF9800), // Orange
    const Color(0xFF9C27B0), // Purple
    const Color(0xFFF44336), // Red
  ];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _iconController = TextEditingController();
    if (widget.habit != null) {
      _name = widget.habit!.name;
      _colorValue = widget.habit!.colorValue;
      _iconCodePoint = widget.habit!.iconCodePoint;
      _iconFontFamily = widget.habit!.iconFontFamily;
      _selectedDays = List<int>.from(widget.habit!.selectedDays);
    }
  }

  @override
  void dispose() {
    _iconController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selectedDays.isEmpty) {
      showAppSnack(context, 'Bitte wähle mindestens einen Wochentag aus.', error: true);
      return;
    }
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      try {
        _formKey.currentState!.save();
        final h = Habit(
          id: widget.habit?.id,
          name: _name,
          frequency: 'custom',
          userid: widget.userid,
          colorValue: _colorValue,
          iconCodePoint: _iconCodePoint,
          iconFontFamily: _iconFontFamily,
          selectedDays: _selectedDays,
        );
        final repo = context.read<HabitRepository>();
        final navigator = Navigator.of(context);
        if (widget.habit == null) {
          await repo.createHabit(h);
        } else {
          await repo.updateHabit(h);
        }
        navigator.pop();
      } catch (e) {
        if (mounted) showAppSnack(context, 'Speichern fehlgeschlagen: ${errorText(e)}', error: true);
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
        _selectedDays.sort();
      }
    });
  }

  String _getSelectedDaysSummary() {
    if (_selectedDays.length == 7) return 'Jeden Tag';
    if (_selectedDays.length == 5 && !_selectedDays.contains(6) && !_selectedDays.contains(7)) return 'Wochentags';
    if (_selectedDays.length == 2 && _selectedDays.contains(6) && _selectedDays.contains(7)) return 'Am Wochenende';
    if (_selectedDays.isEmpty) return 'Keine Tage ausgewählt';
    return _selectedDays.map((d) => _dayLabels[d - 1]).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isNew = widget.habit == null;
    final color = Color(_colorValue);
    final presets = <(String, List<int>)>[
      ('Jeden Tag', [1, 2, 3, 4, 5, 6, 7]),
      ('Wochentags', [1, 2, 3, 4, 5]),
      ('Wochenende', [6, 7]),
    ];
    return Scaffold(
      appBar: ModernAppBar(title: isNew ? 'Neues Habit' : 'Habit bearbeiten'),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FormFieldCard(
                icon: Icons.local_fire_department_rounded,
                label: 'Name',
                child: TextFormField(
                  initialValue: _name,
                  autofocus: isNew,
                  decoration: bareInputDecoration.copyWith(hintText: 'z. B. 10 Minuten lesen'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Bitte Namen eingeben' : null,
                  onSaved: (v) => _name = v!.trim(),
                ),
              ),
              const SizedBox(height: 8),
              GroupLabel('Wiederholung', trailing: _getSelectedDaysSummary()),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (index) {
                  final day = index + 1; // 1=Mo, 7=So
                  final isSelected = _selectedDays.contains(day);
                  return Semantics(
                    button: true,
                    selected: isSelected,
                    child: GestureDetector(
                      onTap: () => _toggleDay(day),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected ? color : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? color : c.line, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            _dayLabels[index],
                            style: TextStyle(color: isSelected ? Colors.white : c.text, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (label, days) in presets)
                  AppChip(
                    label: label,
                    selected: _selectedDays.length == days.length && days.every(_selectedDays.contains),
                    onTap: () => setState(() => _selectedDays = List.of(days)),
                  ),
              ]),
              const SizedBox(height: 20),
              IconPickerField(
                label: 'Icon',
                controller: _iconController,
                onPicked: (codePoint, fontFamily) => setState(() {
                  _iconCodePoint = codePoint;
                  _iconFontFamily = fontFamily;
                }),
              ),
              const GroupLabel('Farbe'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _swatches.map((swatch) {
                  final isSelected = _colorValue == swatch.toARGB32();
                  return Semantics(
                    button: true,
                    selected: isSelected,
                    child: GestureDetector(
                      onTap: () => setState(() => _colorValue = swatch.toARGB32()),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: swatch,
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: c.text, width: 3) : null,
                        ),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
              FormActions(
                isNew: isNew,
                busy: _isSaving,
                onSave: _save,
                onDelete: () => Navigator.of(context).pop(kDeletedResult),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
