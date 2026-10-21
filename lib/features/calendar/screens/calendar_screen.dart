import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:provider/provider.dart';
import 'package:frontend/core/services/device_calendar_service.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/calendar/services/calendar_sync.dart';
import 'package:frontend/features/calendar/widgets/external_event_card.dart';
import 'package:frontend/features/vision/repositories/vision_repository.dart';
import 'package:frontend/features/vision/widgets/goal_hint.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/screens/add_update_appointment_screen.dart';
import 'package:frontend/features/auth/models/user.dart';

class CalendarScreen extends StatefulWidget {
  final UserModel user;
  const CalendarScreen({super.key, required this.user});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  Map<DateTime, List<Appointment>> _grouped = {};
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isLoading = true;
  Map<int, String> _goalByStep = {};

  /// Termine aus dem Handy-Kalender für den sichtbaren Monat (nur angezeigt, nie gespeichert).
  Map<DateTime, List<ExternalEvent>> _external = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    final vision = context.read<VisionRepository>();
    final all = await context.read<AppointmentRepository>().getAllAppointments(widget.user.uid);
    final goals = await vision.goalTitlesForSteps(widget.user.uid);
    final groups = <DateTime, List<Appointment>>{};
    final now = DateTime.now();
    // Wiederkehrende Einträge erscheinen in jedem Vorkommen des sichtbaren Bereichs –
    // jährliche (Geburtstage …) ±5 Jahre, häufigere 1 Jahr zurück und 2 Jahre voraus.
    for (final a in all) {
      final yearly = a.repeatYearly || !a.repeats;
      final from = yearly ? DateTime(now.year - 5) : DateTime(now.year - 1, now.month, now.day);
      final to = yearly ? DateTime(now.year + 5, 12, 31) : DateTime(now.year + 2, now.month, now.day);
      for (final occ in a.occurrencesBetween(from, to)) {
        groups.putIfAbsent(DateTime(occ.year, occ.month, occ.day), () => []).add(a);
      }
    }
    for (final l in groups.values) {
      l.sort((a, b) => a.allDay != b.allDay
          ? (a.allDay ? -1 : 1)
          : (a.date.hour * 60 + a.date.minute).compareTo(b.date.hour * 60 + b.date.minute));
    }
    if (!mounted) return;
    setState(() {
      _goalByStep = goals;
      _grouped = groups;
      _isLoading = false;
    });
    await _loadExternal();
  }

  /// Handy-Termine des sichtbaren Monats (eine Woche Rand für die Nachbartage im Raster).
  Future<void> _loadExternal() async {
    final month = DateTime(_focusedDay.year, _focusedDay.month);
    final from = month.subtract(const Duration(days: 7));
    final to = DateTime(month.year, month.month + 1, 8);
    final events = await context.read<CalendarSync>().events(widget.user.uid, from, to);
    if (!mounted) return;
    setState(() => _external = groupExternalByDay(events));
  }

  List<Appointment> _eventsFor(DateTime day) => _grouped[DateTime(day.year, day.month, day.day)] ?? [];
  List<ExternalEvent> _externalFor(DateTime day) => _external[DateTime(day.year, day.month, day.day)] ?? const [];

  Future<void> _deleteAppointment(Appointment a) {
    final repo = context.read<AppointmentRepository>();
    return deleteWithUndo(
      context,
      label: a.title,
      delete: () => repo.deleteAppointment(a.id!),
      restore: () => repo.restoreAppointment(a),
      onChanged: _loadAppointments,
    );
  }

  Future<void> _openEditor({Appointment? appointment}) async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => appointment == null
            ? AddUpdateAppointmentScreen(userid: widget.user.uid, initialDate: _selectedDay ?? _focusedDay)
            : AddUpdateAppointmentScreen(userid: widget.user.uid, appointment: appointment),
      ),
    );
    if (!mounted) return;
    if (result == kDeletedResult && appointment != null) {
      await _deleteAppointment(appointment);
    } else {
      _loadAppointments();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final selected = _selectedDay ?? _focusedDay;
    final events = _eventsFor(selected);
    final external = _externalFor(selected);
    final count = events.length + external.length;
    final isToday = isSameDay(selected, DateTime.now());
    // LifeHub- und Handy-Termine nach Uhrzeit gemischt, ganztägige zuerst
    int minutes(DateTime d, bool allDay) => allDay ? -1 : d.hour * 60 + d.minute;
    final cards = [
      for (final e in events) (minutes(e.date, e.allDay), _eventCard(context, e)),
      for (final x in external) (minutes(x.start, x.allDay), ExternalEventCard(event: x)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return Scaffold(
      floatingActionButton: AppFab(label: 'Termin', heroTag: 'appointment-fab', onPressed: () => _openEditor()),
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : ListView(
                padding: pagePadding(context),
                children: [
                  SummaryRow(
                    DateFormat('MMMM yyyy', 'de_DE').format(_focusedDay),
                    actions: [
                      // Nur nötig, wenn man von heute weggeblättert hat
                      if (!isToday || !isSameDay(_focusedDay, DateTime.now()))
                        AppChip(
                          label: 'Heute',
                          onTap: () {
                            setState(() {
                              _focusedDay = DateTime.now();
                              _selectedDay = _focusedDay;
                            });
                            _loadExternal();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AppCard(
                    radius: 24,
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                    child: _calendar(context),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${isToday ? 'Heute · ' : ''}${DateFormat('EEEE, d. MMMM', 'de_DE').format(selected)}',
                          style: t.titleLarge,
                        ),
                      ),
                      Text(count == 1 ? '1 Termin' : '$count Termine', style: t.bodySmall),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (cards.isEmpty)
                    GestureDetector(
                      onTap: () => _openEditor(),
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                          border: Border.all(color: c.line, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text('Keine Termine an diesem Tag', style: t.bodySmall?.copyWith(color: c.dim)),
                      ),
                    )
                  else
                    for (final (_, card) in cards) Padding(padding: const EdgeInsets.only(bottom: 10), child: card),
                ],
              ),
      ),
    );
  }

  Widget _calendar(BuildContext context) {
    final c = AppColors.of(context);
    final today = DateTime.now();

    Widget cell(DateTime day, {bool selected = false, bool isToday = false, bool outside = false}) {
      final past = day.isBefore(DateTime(today.year, today.month, today.day));
      final bg = selected ? c.accent : (isToday ? c.line.withValues(alpha: 0.6) : Colors.transparent);
      final fg = selected ? c.onAccent : (outside ? c.dim.withValues(alpha: 0.4) : (past ? c.dim : c.text));
      final hasEvents = (_eventsFor(day).isNotEmpty || _externalFor(day).isNotEmpty) && !outside;
      return Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${day.day}', style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasEvents ? (selected ? c.onAccent : c.event) : Colors.transparent,
              ),
            ),
          ]),
        ),
      );
    }

    return TableCalendar<Appointment>(
      locale: 'de_DE',
      firstDay: DateTime.utc(2000, 1, 1),
      lastDay: DateTime.utc(2100, 12, 31),
      focusedDay: _focusedDay,
      startingDayOfWeek: StartingDayOfWeek.monday,
      availableGestures: AvailableGestures.horizontalSwipe,
      rowHeight: 46,
      daysOfWeekHeight: 22,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        final otherMonth = focusedDay.month != _focusedDay.month || focusedDay.year != _focusedDay.year;
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
        if (otherMonth) _loadExternal();
      },
      onPageChanged: (focused) {
        setState(() => _focusedDay = focused);
        _loadExternal();
      },
      eventLoader: _eventsFor,
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextFormatter: (date, locale) => DateFormat('MMMM', locale).format(date),
        titleTextStyle: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w600),
        leftChevronIcon: Icon(Icons.chevron_left_rounded, color: c.muted),
        rightChevronIcon: Icon(Icons.chevron_right_rounded, color: c.muted),
        headerPadding: const EdgeInsets.symmetric(vertical: 4),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        dowTextFormatter: (date, locale) => DateFormat('E', locale).format(date).replaceAll('.', '').toUpperCase(),
        weekdayStyle: TextStyle(color: c.dim, fontSize: 11, fontFamily: 'monospace'),
        weekendStyle: TextStyle(color: c.dim, fontSize: 11, fontFamily: 'monospace'),
      ),
      calendarBuilders: CalendarBuilders<Appointment>(
        defaultBuilder: (_, day, __) => cell(day),
        todayBuilder: (_, day, __) => cell(day, isToday: true),
        selectedBuilder: (_, day, __) => cell(day, selected: true),
        outsideBuilder: (_, day, __) => cell(day, outside: true),
        markerBuilder: (_, __, ___) => const SizedBox.shrink(), // Punkt wird in der Zelle gezeichnet
      ),
    );
  }

  /// „Jährlich · 36 Jahre“ für wiederkehrende Einträge am ausgewählten Tag.
  String? _yearsLabel(Appointment e) {
    if (!e.repeats) return null;
    if (!e.repeatYearly) return e.repeat.label(e.date);
    final occ = e.occurrenceOn(_selectedDay ?? _focusedDay);
    final years = occ == null ? null : e.yearsAt(occ);
    return years == null ? 'Jährlich' : 'Jährlich · $years Jahre';
  }

  Widget _eventCard(BuildContext context, Appointment e) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return SwipeTile(
      id: 'appointment-${e.id}',
      onEdit: () => _openEditor(appointment: e),
      onDelete: () => _deleteAppointment(e),
      child: AppCard(
        onTap: () => _openEditor(appointment: e),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, decoration: BoxDecoration(color: c.event, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(e.title, style: t.titleMedium),
                if (_yearsLabel(e) != null) Text(_yearsLabel(e)!, style: t.labelMedium?.copyWith(color: c.event)),
                if (e.description?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(e.description!, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                if (_goalByStep[e.goalStepId] != null) GoalHint(_goalByStep[e.goalStepId]!),
              ]),
            ),
            const SizedBox(width: 12),
            if (e.allDay)
              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Icon(e.repeatYearly ? Icons.cake_rounded : Icons.sticky_note_2_outlined, color: c.event),
                const SizedBox(height: 2),
                Text('Ganztägig', style: t.labelMedium),
              ])
            else
              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(DateFormat('HH:mm').format(e.date), style: t.titleMedium),
                const SizedBox(height: 2),
                Text('bis ${DateFormat('HH:mm').format(e.endDate)}', style: t.labelMedium),
              ]),
          ]),
        ),
      ),
    );
  }
}
