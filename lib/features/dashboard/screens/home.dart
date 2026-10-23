import 'package:flutter/material.dart';
import 'package:frontend/core/services/device_calendar_service.dart';
import 'package:frontend/features/calendar/services/calendar_sync.dart';
import 'package:frontend/features/calendar/widgets/external_event_card.dart';
import 'package:frontend/app/app_tabs.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/dates.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/screens/wrapper.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/screens/add_update_appointment_screen.dart';
import 'package:frontend/features/dashboard/widgets/global_search_delegate.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/fitness/models/workout.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/profile/screens/profile_screen.dart';
import 'package:frontend/features/finance/services/prediction_service.dart';
import 'package:frontend/features/habits/services/habit_actions.dart';
import 'package:frontend/features/habits/models/habit.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/inventory/widgets/inventory_widgets.dart';
import 'package:frontend/features/journal/models/journal_entry.dart';
import 'package:frontend/features/journal/repositories/journal_repository.dart';
import 'package:frontend/features/journal/screens/journal_editor_screen.dart';
import 'package:frontend/features/journal/widgets/journal_widgets.dart';
import 'package:frontend/features/contacts/models/contact.dart';
import 'package:frontend/features/contacts/repositories/contact_repository.dart';
import 'package:frontend/features/contacts/screens/contacts_screen.dart';
import 'package:frontend/features/contacts/widgets/contact_widgets.dart';
import 'package:frontend/features/learning/repositories/learning_repository.dart';
import 'package:frontend/features/more/more_screen.dart';
import 'package:frontend/features/learning/screens/study_screen.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/repositories/meal_plan_repository.dart';
import 'package:frontend/features/meals/screens/recipe_screen.dart';
import 'package:frontend/features/meals/widgets/meal_widgets.dart';
import 'package:frontend/features/receipts/widgets/missing_receipt_banner.dart';
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/todos/screens/add_update_todo_screen.dart';
import 'package:frontend/features/vision/models/vision.dart';
import 'package:frontend/features/vision/repositories/vision_repository.dart';
import 'package:frontend/features/vision/screens/vision_board_screen.dart';

class Home extends StatefulWidget {
  const Home({super.key, required this.user, this.onTabNav});
  final UserModel user;
  final TabNavigator? onTabNav;

  @override
  State<Home> createState() => _HomeState();
}

class _TodayHabit {
  final Habit habit;
  final int streak;
  final bool done;
  _TodayHabit(this.habit, this.streak, this.done);
}

class _HomeState extends State<Home> {
  late UserModel _user;
  bool _isLoading = true;
  List<_TodayHabit> _habits = [];
  List<Todo> _todayTodos = [];
  /// Die nächsten Termine – aus LifeHub (mit nächstem Vorkommen, jährliche evtl. im Folgejahr)
  /// und aus dem Handy-Kalender.
  List<_NextUp> _next = [];
  double _monthlyBalance = 0;
  ForecastBreakdown? _forecast;
  List<AreaWithGoals> _vision = [];
  List<InventoryItem> _expiring = [];
  List<PlanEntry> _training = [];
  List<PlannedMeal> _meals = [];
  JournalEntry? _journal;
  int _dueCards = 0;

