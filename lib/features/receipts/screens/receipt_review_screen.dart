import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/form_widgets.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/finance/models/transaction.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/lists/widgets/shopping_detail_sheet.dart';
import 'package:frontend/features/receipts/models/receipt.dart';
import 'package:frontend/features/receipts/services/receipt_analyzer.dart';
import 'package:frontend/features/receipts/services/receipt_import_service.dart';
import 'package:frontend/features/receipts/services/receipt_matcher.dart';
import 'package:frontend/features/receipts/services/receipt_parser.dart';
import 'package:frontend/features/receipts/services/receipt_scanner.dart';
import 'package:frontend/features/receipts/widgets/receipt_photo.dart';

/// Kassenzettel fotografieren (oder aus der Galerie wählen), erkennen lassen und zur Prüfung öffnen.
/// Mit [existing] gehört der Bon zu einer schon vorhandenen Buchung (sie wird ergänzt statt neu angelegt),
/// [day] ist der Einkaufstag als Vorgabe, falls auf dem Bon kein Datum erkannt wird.
Future<void> scanReceipt(BuildContext context,
    {required int userid, VoidCallback? onSaved, Transaction? existing, DateTime? day}) async {
  final scanner = context.read<ReceiptScanner>();
  final images = context.read<ReceiptImageStore>();
  final source = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Kassenzettel fotografieren'),
          onTap: () => Navigator.pop(ctx, false),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Foto aus der Galerie'),
          onTap: () => Navigator.pop(ctx, true),
        ),
      ]),
    ),
  );
  if (source == null || !context.mounted) return;
  final scan = await runGuarded(context, () => scanner.scan(fromGallery: source));
  if (scan == null || !context.mounted) return;
  if (scan.lines.isEmpty) {
    await images.delete(scan.imagePath);
    if (!context.mounted) return;
    showAppSnack(context, 'Auf dem Foto wurde kein Text erkannt – bitte gerade und gut beleuchtet fotografieren.', error: true);
    return;
  }
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => ReceiptReviewScreen(userid: userid, scan: scan, existing: existing, day: day)),
  );
  if (saved == true) {
    // Das alte Belegfoto der Buchung wird ersetzt – löschen, wenn es sonst niemand nutzt
    final old = existing?.imagePath;
    if (old != null && old != scan.imagePath && context.mounted) {
      final transactions = context.read<TransactionRepository>();
      if (!await transactions.isImageUsed(old)) await images.delete(old);
    }
    onSaved?.call();
  } else {
    await images.delete(scan.imagePath); // abgebrochen: das Foto gehört zu keiner Buchung
  }
}

/// Eine Position in der Prüfansicht – alles änderbar.
class _Line {
  final ReceiptItem item;
  bool include;
  Food? food;
  String unit; // 'g', 'ml' oder 'Stück'
  final TextEditingController name;
  final TextEditingController quantity;

  /// Vorschlag der Auswertung, ob die Position in den Vorrat gehört (gilt, solange sie nicht zum Einkauf passt).
  final bool suggested;

  /// Passender Vorratsartikel aus dem Einkauf vom selben Tag – dann wird verknüpft statt neu angelegt.
  InventoryItem? linked;

  /// Bei abweichender Menge: die Menge vom Bon in den Vorrat übernehmen.
  bool takeReceiptAmount = false;

  _Line(this.item, this.food, this.include)
      : suggested = include,
        unit = item.pantryAmount.$2 ?? 'Stück',
        name = TextEditingController(text: food?.name ?? item.displayName),
        quantity = TextEditingController(text: _fmt(item.pantryAmount.$1));

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString().replaceAll('.', ',');

  void dispose() {
    name.dispose();
    quantity.dispose();
  }
}

/// Prüfansicht: erkannte Buchung (Händler, Betrag, Datum, Konto, Kategorie mit Vorschlägen) und die
/// Positionen für den Vorrat (mit Menge). Gespeichert wird erst nach „Bestätigen und speichern“.
class ReceiptReviewScreen extends StatefulWidget {
  final int userid;
  final ReceiptScan scan;

  /// Vorhandene Buchung, zu der der Bon gehört (Betrag, Datum, Konto, Kategorie als Vorgabe).
  final Transaction? existing;

  /// Einkaufstag als Vorgabe, wenn auf dem Bon kein Datum steht.
  final DateTime? day;
  const ReceiptReviewScreen({super.key, required this.userid, required this.scan, this.existing, this.day});

