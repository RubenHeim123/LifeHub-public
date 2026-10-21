import 'package:flutter/material.dart';

import 'package:frontend/core/ui/theme.dart';

/// Zeigt an, zu welchem Ziel eine Aufgabe oder ein Termin gehört.
class GoalHint extends StatelessWidget {
  final String goal;
  const GoalHint(this.goal, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(children: [
        Icon(Icons.flag_rounded, size: 13, color: c.accentText),
        const SizedBox(width: 4),
        Flexible(
          child: Text(goal, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.accentText)),
        ),
      ]),
    );
  }
}
