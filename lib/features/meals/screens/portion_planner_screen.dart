import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/models/dates.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/meals/models/meal_plan.dart';
import 'package:frontend/features/meals/repositories/meal_plan_repository.dart';
import 'package:frontend/features/meals/services/pantry_check.dart';
import 'package:frontend/features/meals/widgets/meal_widgets.dart';

/// Kochen planen: Menge (Portionen), Kochtag mit Uhrzeit (Termin im Kalender), Portionen auf
/// Mahlzeiten verteilen (übrige dürfen bleiben) und im zweiten Schritt die Zutaten gegen den Vorrat
/// prüfen – vorhandene reservieren, den Rest auf die Einkaufsliste. Mit [batch] wird ein bestehender
/// Koch-Block geändert. Liefert `true` nach dem Speichern.
class PortionPlannerScreen extends StatefulWidget {
  final int userid;
  final Recipe recipe;
  final DateTime initialDate;

  /// Diese Mahlzeit bekommt beim Öffnen schon eine Portion (z. B. „+“ beim Mittagessen).
  final Meal? presetMeal;
  final MealBatch? batch;

  const PortionPlannerScreen({
    super.key,
    required this.userid,
    required this.recipe,
    required this.initialDate,
    this.presetMeal,
    this.batch,
  });

  @override
  State<PortionPlannerScreen> createState() => _PortionPlannerScreenState();
}

class _PortionPlannerScreenState extends State<PortionPlannerScreen> {
  late final MealPlanRepository _repo = context.read<MealPlanRepository>();
  late DateTime _cookDate = _dateOnly(widget.batch?.cookDate ?? widget.initialDate);
  late double _factor = widget.batch?.factor ?? 1;

  /// Verteilung: (Tag, Mahlzeit) → Portionen.
  final Map<(DateTime, Meal), double> _slots = {};

  /// Schon gegessene Portionen (nur beim Umverteilen) – bleiben, wie sie sind.
  double _eaten = 0;
  bool _saving = false;

  /// Koch-Termin im Kalender.
  late TimeOfDay _time = TimeOfDay(hour: widget.batch?.cookHour ?? 17, minute: widget.batch?.cookMinute ?? 0);
  late int _duration = widget.batch?.durationMin ?? 60;

  /// Schritt 2: Zutaten gegen den Vorrat.
  bool _ingredientsStep = false;

  /// Vorrat reservieren bzw. Fehlendes einkaufen – beides abschaltbar, am Block gemerkt.
  late bool _pantry = widget.batch?.usePantry ?? true;
  late bool _shop = widget.batch?.shop ?? true;

  /// Beim Bearbeiten ohne geänderte Menge: speichern, ohne Vorrat und Einkauf neu zu planen.
  bool get _canQuickSave => widget.batch != null && widget.batch!.ingredientsPlanned && _factor == widget.batch!.factor;
  List<PantryCheck>? _checks;
  List<bool> _use = const [];

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  double get _total => widget.recipe.servings * _factor;
  double get _distributed => _eaten + _slots.values.fold(0.0, (s, v) => s + v);
  double get _left => _total - _distributed;

  /// Tage ab dem Kochtag, auf die verteilt werden kann.
  List<DateTime> get _days => [for (var i = 0; i < 7; i++) addDays(_cookDate, i)];

