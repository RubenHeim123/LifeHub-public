import 'package:flutter/material.dart';

import 'package:frontend/app/app_tabs.dart';
import 'package:frontend/app/tab_style.dart';
import 'package:frontend/core/ui/hub_tabs.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/calendar/screens/calendar_screen.dart';
import 'package:frontend/features/habits/screens/habit_tracker_screen.dart';
import 'package:frontend/features/journal/screens/journal_screen.dart';
import 'package:frontend/features/todos/screens/todo_list_screen.dart';

/// Tab „Planen“: To-Dos, Habits, Termine und Journal.
class PlanningHubScreen extends StatelessWidget {
  final UserModel user;
  final PlanSection initialSection;
  final ValueChanged<PlanSection>? onSectionChanged;
  const PlanningHubScreen({super.key, required this.user, this.initialSection = PlanSection.todos, this.onSectionChanged});

  @override
  Widget build(BuildContext context) {
    return HubTabs(
      title: AppTab.plan.style.label,
      icon: AppTab.plan.style.activeIcon,
      color: AppTab.plan.style.toneOf(context),
      initialIndex: initialSection.index,
      onChanged: (i) => onSectionChanged?.call(PlanSection.values[i]),
      tabs: [
        for (final s in PlanSection.values)
          switch (s) {
            PlanSection.todos => HubTab('To-Dos', (_) => TodoListScreen(user: user)),
            PlanSection.habits => HubTab('Habits', (_) => HabitTrackerScreen(user: user)),
            PlanSection.appointments => HubTab('Termine', (_) => CalendarScreen(user: user)),
            PlanSection.journal => HubTab('Journal', (_) => JournalScreen(user: user)),
          },
      ],
    );
  }
}
