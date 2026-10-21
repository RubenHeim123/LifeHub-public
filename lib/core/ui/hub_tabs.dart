import 'package:flutter/material.dart';

import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';

/// Ein Bereich in [HubTabs].
class HubTab {
  final String label;
  final WidgetBuilder builder;
  const HubTab(this.label, this.builder);
}

/// Bereichs-Umschalter für Tabs mit mehreren Unterseiten (Planen, Essen):
/// Titel und Chips oben, darunter die gewählte Seite. Die Seiten bringen ihren eigenen
/// Scaffold mit; der obere Rand ist hier schon berücksichtigt.
class HubTabs extends StatefulWidget {
  final String? title;
  final IconData? icon;
  final Color? color;
  final List<HubTab> tabs;
  final int initialIndex;

  /// Gewählter Bereich – die Shell merkt ihn sich für den nächsten Besuch des Tabs.
  final ValueChanged<int>? onChanged;
  const HubTabs({super.key, this.title, this.icon, this.color, required this.tabs, this.initialIndex = 0, this.onChanged});

  @override
  State<HubTabs> createState() => _HubTabsState();
}

class _HubTabsState extends State<HubTabs> {
  late int _index = widget.initialIndex;
  late final _chipKeys = [for (final _ in widget.tabs) GlobalKey()];

  @override
  void initState() {
    super.initState();
    // Weiter rechts liegende Bereiche (z. B. Journal, angesprungen von Heute) sichtbar machen
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected(animate: false));
  }

  void _select(int i) {
    setState(() => _index = i);
    widget.onChanged?.call(i);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  void _revealSelected({bool animate = true}) {
    final chip = _chipKeys[_index].currentContext;
    if (!mounted || chip == null) return;
    Scrollable.ensureVisible(
      chip,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      body: Column(children: [
        SafeArea(
          bottom: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.title != null) TabTitle(widget.title!, icon: widget.icon, color: widget.color),
            SizedBox(
              height: 48,
              // Alle Chips gebaut (keine ListView), damit der aktive auch rechts außerhalb gefunden wird
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                child: Row(children: [
                  for (var i = 0; i < widget.tabs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    AppChip(
                      key: _chipKeys[i],
                      label: widget.tabs[i].label,
                      selected: i == _index,
                      onTap: () => _select(i),
                    ),
                  ],
                ]),
              ),
            ),
          ]),
        ),
        Divider(height: 1, color: c.line),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: KeyedSubtree(key: ValueKey(_index), child: widget.tabs[_index].builder(context)),
          ),
        ),
      ]),
    );
  }
}

/// Titel oben auf einer Tab-Seite – gleich auf allen Tabs.
class TabTitle extends StatelessWidget {
  final String title;
  final List<Widget> actions;

  /// Icon in der Farbe des Tabs (wie die aktive Pille in der Leiste).
  final IconData? icon;
  final Color? color;
  const TabTitle(this.title, {super.key, this.actions = const [], this.icon, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
        child: SizedBox(
          height: 40,
          child: Row(children: [
            if (icon != null) ...[
              IconTile(icon: icon!, color: color ?? AppColors.of(context).accentText, size: 32, iconSize: 18),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            ...actions,
          ]),
        ),
      );
}

/// Tab mit nur einer Seite (Training, Mehr): Titel oben, darunter die Seite – wie bei [HubTabs].
class TabPage extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? color;
  final Widget child;
  const TabPage({super.key, required this.title, this.icon, this.color, required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          SafeArea(bottom: false, child: TabTitle(title, icon: icon, color: color)),
          Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child)),
        ]),
      );
}