  /// Lässt den Kassenzettel-Hinweis nach jedem Laden neu nachsehen.
  int _revision = 0;
  List<ContactNote> _peopleNotes = [];
  List<ContactNote> _followUps = [];
  List<Contact> _birthdays = [];

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _load();
  }

  /// Lädt alles; ein Fehler (z. B. beschädigte Daten) zeigt eine Meldung statt eines ewigen Ladekreises.
  Future<void> _openAppointment(Appointment a) async {
    final repo = context.read<AppointmentRepository>();
    final result = await Navigator.push<Object?>(
        context, MaterialPageRoute(builder: (_) => AddUpdateAppointmentScreen(userid: _user.uid, appointment: a)));
    if (!mounted) return;
    if (result == kDeletedResult) {
      await deleteWithUndo(context,
          label: a.title, delete: () => repo.deleteAppointment(a.id!), restore: () => repo.restoreAppointment(a), onChanged: _load);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      await _loadData();
    } catch (e, s) {
      debugPrint('Laden fehlgeschlagen: $e $s');
      if (!mounted) return;
      setState(() => _isLoading = false);
      showAppSnack(context, 'Daten konnten nicht vollständig geladen werden: ${errorText(e)}', error: true);
    }
  }

  Future<void> _loadData() async {
    final habitRepo = context.read<HabitRepository>();
    final transactions = context.read<TransactionRepository>();
    final prediction = context.read<PredictionService>();
    final visionRepo = context.read<VisionRepository>();
    final inventoryRepo = context.read<InventoryRepository>();
    final workoutRepo = context.read<WorkoutRepository>();
    final mealRepo = context.read<MealPlanRepository>();
    final journalRepo = context.read<JournalRepository>();
    final learningRepo = context.read<LearningRepository>();
    final contactRepo = context.read<ContactRepository>();
    final calendarSync = context.read<CalendarSync>();
    final uid = widget.user.uid;
    final now = DateTime.now();
    final today = _today;

    final results = await Future.wait([
      context.read<TodoRepository>().getAllTodos(uid),
      context.read<AppointmentRepository>().getAllAppointments(uid),
      habitRepo.getAllHabits(uid),
      context.read<UserRepository>().getUser(uid),
    ]);

    // Heute fällige und alle unerledigten aus der Vergangenheit (überfällig)
    final todos = (results[0] as List<Todo>).where((t) {
      final d = t.dueDate;
      if (d == null) return false;
      final day = dateOnly(d);
      return day == today || (day.isBefore(today) && !t.isCompleted);
    }).toList()
      ..sort((a, b) {
        int rank(Todo t) => _isOverdue(t) ? 0 : (t.isCompleted ? 2 : 1);
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.dueDate!.compareTo(b.dueDate!); // älteste überfällige zuerst
      });

    final external = await calendarSync.events(uid, today, now.add(const Duration(days: 31)));
    final next = [
      for (final a in results[1] as List<Appointment>)
        if (a.endOf(a.nextOccurrence(now)).isAfter(now)) _NextUp.appointment(a, a.nextOccurrence(now)),
      for (final x in external)
        if (x.end.isAfter(now)) _NextUp.external(x),
    ]..sort((x, y) => x.at.compareTo(y.at));

    final habits = <_TodayHabit>[];
    for (final h in results[2] as List<Habit>) {
      if (!HabitActions.isScheduled(h.selectedDays, today)) continue;
      final streak = await habitRepo.calculateStreak(h.id!);
      final done = await habitRepo.isHabitCompletedOnDate(h.id!, today);
      habits.add(_TodayHabit(h, streak, done));
    }

    // Monatsbilanz (aktueller Monat, alle Konten, ohne Umbuchungen)
    final monthTransactions = await transactions.getTransactionsSince(uid, DateTime(now.year, now.month, 1));
    double inc = 0, exp = 0;
    for (final t in monthTransactions) {
      if (t.isTransfer || t.date.isAfter(now)) continue;
      if (t.transactionType == TransactionType.income) inc += t.amount;
      if (t.transactionType == TransactionType.expense) exp += t.amount;
    }
    final forecast = await prediction.calculateEndOfMonthForecast(uid, accountName: PredictionService.allAccounts);
    final vision = await visionRepo.getBoard(uid);
    final expiring = await inventoryRepo.getExpiring(uid);
    final training = await workoutRepo.getPlanForDay(uid, today);
    final meals = await mealRepo.getDay(uid, today);
    final journal = await journalRepo.getEntry(uid, today);
    final dueCards = await learningRepo.dueCount(uid);
    final people = await contactRepo.notesForDay(uid, today);
    final birthdays = await contactRepo.upcomingBirthdays(uid, now: now);

    if (!mounted) return;
    setState(() {
      _todayTodos = todos;
      _next = next.take(2).toList();
      _habits = habits;
      _user = results[3] as UserModel;
      _monthlyBalance = inc - exp;
      _forecast = forecast;
      _vision = vision;
      _expiring = expiring;
      _training = training;
      _meals = meals;
      _journal = journal;
      _dueCards = dueCards;
      _revision++;
      _peopleNotes = people.due;
      _followUps = people.followUps;
      _birthdays = birthdays;
      _isLoading = false;
    });
  }

  // ─── Aktionen ────────────────────────────────────────────────────────────

  Future<void> _toggleHabit(_TodayHabit h) async {
    final i = _habits.indexOf(h);
    setState(() => _habits[i] = _TodayHabit(h.habit, h.streak + (h.done ? -1 : 1), !h.done)); // optimistisch
    final updated = await HabitActions.toggle(
      habits: context.read<HabitRepository>(),
      users: context.read<UserRepository>(),
      userId: _user.uid,
      habitId: h.habit.id!,
      date: _today,
      currentlyCompleted: h.done,
    );
    if (updated != null && mounted) setState(() => _user = updated);
  }

  Future<void> _toggleTodo(Todo t) async {
    final repo = context.read<TodoRepository>();
    final updated = t.copyWith(isCompleted: !t.isCompleted);
    setState(() => _todayTodos = _todayTodos.map((x) => x.id == t.id ? updated : x).toList());
    await repo.setCompleted(t, updated.isCompleted);
  }

  bool _isOverdue(Todo t) => t.dueDate != null && dateOnly(t.dueDate!).isBefore(_today);

  /// Nur die heute fälligen – überfällige zählen nicht in den Tages-Score.
  Iterable<Todo> get _dueToday => _todayTodos.where((t) => !_isOverdue(t));

  String _overdueLabel(Todo t) {
    final days = daysBetween(t.dueDate!, _today);
    return 'Überfällig · seit ${days == 1 ? 'gestern' : '$days Tagen'}';
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Guten Morgen';
    if (h < 18) return 'Guten Tag';
    return 'Guten Abend';
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (_isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: c.accent)));
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.accent,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 8, 20, navClearance(context)),
            children: [
              _header(context),
              const SizedBox(height: 16),
              _scoreCard(context),
              const SizedBox(height: 24),
              // Reihenfolge nach täglicher Nutzung; Abschnitte ohne Inhalt bleiben weg
              _habitSection(context),
              const SizedBox(height: 24),
              if (_meals.isNotEmpty) ...[
                _mealSection(context),
                const SizedBox(height: 24),
              ],
              if (_training.isNotEmpty) ...[
                _trainingSection(context),
                const SizedBox(height: 24),
              ],
              _todoSection(context),
              const SizedBox(height: 24),
              if (_next.isNotEmpty) ...[
                _appointmentSection(context),
                const SizedBox(height: 24),
              ],
              if (_peopleNotes.isNotEmpty || _followUps.isNotEmpty || _birthdays.isNotEmpty) ...[
                _peopleSection(context),
                const SizedBox(height: 24),
              ],
              if (_dueCards > 0) ...[
                _learningSection(context),
                const SizedBox(height: 24),
              ],
              // Einkauf ohne Kassenzettel (unsichtbar, wenn alles belegt ist)
              MissingReceiptBanner(userid: _user.uid, revision: _revision, onChanged: _load, bottomSpacing: 24),
              if (_expiring.isNotEmpty) ...[
                _expiringSection(context),
                const SizedBox(height: 24),
              ],
              _journalSection(context),
              const SizedBox(height: 24),
              _visionSection(context),
              const SizedBox(height: 24),
              _financeSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final name = (_user.displayName?.trim().isNotEmpty ?? false) ? _user.displayName!.trim() : 'du';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('EEEE, d. MMMM', 'de_DE').format(DateTime.now()), style: t.bodySmall),
            const SizedBox(height: 4),
            Text('$_greeting,\n$name', style: t.displaySmall?.copyWith(height: 1.1)),
          ]),
        ),
        RoundIconButton(icon: Icons.flag_outlined, tooltip: 'Vision Board', onTap: _openVisionBoard),
        const SizedBox(width: 8),
        RoundIconButton(
          icon: Icons.search_rounded,
          tooltip: 'Suche',
          onTap: () => showSearch(context: context, delegate: GlobalSearchDelegate(userId: _user.uid, db: context.read<DatabaseService>())),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Profil',
          offset: const Offset(0, 52),
          onSelected: (v) async {
            if (v == 'profile') {
              final updated = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(user: _user)));
              if (!mounted) return;
              if (updated is UserModel) setState(() => _user = updated);
              _load(); // z. B. Handy-Kalender gerade eingeschaltet
            } else if (v == 'logout') {
              await Wrapper.signOut(context);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'profile', child: Text('Profil')),
            PopupMenuItem(value: 'logout', child: Text('Abmelden')),
          ],
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: c.onAccent, fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _scoreCard(BuildContext context) {
    final c = AppColors.of(context);
    final habitsDone = _habits.where((h) => h.done).length;
    final todosDone = _dueToday.where((t) => t.isCompleted).length;
    final total = _habits.length + _dueToday.length;
    final score = total == 0 ? 0.0 : (habitsDone + todosDone) / total;
    final xpInLevel = _user.xpIntoLevel;
    final xpForNext = _user.xpForNextLevel;

    Widget row(String label, String value) => Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: c.onScoreCardMuted, fontSize: 14))),
          Text(value, style: TextStyle(color: c.onScoreCard, fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
        ]);

    return AppCard(
      color: c.scoreCard,
      radius: AppTheme.radiusHero,
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        ScoreRing(
          progress: score,
          color: c.accent,
          track: c.scoreTrack,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${(score * 100).round()}',
                style: TextStyle(color: c.onScoreCard, fontSize: 30, fontWeight: FontWeight.w600, letterSpacing: -1)),
            Text('TAG %', style: TextStyle(color: c.onScoreCardMuted, fontSize: 11, fontFamily: 'monospace')),
          ]),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(children: [
            row('Habits', '$habitsDone/${_habits.length}'),
            const SizedBox(height: 12),
            row('To-Dos', '$todosDone/${_dueToday.length}'),
            const SizedBox(height: 12),
            Divider(height: 1, color: c.scoreTrack),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('Level ${_user.level}', style: TextStyle(color: c.onScoreCard, fontSize: 13, fontWeight: FontWeight.w600))),
              Text('$xpInLevel/$xpForNext XP', style: TextStyle(color: c.onScoreCardMuted, fontSize: 13)),
            ]),
            const SizedBox(height: 6),
            AppProgressBar(value: xpInLevel / xpForNext, color: AppColors.dark.streak, track: c.scoreTrack),
          ]),
        ),
      ]),
    );
  }

  Widget _habitSection(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Habits heute', trailing: _habits.isEmpty ? null : 'Tippen zum Abhaken'),
      if (_habits.isEmpty)
        AppCard(onTap: () => widget.onTabNav?.call(AppTab.plan, PlanSection.habits), child: Text('Heute sind keine Habits geplant.', style: t.bodySmall))
      else
        // Zwei Spalten, Höhe nach Inhalt – ein festes Seitenverhältnis lief bei großer Schrift über
        LayoutBuilder(builder: (context, box) {
          final width = (box.maxWidth - 10) / 2;
          return Wrap(spacing: 10, runSpacing: 10, children: _habits.map((h) {
            final col = Color(h.habit.colorValue);
            return SizedBox(
              width: width,
              child: AppCard(
                color: h.done ? col.withValues(alpha: 0.18) : c.card,
                padding: const EdgeInsets.all(14),
                onTap: () => _toggleHabit(h),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    IconTile(icon: IconData(h.habit.iconCodePoint, fontFamily: h.habit.iconFontFamily), color: col),
                    const Spacer(),
                    AppCheck(checked: h.done, round: true, size: 26, color: col),
                  ]),
                  const SizedBox(height: 12),
                  Text(h.habit.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.local_fire_department_rounded, size: 14, color: c.streak),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('${h.streak} ${h.streak == 1 ? 'Tag' : 'Tage'} in Folge',
                          style: t.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ]),
              ),
            );
          }).toList());
        }),
    ]);
  }

  Widget _appointmentSection(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Als Nächstes', trailing: 'Alle', onTrailingTap: () => widget.onTabNav?.call(AppTab.plan, PlanSection.appointments)),
      ..._next.asMap().entries.map((e) {
        final n = e.value;
        final a = n.appointment;
        final occ = n.at;
        final isToday = occ.year == now.year && occ.month == now.month && occ.day == now.day;
        final dayLabel = isToday ? 'HEUTE' : DateFormat('E', 'de_DE').format(occ).replaceAll('.', '').toUpperCase();
        final years = a?.yearsAt(occ);
        final highlight = e.key == 0;
        // Handy-Termine in der Farbe ihres Kalenders
        final accent = n.external == null ? c.event : Color(n.external!.color | 0xFF000000);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            onTap: () => a != null ? _openAppointment(a) : ExternalEventCard(event: n.external!).showDetails(context),
            child: Row(children: [
              Container(
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: highlight ? accent.withValues(alpha: 0.16) : c.cardAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  if (n.allDay) ...[
                    Icon(a?.repeatYearly ?? false ? Icons.cake_rounded : (a == null ? Icons.event_rounded : Icons.sticky_note_2_outlined),
                        size: 20, color: highlight ? accent : c.text),
                    Text(DateFormat('d.M.').format(occ), style: TextStyle(fontSize: 10, color: highlight ? accent : c.muted)),
                  ] else ...[
                    Text(DateFormat('HH:mm').format(occ),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: highlight ? accent : c.text)),
                    Text('bis ${DateFormat('HH:mm').format(n.end)}',
                        style: TextStyle(fontSize: 10, color: highlight ? accent : c.muted)),
                  ],
                  Text(dayLabel, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: highlight ? accent : c.muted)),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.title, style: t.titleMedium),
                  if (years != null) Text('$years Jahre', style: t.labelMedium?.copyWith(color: c.event)),
                  if (n.external != null)
                    Text(n.external!.calendarName, style: t.labelMedium?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (a?.description?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 3),
                    Text(a!.description!, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: c.dim),
            ]),
          ),
        );
      }),
    ]);
  }

  Widget _todoSection(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final open = _todayTodos.where((x) => !x.isCompleted).length;
    final overdue = _todayTodos.where((x) => !x.isCompleted && _isOverdue(x)).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('To-Dos', trailing: overdue == 0 ? '$open offen' : '$open offen · $overdue überfällig', onTrailingTap: () => widget.onTabNav?.call(AppTab.plan, PlanSection.todos)),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: _todayTodos.isEmpty
            ? Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('Keine Aufgaben für heute.', style: t.bodySmall))
            : Column(
                children: _todayTodos.asMap().entries.map((e) {
                  final todo = e.value;
                  return InkWell(
                    // Antippen öffnet die Aufgabe, das Kästchen hakt ab – wie in der To-Do-Liste
                    onTap: () => openTodoEditor(context, userid: _user.uid, todo: todo, onChanged: _load),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        border: e.key == 0 ? null : Border(top: BorderSide(color: c.line.withValues(alpha: 0.5))),
                      ),
                      child: Row(children: [
                        Semantics(
                          checked: todo.isCompleted,
                          label: 'Erledigt',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _toggleTodo(todo),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Center(child: AppCheck(checked: todo.isCompleted, onTap: () => _toggleTodo(todo))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(todo.title,
                                style: t.bodyLarge?.copyWith(
                                  color: todo.isCompleted ? c.dim : c.text,
                                  decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                                )),
                            if (!todo.isCompleted && _isOverdue(todo))
                              Row(children: [
                                Icon(Icons.schedule_rounded, size: 13, color: c.negative),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(_overdueLabel(todo),
                                      style: t.labelMedium?.copyWith(color: c.negative, fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            if (todo.description?.isNotEmpty ?? false)
                              Text(todo.description!, style: t.labelMedium?.copyWith(color: c.dim)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                }).toList(),
              ),
      ),
    ]);
  }

  Widget _trainingSection(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    void open() => widget.onTabNav?.call(AppTab.training);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Training heute', trailing: 'Plan', onTrailingTap: open),
      for (final e in _training)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            onTap: open,
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              IconTile(
                icon: e.status == PlanStatus.done ? Icons.check_rounded : Icons.fitness_center_rounded,
                color: e.status == PlanStatus.done ? c.positive : c.accentText,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.workout.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    switch (e.status) {
                      PlanStatus.done => 'Erledigt',
                      PlanStatus.skipped => 'Übersprungen',
                      PlanStatus.planned => e.workout.exercises.map((w) => w.exercise.name).join(', '),
                    },
                    style: t.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
    ]);
  }

  /// Was es heute zu essen gibt; das nächste offene Gericht ist hervorgehoben.
  Widget _mealSection(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    final now = DateTime.now();
    final next = _meals.where((p) => !p.eaten && p.at.add(const Duration(hours: 1)).isAfter(now)).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Essen heute',
          trailing: 'Essensplan', onTrailingTap: () => widget.onTabNav?.call(AppTab.food, FoodSection.mealPlan)),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(children: [
          for (final p in _meals)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              leading: Icon(p.eaten ? Icons.check_circle_rounded : mealIcon(p.meal),
                  color: p.eaten ? c.positive : (p == next ? c.accentText : c.muted)),
              title: Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyLarge?.copyWith(
                    fontWeight: p == next ? FontWeight.w700 : null,
                    decoration: p.eaten ? TextDecoration.lineThrough : null,
                  )),
              subtitle: Text('${p.meal.label}${p == next ? ' · als Nächstes' : ''}', style: t.labelMedium),
              trailing: Text(formatMinutes(p.minutes), style: t.labelMedium),
              onTap: () => _toggleMeal(p),
              onLongPress: () => _openMeal(p),
            ),
        ]),
      ),
    ]);
  }

  /// Antippen: Gericht oder Lebensmittel als gegessen eintragen – bzw. zurücknehmen, wenn es schon
  /// eingetragen ist. Die Snackbar bietet „Rückgängig“.
  Future<void> _toggleMeal(PlannedMeal p) async {
    final messenger = ScaffoldMessenger.of(context);
    final updated = await runGuarded(context, () => _setEaten(p, !p.eaten));
    if (updated == null || !mounted) return;
    _replaceMeal(updated);
    _load();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(updated.eaten ? '„${p.name}“ unter ${p.meal.label} eingetragen' : '„${p.name}“ aus dem Ernährungsprotokoll entfernt'),
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: () async {
          if (!mounted) return;
          final back = await _setEaten(updated, !updated.eaten);
          if (!mounted) return;
          if (back != null) _replaceMeal(back);
          _load();
        },
      ),
    ));
  }

  /// Zeigt den neuen Stand sofort – das Neuladen von Heute dauert einen Moment.
  void _replaceMeal(PlannedMeal updated) =>
      setState(() => _meals = [for (final m in _meals) m.id == updated.id ? updated : m]);

  /// Trägt [p] ein ([eat]) oder nimmt es zurück. Liefert `null`, wenn Rezept bzw. Lebensmittel fehlen.
  Future<PlannedMeal?> _setEaten(PlannedMeal p, bool eat) async {
    final repo = context.read<MealPlanRepository>();
    final nutrition = context.read<NutritionRepository>();
    final messenger = ScaffoldMessenger.of(context);
    if (!eat) return repo.unmarkEaten(p);
    if (p.foodId != null) {
      final food = await nutrition.getFood(p.foodId!);
      if (food == null) {
        messenger.showSnackBar(SnackBar(content: Text('Das Lebensmittel „${p.name}“ gibt es nicht mehr.')));
        return null;
      }
      return repo.markFoodEaten(p, food);
    }
    final recipe = await repo.recipeFor(p);
    if (recipe == null) {
      messenger.showSnackBar(SnackBar(content: Text('Das Rezept zu „${p.name}“ wurde gelöscht.')));
      return null;
    }
    return repo.markEaten(p, recipe);
  }

  /// Lange drücken: Rezept öffnen; ein eingeplantes Lebensmittel zeigt der Essensplan.
  Future<void> _openMeal(PlannedMeal p) async {
    if (p.foodId != null) {
      widget.onTabNav?.call(AppTab.food, FoodSection.mealPlan);
      return;
    }
    await openPlannedMeal(context, _user.uid, p);
    _load();
  }

  Widget _expiringSection(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    void open() => widget.onTabNav?.call(AppTab.food, FoodSection.pantry);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Läuft bald ab', trailing: 'Vorrat', onTrailingTap: open),
      AppCard(
        onTap: open,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(children: [
          for (final (i, item) in _expiring.take(4).indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.line.withValues(alpha: 0.5)))),
              child: Row(children: [
                InventoryThumb(item: item, size: 34),
                const SizedBox(width: 12),
                Expanded(child: Text(item.name, style: t.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ExpiryBadge(item),
              ]),
            ),
          if (_expiring.length > 4)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('+ ${_expiring.length - 4} weitere', style: t.labelMedium),
            ),
        ]),
      ),
    ]);
  }

  Future<void> _openVisionBoard() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => VisionBoardScreen(user: _user)));
    _load();
  }

  Widget _journalSection(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle('Journal', trailing: 'Alle', onTrailingTap: () => widget.onTabNav?.call(AppTab.plan, PlanSection.journal)),
        JournalTodayCard(
          today: _journal,
          onTap: () => openJournalEditor(context, userid: _user.uid, entry: _journal, date: _today, onChanged: _load),
        ),
      ]);

  Future<void> _toggleNote(ContactNote n) async {
    final updated = n.copyWith(done: !n.done);
    setState(() => _peopleNotes = [for (final x in _peopleNotes) x.id == n.id ? updated : x]); // optimistisch
    await runGuarded(context, () => context.read<ContactRepository>().setNoteDone(n, updated.done));
  }

  Future<void> _openMore(MoreSection section) async {
    await openMoreSection(context, _user, section);
    _load();
  }

  Future<void> _openContact(int id) async {
    await openContact(context, id);
    _load();
  }

  /// Menschen: heutige Notizen zu Kontakten (abhakbar), Nachfragen vom Vortag, Geburtstage der Woche.
  Widget _peopleSection(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final rows = <Widget>[];
    Widget row({required Widget lead, required String title, String? subtitle, required VoidCallback onTap, bool done = false}) => InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(border: rows.isEmpty ? null : Border(top: BorderSide(color: c.line.withValues(alpha: 0.5)))),
            child: Row(children: [
              SizedBox(width: 40, height: 40, child: Center(child: lead)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: t.bodyLarge?.copyWith(color: done ? c.dim : c.text, decoration: done ? TextDecoration.lineThrough : null)),
                  if (subtitle != null) Text(subtitle, style: t.labelMedium?.copyWith(color: c.dim)),
                ]),
              ),
            ]),
          ),
        );
    for (final n in _peopleNotes) {
      rows.add(row(
        lead: Semantics(
          checked: n.done,
          label: 'Erledigt',
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _toggleNote(n), child: AppCheck(checked: n.done, onTap: () => _toggleNote(n))),
        ),
        title: '${n.contactName}: ${n.text}',
        done: n.done,
        onTap: () => _openContact(n.contactId),
      ));
    }
    for (final n in _followUps) {
      rows.add(row(
        lead: Icon(Icons.forum_outlined, color: c.accentText),
        title: 'Bei ${n.contactName} nachfragen',
        subtitle: '${n.text} – wie war’s?',
        onTap: () => _openContact(n.contactId),
      ));
    }
    final now = DateTime.now();
    for (final b in _birthdays) {
      final days = b.daysUntilBirthday(now)!;
      final age = b.ageAtNextBirthday(now)!;
      rows.add(row(
        lead: Icon(Icons.cake_rounded, color: c.streak),
        title: days == 0 ? '${b.name} hat heute Geburtstag' : '${b.name} hat ${relativeDays(days)} Geburtstag',
        subtitle: [if (age > 0) 'wird $age', DateFormat('EEEE, d. MMMM', 'de_DE').format(b.nextBirthday(now)!)].join(' · '),
        onTap: () => _openContact(b.id!),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Menschen', trailing: 'Kontakte', onTrailingTap: () => _openMore(MoreSection.contacts)),
      AppCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Column(children: rows)),
    ]);
  }

  Widget _learningSection(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    Future<void> study() async {
      await openStudy(context, userid: _user.uid);
      _load();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Lernen', trailing: 'Stapel', onTrailingTap: () => _openMore(MoreSection.learning)),
      AppCard(
        onTap: study,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          IconTile(icon: Icons.school_rounded, color: c.accentText),
          const SizedBox(width: 12),
          Expanded(child: Text('$_dueCards ${_dueCards == 1 ? 'Karte' : 'Karten'} fällig', style: t.titleMedium)),
          FilledButton(onPressed: study, child: const Text('Lernen')),
        ]),
      ),
    ]);
  }

  Widget _visionSection(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final total = _vision.fold<int>(0, (s, a) => s + a.goals.length);
    final achieved = _vision.fold<int>(0, (s, a) => s + a.achieved);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Vision Board', trailing: 'Öffnen', onTrailingTap: _openVisionBoard),
      AppCard(
        onTap: _openVisionBoard,
        child: total == 0
            ? Text('Lege deine langfristigen Ziele an und plane sie Schritt für Schritt.', style: t.bodySmall)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('$achieved von $total Zielen erreicht', style: t.titleMedium)),
                  Text('${_vision.length} Bereiche', style: t.labelMedium),
                ]),
                const SizedBox(height: 10),
                AppProgressBar(value: achieved / total, color: c.accent),
              ]),
      ),
    ]);
  }

  Widget _financeSection(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final forecast = _forecast?.totalForecast ?? 0;
    final lastDay = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

    Widget tile(String label, String value, Color color) => Expanded(
          child: AppCard(
            onTap: () => widget.onTabNav?.call(AppTab.money),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: t.labelMedium),
              const SizedBox(height: 6),
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: color)),
            ]),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Finanzen im ${DateFormat('MMMM', 'de_DE').format(DateTime.now())}'),
      Row(children: [
        tile('Bilanz Monat', formatEuro(_monthlyBalance, sign: true), _monthlyBalance >= 0 ? c.positive : c.negative),
        const SizedBox(width: 10),
        tile('Prognose ${DateFormat('dd.MM.').format(lastDay)}', formatEuro(forecast, sign: true), c.text),
      ]),
    ]);
  }
}

/// Ein Eintrag in „Als Nächstes“: LifeHub-Termin (mit dem nächsten Vorkommen) oder Handy-Termin.
class _NextUp {
  final DateTime at;
  final DateTime end;
  final String title;
  final bool allDay;
  final Appointment? appointment;
  final ExternalEvent? external;

  _NextUp.appointment(Appointment a, DateTime occ)
      : at = occ,
        end = a.endOf(occ),
        title = a.title,
        allDay = a.allDay,
        appointment = a,
        external = null;

  _NextUp.external(ExternalEvent x)
      : at = x.start,
        end = x.end,
        title = x.title.isEmpty ? '(ohne Titel)' : x.title,
        allDay = x.allDay,
        appointment = null,
        external = x;
}
