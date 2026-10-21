import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:frontend/core/models/dates.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/habits/services/habit_actions.dart';
import 'package:frontend/features/habits/models/habit.dart';
import 'package:frontend/features/habits/screens/add_habit_screen.dart';

class HabitTrackerScreen extends StatefulWidget {
  final UserModel user;
  const HabitTrackerScreen({super.key, required this.user});

  @override
  State<HabitTrackerScreen> createState() => _HabitTrackerScreenState();
}

class HabitData {
  Habit habit;
  int streak;
  List<bool> statusList;
  List<DateTime> dateMapping;
  List<String> labels;
  int todayIndex;
  HabitData(this.habit, this.streak, this.statusList, this.dateMapping, this.labels, this.todayIndex);
}

class _WeekDay {
  final DateTime date;
  final double progress; // Anteil erledigter geplanter Habits
  _WeekDay(this.date, this.progress);
}

class _HabitTrackerScreenState extends State<HabitTrackerScreen> {
  static const _dayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  bool _isLoading = true;
  List<HabitData> _habitDataList = [];
  List<_WeekDay> _week = [];

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _loadHabits();
  }

  Future<void> _loadHabits() async {
    final db = context.read<HabitRepository>();
    final allHabits = await db.getAllHabits(widget.user.uid);
    final today = _today;
    final dataList = <HabitData>[];

    for (final h in allHabits) {
      final streak = await db.calculateStreak(h.id!);
      final timeline = [
        for (int i = 3; i >= 1; i--) HabitActions.pastScheduledDate(today, h.selectedDays, i),
        today,
        for (int i = 1; i <= 3; i++) HabitActions.futureScheduledDate(today, h.selectedDays, i),
      ];
      final status = <bool>[];
      for (final d in timeline) {
        status.add(await db.isHabitCompletedOnDate(h.id!, d));
      }
      dataList.add(HabitData(h, streak, status, timeline, timeline.map((d) => _dayLabels[d.weekday - 1]).toList(), 3));
    }

    // Wochenstreifen Mo–So der aktuellen Woche
    final monday = weekStart(today);
    final week = <_WeekDay>[];
    for (int i = 0; i < 7; i++) {
      final d = DateTime(monday.year, monday.month, monday.day + i);
      if (d.isAfter(today)) {
        week.add(_WeekDay(d, 0));
        continue;
      }
      final scheduled = allHabits.where((h) => h.selectedDays.contains(d.weekday)).toList();
      var done = 0;
      for (final h in scheduled) {
        if (await db.isHabitCompletedOnDate(h.id!, d)) done++;
      }
      week.add(_WeekDay(d, scheduled.isEmpty ? 0 : done / scheduled.length));
    }

    if (!mounted) return;
    setState(() {
      _habitDataList = dataList;
      _week = week;
      _isLoading = false;
    });
  }

  Future<void> _toggleHabit(Habit habit, DateTime date, bool currentlyCompleted) async {
    await HabitActions.toggle(
      habits: context.read<HabitRepository>(),
      users: context.read<UserRepository>(),
      userId: widget.user.uid, habitId: habit.id!, date: date, currentlyCompleted: currentlyCompleted);
    _loadHabits();
  }

  Future<void> _deleteHabit(Habit habit) {
    final repo = context.read<HabitRepository>();
    return deleteWithUndo(
      context,
      label: habit.name,
      delete: () => repo.deleteHabit(habit.id!),
      restore: () => repo.restoreHabit(habit.id!),
      onChanged: _loadHabits,
    );
  }

  Future<void> _openEditor([Habit? habit]) async {
    final result = await Navigator.push<Object?>(
        context, MaterialPageRoute(builder: (_) => AddHabitScreen(userid: widget.user.uid, habit: habit)));
    if (!mounted) return;
    if (result == kDeletedResult && habit != null) {
      await _deleteHabit(habit);
    } else {
      _loadHabits();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final todayScheduled = _habitDataList.where((d) => d.habit.selectedDays.contains(_today.weekday)).toList();
    final doneToday = todayScheduled.where((d) => d.statusList[d.todayIndex]).length;

    return Scaffold(
      floatingActionButton: AppFab(label: 'Habit', heroTag: 'habit-fab', onPressed: () => _openEditor()),
      body: SafeArea(
        bottom: false,
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : RefreshIndicator(
                color: c.accent,
                onRefresh: _loadHabits,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: pagePadding(context),
                  children: [
                    SummaryRow('$doneToday von ${todayScheduled.length} heute erledigt'),
                    const SizedBox(height: 8),
                    _weekStrip(context),
                    const SizedBox(height: 18),
                    if (_habitDataList.isEmpty)
                      EmptyState(
                        icon: Icons.local_fire_department_outlined,
                        title: 'Noch keine Habits',
                        message: 'Gewohnheiten jeden Tag abhaken und Serien aufbauen.',
                        action: OutlinedButton(onPressed: () => _openEditor(), child: const Text('Erstes Habit anlegen')),
                      )
                    else
                      ..._habitDataList.map((d) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _habitCard(context, d))),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _weekStrip(BuildContext context) {
    final c = AppColors.of(context);
    final today = _today;
    return Row(
      children: _week.asMap().entries.map((e) {
        final d = e.value;
        final isToday = d.date == today;
        final isFuture = d.date.isAfter(today);
        final bg = isToday ? c.text : c.card;
        final fg = isToday ? c.bg : (isFuture ? c.dim : c.text);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: e.key == 0 ? 0 : 6),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Text(_dayLabels[d.date.weekday - 1], style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: fg.withValues(alpha: 0.75))),
                const SizedBox(height: 6),
                Text('${d.date.day}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
                const SizedBox(height: 6),
                SizedBox(
                  width: 22,
                  child: AppProgressBar(
                    value: d.progress,
                    height: 4,
                    color: isToday ? c.bg : c.accentText,
                    track: isToday ? c.bg.withValues(alpha: 0.2) : c.line,
                  ),
                ),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _habitCard(BuildContext context, HabitData data) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final col = Color(data.habit.colorValue);
    final today = _today;

    return SwipeTile(
      id: 'habit-${data.habit.id}',
      onEdit: () => _openEditor(data.habit),
      onDelete: () => _deleteHabit(data.habit),
      child: AppCard(
        radius: 24,
        onTap: () => _openEditor(data.habit),
        child: Column(children: [
          Row(children: [
            IconTile(icon: IconData(data.habit.iconCodePoint, fontFamily: data.habit.iconFontFamily), color: col, size: 44, iconSize: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(data.habit.name, style: t.titleMedium?.copyWith(fontSize: 16)),
                const SizedBox(height: 2),
                Text(HabitActions.scheduleSummary(data.habit.selectedDays), style: t.labelMedium),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(children: [
                Icon(Icons.local_fire_department_rounded, size: 20, color: c.streak),
                const SizedBox(width: 2),
                Text('${data.streak}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              ]),
              Text('in Folge', style: TextStyle(fontSize: 11, color: c.dim)),
            ]),
          ]),
          const SizedBox(height: 16),
          Row(
            children: List.generate(data.statusList.length, (i) {
              final date = data.dateMapping[i];
              final done = data.statusList[i];
              final isToday = i == data.todayIndex;
              final isFuture = date.isAfter(today);
              final scheduled = data.habit.selectedDays.contains(date.weekday);
              final canTap = !isFuture && scheduled;

              Color border;
              if (done || (isToday && scheduled)) {
                border = col;
              } else if (isFuture) {
                border = Colors.transparent;
              } else {
                border = c.line;
              }

              return Expanded(
                child: Column(children: [
                  Text(
                    data.labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                      color: isToday ? col : (isFuture ? c.dim.withValues(alpha: 0.6) : c.muted),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: canTap ? () => _toggleHabit(data.habit, date, done) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? col : (isFuture ? c.line.withValues(alpha: 0.25) : Colors.transparent),
                        border: Border.all(color: border, width: 2),
                      ),
                      child: done
                          ? Icon(Icons.check_rounded, size: 20, color: c.onAccent)
                          : (!scheduled ? Icon(Icons.remove_rounded, size: 14, color: c.dim) : null),
                    ),
                  ),
                ]),
              );
            }),
          ),
        ]),
      ),
    );
  }
}