  @override
  State<ReceiptReviewScreen> createState() => _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends State<ReceiptReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ParsedReceipt _receipt = const ReceiptParser().parse(widget.scan.lines);
  late final _store = TextEditingController(text: _receipt.store ?? 'Einkauf');
  late final _amount = TextEditingController(
      text: (_receipt.amount ?? widget.existing?.amount)?.toStringAsFixed(2).replaceAll('.', ',') ?? '');
  late DateTime _date = _receipt.date ?? widget.day ?? widget.existing?.date ?? DateTime.now();
  ShoppingComparison _comparison = ShoppingComparison.empty;
  String? _category;
  String? _account;
  List<String> _suggested = const [];
  List<String> _categories = const [];

  /// Keine Ausgaben-Kategorie vorhanden → beim Speichern „Allgemein“ anlegen statt in einer Sackgasse zu enden.
  bool _createFallbackCategory = false;
  static const _fallbackCategory = 'Allgemein';
  List<String> _accounts = const [];
  List<_Line> _lines = const [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _store.dispose();
    _amount.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final nutrition = context.read<NutritionRepository>();
    final categories = await context.read<CategoryRepository>().getAllCategories(widget.userid);
    if (!mounted) return;
    final accounts = await context.read<AccountRepository>().getAllAccounts(widget.userid);
    if (!mounted) return;
    final history = await context.read<TransactionRepository>().getAllTransactions(widget.userid);
    await nutrition.ensureStandardFoods(widget.userid);
    final foods = await nutrition.searchFoods(widget.userid);
    final s = const ReceiptAnalyzer().analyze(
      receipt: _receipt,
      categories: categories,
      accounts: accounts,
      history: history,
      foods: foods,
    );
    if (!mounted) return;
    setState(() {
      _categories = {
        for (final c in categories)
          if (c.transactionType == TransactionType.expense) c.categoryName,
      }.toList();
      _accounts = {for (final a in accounts) a.accountName}.toList();
      _suggested = s.categories;
      _category = s.categories.firstOrNull ?? _categories.firstOrNull;
      if (_categories.isEmpty) {
        _categories = const [_fallbackCategory];
        _category = _fallbackCategory;
        _createFallbackCategory = true;
      }
      _account = s.account ?? _accounts.firstOrNull;
      final existing = widget.existing;
      if (existing != null) {
        if (_accounts.contains(existing.account)) _account = existing.account;
        if (_categories.contains(existing.category)) _category = existing.category;
        if (_receipt.store == null && existing.description.isNotEmpty) _store.text = existing.description;
      }
      _lines = [for (final (i, item) in _receipt.items.indexed) _Line(item, s.items[i].$1, s.items[i].$2)];
    });
    await _compare();
    if (mounted) setState(() => _loading = false);
  }

  /// Abgleich mit dem Einkauf vom Bon-Tag – nur dieser Tag, nur noch nicht belegte Artikel.
  Future<void> _compare() async {
    final trip = await context.read<InventoryRepository>().shoppingTrip(widget.userid, _date);
    if (!mounted) return;
    final comparison = const ReceiptMatcher().compare(
      [for (final l in _lines) l.item],
      [for (final l in _lines) l.food],
      trip,
    );
    setState(() {
      _comparison = comparison;
      for (final (i, l) in _lines.indexed) {
        final linked = comparison.pairs[i];
        if (linked?.id != l.linked?.id) {
          // Schon über die Einkaufsliste im Vorrat → nicht noch einmal anlegen
          l.include = linked == null && l.suggested;
          l.takeReceiptAmount = false;
        }
        l.linked = linked;
      }
    });
  }

  static double? _parse(String s) => double.tryParse(s.trim().replaceAll('€', '').replaceAll(',', '.'));

  Future<void> _pickDate() async {
    final last = DateTime.now().add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(last) ? last : (_date.year < 2000 ? DateTime(2000) : _date),
      firstDate: DateTime(2000),
      lastDate: last,
      helpText: 'Datum des Einkaufs',
    );
    if (picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
    await _compare();
  }

