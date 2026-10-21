import 'package:flutter/material.dart';
import 'package:frontend/core/models/repeat.dart';
import 'package:frontend/core/ui/repeat_picker.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:intl/intl.dart';

class AddUpdateAppointmentScreen extends StatefulWidget {
  final int userid;
  final Appointment? appointment;
  final DateTime? initialDate;

  /// Neuen Termin direkt einem Schritt eines Ziel-Plans zuordnen.
  final int? goalStepId;

  const AddUpdateAppointmentScreen({super.key, required this.userid, this.appointment, this.initialDate, this.goalStepId});

  @override
  State<AddUpdateAppointmentScreen> createState() => _AddUpdateAppointmentScreenState();
}

class _AddUpdateAppointmentScreenState extends State<AddUpdateAppointmentScreen> {
  static const _durationPresets = [15, 30, 45, 60, 90, 120];

  final _formKey = GlobalKey<FormState>();
  late String _title;
  String? _description;
  late DateTime _start;
  late int _duration;
  late int? _reminder;
  late bool _allDay;
  late Repeat _repeat;
  bool _saving = false;

  bool get _yearly => _repeat.freq == RepeatFreq.yearly;

  DateTime get _end => _start.add(Duration(minutes: _duration));

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    final existing = widget.appointment;
    if (existing != null) {
      _title = existing.title;
      _description = existing.description;
      _start = existing.date.toLocal();
      _duration = existing.durationMinutes;
      _reminder = existing.reminderMinutes;
      _allDay = existing.allDay;
      _repeat = existing.repeat;
    } else {
      _reminder = Appointment.defaultReminderMinutes;
      _allDay = false;
      _repeat = Repeat.none;
      _title = '';
      _description = null;
      _duration = Appointment.defaultDurationMinutes;

      // Startwert immer lokal und nie in der Vergangenheit
      // (TableCalendar liefert Tage als UTC-Mitternacht).
      final now = DateTime.now();
      final today = _dayOnly(now);
      final picked = widget.initialDate;
      var day = picked == null ? today : DateTime(picked.year, picked.month, picked.day);
      if (day.isBefore(today)) day = today;
      _start = day == today ? DateTime(now.year, now.month, now.day, now.hour + 1) : DateTime(day.year, day.month, day.day, 9);
    }
  }

  /// Nur neue oder verschobene Termine dürfen nicht in der Vergangenheit liegen –
  /// ein vergangener Termin darf weiterhin nur inhaltlich bearbeitet werden.
  bool get _startIsInvalidPast {
    // Wiederkehrende Einträge (z. B. Geburtstage) dürfen in der Vergangenheit beginnen.
    if (!_repeat.isNone) return false;
    final original = widget.appointment;
    final moved = original == null || !_start.isAtSameMomentAs(original.date.toLocal());
    if (_allDay) return moved && _dayOnly(_start).isBefore(_dayOnly(DateTime.now()));
    return moved && _start.isBefore(DateTime.now());
  }

  void _setAllDay(bool value) => setState(() {
        _allDay = value;
        final options = value ? Appointment.allDayReminderOptions : Appointment.reminderOptions;
        if (!options.contains(_reminder)) _reminder = value ? 0 : Appointment.defaultReminderMinutes;
      });

  /// Vorlage „Geburtstag“: ganztägig, jährlich, Erinnerung am Tag.
  void _birthdayPreset() => setState(() {
        _allDay = true;
        _repeat = Repeat.yearly;
        _reminder = 0;
      });

  Future<void> _pickDate() async {
    final today = _dayOnly(DateTime.now());
    final original = widget.appointment?.date.toLocal();
    // firstDate darf nicht nach initialDate liegen (sonst wirft der Picker).
    final firstDate = !_repeat.isNone ? DateTime(1900) : (original != null && _dayOnly(original).isBefore(today) ? _dayOnly(original) : today);
    final initial = _dayOnly(_start).isBefore(firstDate) ? firstDate : _start;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _start = DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute));
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (picked != null) {
      setState(() => _start = DateTime(_start.year, _start.month, _start.day, picked.hour, picked.minute));
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_end));
    if (picked == null) return;
    var end = DateTime(_start.year, _start.month, _start.day, picked.hour, picked.minute);
    if (!end.isAfter(_start)) {
      // Endzeit vor/gleich Beginn → als Termin über Mitternacht am Folgetag werten.
      end = end.add(const Duration(days: 1));
    }
    setState(() => _duration = end.difference(_start).inMinutes);
  }

  String _durationLabel(int minutes) {
    if (minutes < 60) return '$minutes Min';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h Std' : '$h Std $m Min';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startIsInvalidPast) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Der Termin darf nicht in der Vergangenheit liegen.')));
      return;
    }
    _formKey.currentState!.save();

    final a = Appointment(
      id: widget.appointment?.id,
      title: _title,
      description: _description,
      date: _allDay ? _dayOnly(_start) : _start,
      durationMinutes: _allDay ? 24 * 60 : _duration,
      userid: widget.userid,
      goalStepId: widget.appointment?.goalStepId ?? widget.goalStepId,
      reminderMinutes: _reminder,
      allDay: _allDay,
      repeat: _repeat,
    );

    final repo = context.read<AppointmentRepository>();
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final ok = await runGuarded(context, () async {
        if (a.id == null) {
          await repo.createAppointment(a);
        } else {
          await repo.updateAppointment(a);
        }
        return true;
      });
      if (ok == true) navigator.pop(a);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isEditing = widget.appointment != null;
    final crossesMidnight = !DateUtils.isSameDay(_start, _end);

    return Scaffold(
      appBar: ModernAppBar(title: isEditing ? 'Termin bearbeiten' : 'Neuer Termin'),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FormFieldCard(
                icon: Icons.event_rounded,
                label: 'Titel',
                child: TextFormField(
                  initialValue: _title,
                  autofocus: !isEditing,
                  decoration: bareInputDecoration.copyWith(hintText: 'z. B. Zahnarzt'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Bitte Titel eingeben' : null,
                  onSaved: (v) => _title = v!.trim(),
                ),
              ),
              FormFieldCard(
                icon: Icons.notes_rounded,
                label: 'Beschreibung',
                child: TextFormField(
                  initialValue: _description,
                  minLines: 1,
                  maxLines: 4,
                  decoration: bareInputDecoration.copyWith(hintText: 'Optional'),
                  onSaved: (v) => _description = v?.trim().isEmpty == true ? null : v!.trim(),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.cake_rounded, size: 18),
                  label: const Text('Als Geburtstag'),
                  onPressed: _birthdayPreset,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ganztägig'),
                subtitle: const Text('Nur als Notiz an diesem Tag, ohne Uhrzeit'),
                value: _allDay,
                onChanged: _setAllDay,
              ),
              RepeatPicker(value: _repeat, start: _start, onChanged: (r) => setState(() => _repeat = r)),
              const SizedBox(height: 16),
              GroupLabel(_yearly ? 'Datum (erstes Jahr, z. B. Geburtsdatum)' : (!_repeat.isNone ? 'Erster Termin' : (_allDay ? 'Datum' : 'Beginn'))),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(DateFormat('dd.MM.yyyy').format(_start)),
                  ),
                ),
                if (!_allDay) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickStartTime,
                      icon: const Icon(Icons.access_time),
                      label: Text(DateFormat('HH:mm').format(_start)),
                    ),
                  ),
                ],
              ]),
              if (_startIsInvalidPast)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text('Der Beginn liegt in der Vergangenheit.', style: TextStyle(color: c.negative, fontSize: 13)),
                ),
              if (!_allDay) ...[
                const SizedBox(height: 24),
                GroupLabel('Dauer', trailing: _durationLabel(_duration)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _durationPresets
                      .map((m) => AppChip(label: _durationLabel(m), selected: _duration == m, onTap: () => setState(() => _duration = m)))
                      .toList(),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickEndTime,
                  icon: const Icon(Icons.hourglass_bottom_rounded),
                  label: Text('Ende: ${DateFormat('HH:mm').format(_end)}${crossesMidnight ? ' (Folgetag)' : ''}'),
                ),
              ],
              const SizedBox(height: 24),
              GroupLabel('Erinnerung', trailing: Appointment.reminderLabel(_reminder, allDay: _allDay)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in _allDay ? Appointment.allDayReminderOptions : Appointment.reminderOptions)
                    AppChip(
                      label: Appointment.reminderLabel(m, allDay: _allDay),
                      selected: _reminder == m,
                      onTap: () => setState(() => _reminder = m),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              FormActions(
                isNew: !isEditing,
                busy: _saving,
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
