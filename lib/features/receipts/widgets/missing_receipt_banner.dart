import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/receipts/screens/receipt_review_screen.dart';

/// Hinweis „Einkauf vom 21.10. · 5 Artikel – noch kein Kassenzettel“ am Einkaufstag und am Tag danach,
/// wenn Sachen von der Einkaufsliste in den Vorrat gewandert sind, aber kein Bon dazu da ist. Danach
/// verschwindet er von selbst – ein Bon ist kein Muss.
/// Antippen scannt den Bon für genau diesen Tag; „Ohne Bon“ schließt den Tag ab. Ohne offene Tage
/// bleibt der Hinweis unsichtbar. Ändert sich [revision], wird neu geladen.
class MissingReceiptBanner extends StatefulWidget {
  final int userid;
  final int revision;

  /// Nach einem gespeicherten Bon (z. B. um die Ansicht drumherum neu zu laden).
  final VoidCallback? onChanged;

  /// Abstand unter dem Hinweis – nur, wenn er sichtbar ist.
  final double bottomSpacing;

  const MissingReceiptBanner({super.key, required this.userid, this.revision = 0, this.onChanged, this.bottomSpacing = 12});

  @override
  State<MissingReceiptBanner> createState() => _MissingReceiptBannerState();
}

class _MissingReceiptBannerState extends State<MissingReceiptBanner> {
  late final InventoryRepository _repo = context.read<InventoryRepository>();
  List<(DateTime, int)> _trips = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MissingReceiptBanner old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision || old.userid != widget.userid) _load();
  }

  Future<void> _load() async {
    final trips = await _repo.tripsWithoutReceipt(widget.userid);
    if (mounted) setState(() => _trips = trips);
  }

  void _changed() {
    _load();
    widget.onChanged?.call();
  }

  Future<void> _scan(DateTime day) => scanReceipt(context, userid: widget.userid, day: day, onSaved: _changed);

  Future<void> _dismiss(DateTime day) async {
    final messenger = ScaffoldMessenger.of(context);
    final at = await _repo.dismissTrip(widget.userid, day);
    _load();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('Einkauf vom ${_label(day)} ohne Kassenzettel abgeschlossen'),
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: () async {
          await _repo.undoDismissTrip(widget.userid, at);
          _load();
        },
      ),
    ));
  }

  static String _label(DateTime d) => DateFormat('d.M.', 'de_DE').format(d);

  @override
  Widget build(BuildContext context) {
    if (_trips.isEmpty) return const SizedBox.shrink();
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomSpacing),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Column(children: [
          for (final (day, count) in _trips.take(3))
            Row(children: [
              Icon(Icons.receipt_long_rounded, color: c.streak, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _scan(day),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Einkauf vom ${_label(day)} · $count ${count == 1 ? 'Artikel' : 'Artikel'}', style: t.bodyLarge),
                      Text('Noch kein Kassenzettel – antippen zum Scannen', style: t.labelMedium),
                    ]),
                  ),
                ),
              ),
              TextButton(onPressed: () => _dismiss(day), child: const Text('Ohne Bon')),
            ]),
        ]),
      ),
    );
  }
}