  Future<void> _pickFood(_Line line) async {
    final food = await showFoodPicker(context, userid: widget.userid, initial: line.item.displayName);
    if (food == null) return;
    setState(() {
      line.food = food;
      line.name.text = food.name;
      line.include = line.linked == null;
    });
    await _compare();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final links = [
      for (final l in _lines)
        if (l.linked != null)
          ReceiptLink(
            inventoryId: l.linked!.id!,
            price: l.item.price,
            quantity: l.takeReceiptAmount ? l.item.pantryAmount.$1 : null,
            unit: l.item.pantryAmount.$2,
          ),
    ];
    final pantry = [
      for (final l in _lines.where((l) => l.include))
        PantryLine(
          name: l.name.text.trim().isEmpty ? l.item.displayName : l.name.text.trim(),
          quantity: _parse(l.quantity.text) ?? 1,
          unit: l.unit == 'Stück' ? null : l.unit,
          foodId: l.food?.id,
          price: l.item.price,
          kind: ShoppingCategory.guess(l.name.text) == ShoppingCategory.drinks || l.unit == 'ml' ? InventoryKind.drink : InventoryKind.food,
        ),
    ];
    final categoryRepo = context.read<CategoryRepository>();
    final importer = context.read<ReceiptImportService>();
    final ok = await runGuarded(context, () async {
      if (_createFallbackCategory) {
        await categoryRepo.createCategory(Category(
          categoryName: _fallbackCategory,
          categoryUserid: widget.userid,
          categoryFontFamily: 'MaterialIcons',
          categoryIconName: 'category',
          categoryCodePoint: Icons.category.codePoint,
          transactionType: TransactionType.expense,
        ));
        _createFallbackCategory = false;
      }
      await importer.save(ReceiptDraft(
            userid: widget.userid,
            description: _store.text.trim(),
            amount: _parse(_amount.text) ?? 0,
            date: _date,
            category: _category!,
            account: _account!,
            imagePath: widget.scan.imagePath,
            pantry: pantry,
            links: links,
            closesTrip: _comparison.hasTrip,
            transactionId: widget.existing?.id,
          ));
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) {
      showAppSnack(
        context,
        'Buchung über ${formatEuro(_parse(_amount.text) ?? 0, decimals: 2)} gespeichert'
        '${pantry.isEmpty ? '' : ' · ${pantry.length} ${pantry.length == 1 ? 'Artikel' : 'Artikel'} im Vorrat'}',
      );
      navigator.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: ModernAppBar(title: 'Kassenzettel prüfen'),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(padding: detailPadding(context), children: [
                  _photo(context),
                  const SizedBox(height: 12),
                  Text('Bitte prüfe, ob alles richtig erkannt wurde – du kannst jedes Feld ändern.',
                      style: t.bodySmall?.copyWith(color: c.muted)),
                  const SizedBox(height: 12),
                  const GroupLabel('Buchung'),
                  FormFieldCard(
                    icon: Icons.storefront_outlined,
                    label: 'Händler',
                    child: TextFormField(
                      controller: _store,
                      decoration: bareInputDecoration,
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Bitte Händler eingeben' : null,
                    ),
                  ),
                  FormFieldCard(
                    icon: Icons.euro_rounded,
                    label: 'Betrag (€)',
                    child: TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: bareInputDecoration,
                      validator: (v) => (_parse(v ?? '') ?? 0) <= 0 ? 'Bitte Betrag eingeben' : null,
                    ),
                  ),
                  if (!_receipt.sumMatches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12, left: 4),
                      child: Text(
                        'Hinweis: Die Positionen ergeben ${formatEuro(_receipt.itemsSum, decimals: 2)}, '
                        'auf dem Bon steht ${formatEuro(_receipt.total!, decimals: 2)}.',
                        style: t.bodySmall?.copyWith(color: c.streak),
                      ),
                    ),
                  FormFieldCard(
                    icon: Icons.event_rounded,
                    label: 'Datum',
                    child: InkWell(
                      onTap: _pickDate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(DateFormat('EEEE, d. MMMM y', 'de_DE').format(_date)),
                      ),
                    ),
                  ),
                  FormFieldCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Konto',
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _account,
                      decoration: bareInputDecoration,
                      items: [for (final a in _accounts) DropdownMenuItem(value: a, child: Text(a))],
                      onChanged: (v) => setState(() => _account = v),
                      validator: (v) => v == null
                          ? (_accounts.isEmpty ? 'Noch kein Konto – leg zuerst unter Finanzen › Konten eins an.' : 'Bitte Konto wählen')
                          : null,
                    ),
                  ),
                  FormFieldCard(
                    icon: Icons.category_outlined,
                    label: 'Kategorie',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (_suggested.isNotEmpty) ...[
                        Text('Vorschläge', style: t.labelMedium),
                        const SizedBox(height: 4),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final s in _suggested.take(3))
                            AppChip(label: s, selected: s == _category, onTap: () => setState(() => _category = s)),
                        ]),
                        const SizedBox(height: 6),
                      ],
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _category,
                        decoration: bareInputDecoration,
                        items: [for (final cat in _categories) DropdownMenuItem(value: cat, child: Text(cat))],
                        onChanged: (v) => setState(() => _category = v),
                        validator: (v) => v == null ? 'Bitte Kategorie wählen' : null,
                      ),
                      if (_createFallbackCategory)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Du hast noch keine Ausgaben-Kategorie – „$_fallbackCategory“ wird angelegt.', style: t.bodySmall),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  ..._comparisonSection(context),
                  GroupLabel('Für den Vorrat', trailing: '${_lines.where((l) => l.include).length} von ${_lines.length}'),
                  if (_lines.isEmpty)
                    AppCard(child: Text('Keine Positionen erkannt – es wird nur die Buchung gespeichert.', style: t.bodySmall)),
                  for (final l in _lines) _lineCard(context, l),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Bestätigen und speichern'),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _photo(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ReceiptPhoto(
            path: widget.scan.imagePath,
            width: 72,
            height: 96,
            placeholder: IconTile(icon: Icons.receipt_long_rounded, color: c.accentText, size: 56),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('${_receipt.items.length} Positionen erkannt', style: t.titleSmall),
              subtitle: Text('Erkannten Text anzeigen', style: t.labelMedium),
              children: [
                SelectableText(widget.scan.lines.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _lineCard(BuildContext context, _Line l) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
        color: l.include ? null : c.cardAlt,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Checkbox(
              value: l.include,
              onChanged: (v) => setState(() => l.include = v ?? false),
              semanticLabel: '${l.item.name} in den Vorrat',
            ),
            Expanded(
              child: Text(l.item.name, style: t.labelMedium?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text(formatEuro(l.item.price, decimals: 2), style: t.titleSmall),
          ]),
          if (l.linked != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text('Schon über die Einkaufsliste im Vorrat („${l.linked!.name}“) – wird verknüpft',
                  style: t.labelMedium?.copyWith(color: c.accentText)),
            ),
          if (l.include) ...[
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: TextField(
                controller: l.name,
                decoration: const InputDecoration(isDense: true, labelText: 'Name im Vorrat'),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: l.quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(isDense: true, labelText: 'Menge'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: l.unit,
                    decoration: const InputDecoration(isDense: true, labelText: 'Einheit'),
                    items: [for (final u in const ['g', 'ml', 'Stück']) DropdownMenuItem(value: u, child: Text(u))],
                    onChanged: (v) => setState(() => l.unit = v ?? 'Stück'),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: Row(children: [
                Icon(Icons.restaurant_rounded, size: 16, color: l.food == null ? c.dim : c.accentText),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.food == null ? 'Keinem Lebensmittel zugeordnet' : 'Lebensmittel: ${l.food!.name}',
                    style: t.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(onPressed: () => _pickFood(l), child: Text(l.food == null ? 'Zuordnen' : 'Ändern')),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  /// „Abgleich mit deinem Einkauf vom …“: was abgehakt wurde und was auf dem Bon steht.
  List<Widget> _comparisonSection(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final cmp = _comparison;
    final day = DateFormat('d.M.', 'de_DE').format(_date);
    if (!cmp.hasTrip) {
      return [
        GroupLabel('Abgleich mit deinem Einkauf vom $day'),
        AppCard(
          child: Text('An diesem Tag ist nichts von der Einkaufsliste in den Vorrat gewandert – es gibt nichts abzugleichen.',
              style: t.bodySmall),
        ),
        const SizedBox(height: 12),
      ];
    }
    final onlyReceipt = [
      for (final (i, l) in _lines.indexed)
        if (i < cmp.status.length && cmp.status[i] == ReceiptMatchStatus.onlyOnReceipt && !l.item.isNonGoods) l,
    ];
    Widget row(IconData icon, Color color, String text, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: t.bodyMedium)),
            if (trailing != null) trailing,
          ]),
        );
    return [
      GroupLabel('Abgleich mit deinem Einkauf vom $day', trailing: '${cmp.matchedCount} von ${cmp.trip.length}'),
      AppCard(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, l) in _lines.indexed)
            if (l.linked != null)
              cmp.status[i] == ReceiptMatchStatus.amountDiffers
                  ? row(
                      Icons.warning_amber_rounded,
                      c.streak,
                      '${l.linked!.name}: Vorrat ${formatAmount(l.linked!.quantity, l.linked!.unit)} · '
                      'Bon ${formatAmount(l.item.pantryAmount.$1, l.item.pantryAmount.$2)}',
                      trailing: TextButton(
                        onPressed: () => setState(() => l.takeReceiptAmount = !l.takeReceiptAmount),
                        child: Text(l.takeReceiptAmount ? 'Bon-Menge ✓' : 'Bon-Menge übernehmen'),
                      ),
                    )
                  : row(Icons.check_circle_rounded, c.accentText, '${l.linked!.name} – passt'),
          for (final p in cmp.onlyInPantry)
            row(Icons.help_outline_rounded, c.muted, '${p.name}: abgehakt, aber nicht auf dem Bon'),
          if (onlyReceipt.isNotEmpty)
            row(Icons.add_shopping_cart_rounded, c.muted,
                '${onlyReceipt.length} ${onlyReceipt.length == 1 ? 'Position' : 'Positionen'} nur auf dem Bon – unten für den Vorrat wählbar'),
        ]),
      ),
      const SizedBox(height: 12),
    ];
  }
}