  @override
  void initState() {
    super.initState();
    // Eine noch sichtbare Meldung würde den Einplanen-Button unten verdecken
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    });
    final batch = widget.batch;
    if (batch != null) {
      _repo.getBatchMeals(batch.id!).then((meals) {
        if (!mounted) return;
        setState(() {
          for (final m in meals) {
            if (m.eaten) {
              _eaten += m.servings;
            } else {
              _slots[(m.date, m.meal)] = (_slots[(m.date, m.meal)] ?? 0) + m.servings;
            }
          }
        });
      });
    } else if (widget.presetMeal != null) {
      _slots[(_cookDate, widget.presetMeal!)] = 1;
    }
  }

  void _change(DateTime day, Meal meal, double delta) {
    final key = (day, meal);
    if (delta > 0) {
      // Bei krummen Mengen (z. B. 4,5 Portionen) bleibt am Ende eine halbe Portion
      delta = _left < 1 ? _left : 1;
      if (delta <= 0.001) return;
    }
    final next = (_slots[key] ?? 0) + delta;
    setState(() {
      if (next <= 0) {
        _slots.remove(key);
      } else {
        _slots[key] = next;
      }
    });
  }

  /// Mittag- und Abendessen ab dem Kochtag der Reihe nach mit je einer Portion füllen.
  void _autoFill() {
    setState(() {
      _slots.clear();
      var left = _total - _eaten;
      for (final day in _days) {
        for (final meal in const [Meal.lunch, Meal.dinner]) {
          if (left <= 0) break;
          final portion = left >= 1 ? 1.0 : left;
          _slots[(day, meal)] = portion;
          left -= portion;
        }
      }
    });
  }

  Future<void> _pickCookDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _cookDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      helpText: 'Kochtag',
    );
    if (picked == null) return;
    final shift = daysBetween(_cookDate, picked);
    setState(() {
      // Die Verteilung wandert mit dem Kochtag mit
      final moved = {for (final e in _slots.entries) (addDays(e.key.$1, shift), e.key.$2): e.value};
      _slots
        ..clear()
        ..addAll(moved);
      _cookDate = _dateOnly(picked);
    });
  }

  void _setFactor(double f) {
    setState(() {
      _factor = f;
      // Zu viel Verteiltes zurücknehmen – von hinten
      final keys = _slots.keys.toList()..sort((a, b) => b.$1.compareTo(a.$1));
      for (final k in keys) {
        if (_left >= 0) break;
        final over = -_left;
        final v = _slots[k]!;
        if (v <= over) {
          _slots.remove(k);
        } else {
          _slots[k] = v - over;
        }
      }
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time, helpText: 'Kochen um');
    if (picked != null) setState(() => _time = picked);
  }

  /// Gesamtportionen um ±1 ändern (mindestens eine).
  void _stepPortions(int delta) {
    final next = (_total + delta).roundToDouble();
    if (next < 1) return;
    _setFactor(next / widget.recipe.servings);
  }

  /// Weiter zu den Zutaten: Vorrat prüfen (ohne das, was andere Koch-Blöcke reserviert haben).
  Future<void> _toIngredients() async {
    final checks = await runGuarded(context, () => _repo.checkPantry(widget.userid, widget.recipe, _factor, batchId: widget.batch?.id));
    if (checks == null || !mounted) return;
    final own = widget.batch == null ? const <String>{} : {for (final r in await _repo.reservationsOf(widget.batch!.id!)) r.ingredient};
    if (!mounted) return;
    setState(() {
      _checks = checks;
      // Vorhandenes standardmäßig aus dem Vorrat; beim Ändern bleibt die bisherige Wahl
      _use = [for (final c in checks) c.inPantry && (widget.batch == null || !widget.batch!.ingredientsPlanned || own.contains(c.ingredient.name))];
      _ingredientsStep = true;
    });
  }

  Future<void> _save({bool ingredients = true}) async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final slots = [for (final e in _slots.entries) PortionSlot(e.key.$1, e.key.$2, e.value)];
    final result = await runGuarded(context, () async {
      final int id;
      if (widget.batch == null) {
        id = await _repo.planBatch(
          uid: widget.userid,
          recipe: widget.recipe,
          cookDate: _cookDate,
          slots: slots,
          factor: _factor,
          cookHour: _time.hour,
          cookMinute: _time.minute,
          durationMin: _duration,
        );
      } else {
        id = widget.batch!.id!;
        await _repo.replanBatch(widget.batch!, widget.recipe,
            cookDate: _cookDate, slots: slots, factor: _factor, cookHour: _time.hour, cookMinute: _time.minute, durationMin: _duration);
      }
      if (!ingredients) return (0, 0);
      return _repo.saveIngredientPlan(widget.userid, id, _checks ?? const [], _use, pantry: _pantry, shop: _shop);
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (result == null) return;
    final (reserved, shopping) = result;
    final left = _left;
    messenger.showSnackBar(SnackBar(
      content: Text([
        'Eingeplant – Termin um ${_timeLabel(_time)}',
        if (!ingredients) 'Vorrat und Einkauf unverändert',
        if (reserved > 0) '$reserved aus dem Vorrat',
        if (shopping > 0) '$shopping auf der Einkaufsliste',
        if (left > 0.01) '${_num(left)} ${left == 1 ? 'Portion' : 'Portionen'} noch frei',
      ].join(' · ')),
    ));
    navigator.pop(true);
  }

  static String _timeLabel(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString().replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final left = _left;
    final done = left.abs() < 0.01;
    final over = left < -0.01;
    if (_ingredientsStep) return _ingredientsPage(context);
    return Scaffold(
      appBar: ModernAppBar(title: widget.batch == null ? 'Kochen planen' : 'Koch-Block ändern'),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
              Text(widget.recipe.name, style: t.titleLarge),
              Text('Ein Rezept ergibt ${widget.recipe.servings} Portionen. Verteil sie auf die Tage – was übrig bleibt, '
                  'kannst du später einplanen.',
                  style: t.bodySmall?.copyWith(color: c.muted)),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                child: Row(children: [
                  Icon(Icons.restaurant_rounded, color: c.accentText, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Portionen', style: t.titleSmall)),
                  IconButton(
                    tooltip: 'Eine Portion weniger',
                    onPressed: _total > 1 ? () => _stepPortions(-1) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(_num(_total), style: t.titleMedium),
                  IconButton(tooltip: 'Eine Portion mehr', onPressed: () => _stepPortions(1), icon: const Icon(Icons.add_circle_outline)),
                ]),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final f in const [1.0, 1.5, 2.0, 3.0])
                  AppChip(
                    label: '×${_num(f)} = ${_num(widget.recipe.servings * f)} Portionen',
                    selected: _factor == f,
                    onTap: () => _setFactor(f),
                  ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickCookDate,
                    icon: const Icon(Icons.soup_kitchen_outlined),
                    label: Text('Kochen am ${DateFormat('EEE, d. MMM', 'de_DE').format(_cookDate)}', overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(_timeLabel(_time)),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Dauer', style: t.labelMedium?.copyWith(color: c.muted)),
                for (final m in const [30, 60, 90, 120])
                  AppChip(label: m < 60 ? '$m Min' : '${_num(m / 60)} Std', selected: _duration == m, onTap: () => setState(() => _duration = m)),
              ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _autoFill,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Automatisch auf Mittag- und Abendessen verteilen'),
                ),
              ),
              if (_eaten > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_eaten == 1 ? '1 Portion ist schon gegessen.' : '${_num(_eaten)} Portionen sind schon gegessen.',
                      style: t.bodySmall),
                ),
              for (final day in _days) _dayCard(context, day),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(color: c.card, border: Border(top: BorderSide(color: c.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                done
                    ? 'Alle ${_num(_total)} Portionen verteilt'
                    : left > 0
                        ? 'Noch ${_num(left)} ${left == 1 ? 'Portion' : 'Portionen'} frei – kannst du auch später verteilen'
                        : '${_num(-left)} Portionen zu viel',
                textAlign: TextAlign.center,
                style: t.titleSmall?.copyWith(color: done ? c.positive : (over ? c.negative : c.streak)),
              ),
              const SizedBox(height: 8),
              if (_canQuickSave)
                Row(children: [
                  OutlinedButton(onPressed: !over && !_saving ? () => _save(ingredients: false) : null, child: const Text('Speichern')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(onPressed: !over && !_saving ? _toIngredients : null, child: const Text('Weiter: Zutaten prüfen')),
                  ),
                ])
              else
                ElevatedButton(onPressed: !over && !_saving ? _toIngredients : null, child: const Text('Weiter: Zutaten prüfen')),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _dayCard(BuildContext context, DateTime day) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final isCookDay = day == _cookDate;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(DateFormat('EEEE, d.M.', 'de_DE').format(day), style: t.titleSmall)),
            if (isCookDay) Text('Kochtag', style: t.labelMedium?.copyWith(color: c.accentText)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final meal in plannedMeals) _slotButton(context, day, meal),
          ]),
        ]),
      ),
    );
  }

  Widget _slotButton(BuildContext context, DateTime day, Meal meal) {
    final c = AppColors.of(context);
    final count = _slots[(day, meal)] ?? 0;
    final active = count > 0;
    return Material(
      color: active ? c.accent : c.cardAlt,
      borderRadius: BorderRadius.circular(20),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _change(day, meal, 1),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(mealIcon(meal), size: 16, color: active ? c.onAccent : c.muted),
              const SizedBox(width: 4),
              Text(
                active ? '${meal.label} ×${_num(count)}' : meal.label,
                style: TextStyle(fontSize: 12, color: active ? c.onAccent : c.text),
              ),
            ]),
          ),
        ),
        if (active)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _change(day, meal, -1),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
              child: Icon(Icons.remove_circle_outline, size: 16, color: c.onAccent, semanticLabel: '${meal.label} eine Portion weniger'),
            ),
          ),
      ]),
    );
  }

  // ─── Schritt 2: Zutaten ───────────────────────────────────────────────

  Widget _ingredientsPage(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final checks = _checks ?? const <PantryCheck>[];
    final reserved = [for (var i = 0; i < checks.length; i++) if (_pantry && _use[i] && checks[i].inPantry) i];
    final buying = checks.length - reserved.length + reserved.where((i) => checks[i].status == PantryStatus.partial).length;
    return Scaffold(
      appBar: ModernAppBar(title: 'Zutaten'),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
              Text('${widget.recipe.name} · ${_num(_total)} Portionen', style: t.titleMedium),
              Text('Was im Vorrat ist, wird für dieses Kochen zurückgelegt. Alles andere kommt auf die Einkaufsliste.',
                  style: t.bodySmall?.copyWith(color: c.muted)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vorrat nutzen'),
                subtitle: const Text('Vorhandenes für dieses Kochen zurücklegen'),
                value: _pantry,
                onChanged: (v) => setState(() => _pantry = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fehlendes auf die Einkaufsliste'),
                subtitle: const Text('Aus, wenn du alles schon hast oder selbst einkaufst'),
                value: _shop,
                onChanged: (v) => setState(() => _shop = v),
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < checks.length; i++) _ingredientRow(context, i),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(color: c.card, border: Border(top: BorderSide(color: c.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                [
                  '${reserved.length} aus dem Vorrat',
                  _shop ? '$buying auf die Einkaufsliste' : 'nichts auf die Einkaufsliste',
                ].join(' · '),
                textAlign: TextAlign.center,
                style: t.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton(onPressed: _saving ? null : () => setState(() => _ingredientsStep = false), child: const Text('Zurück')),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(onPressed: _saving ? null : _save, child: const Text('Einplanen'))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _ingredientRow(BuildContext context, int i) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final check = _checks![i];
    final amount = check.ingredient.amountFor(_factor);
    String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.', ',');
    // Freie Menge in der Einheit des Rezepts zeigen („250 g“ statt „0,25 kg“)
    String free() {
      final (v, u) = normalizeAmount(check.available ?? 0, check.item?.unit);
      return u == null ? fmt(v) : '${fmt(v)} $u';
    }
    final (label, color) = switch (check.status) {
      PantryStatus.missing => (check.item == null ? 'nicht im Vorrat' : 'schon für anderes Kochen reserviert', c.negative),
      PantryStatus.partial => ('nur ${free()} da – Rest wird eingekauft', c.streak),
      PantryStatus.enough => ('im Vorrat: ${check.item!.name}', c.positive),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text([if (amount.isNotEmpty) amount, check.ingredient.name].join(' '), style: t.titleSmall),
              const SizedBox(height: 2),
              Text(label, style: t.labelMedium?.copyWith(color: color)),
            ]),
          ),
          if (check.inPantry)
            Column(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: _use[i],
                onChanged: (v) => setState(() => _use = [..._use]..[i] = v),
              ),
              Text(_use[i] ? 'Vorrat' : 'Einkaufen', style: t.labelSmall?.copyWith(color: c.muted)),
            ])
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.shopping_cart_outlined, color: c.muted, semanticLabel: 'Kommt auf die Einkaufsliste'),
            ),
        ]),
      ),
    );
  }
}
