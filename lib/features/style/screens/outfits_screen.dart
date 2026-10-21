import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/style/models/style.dart';
import 'package:frontend/features/style/repositories/style_repository.dart';
import 'package:frontend/features/style/screens/outfit_editor_screen.dart';
import 'package:frontend/features/style/widgets/style_widgets.dart';

/// Outfits: zusammengestellte Kombinationen, „heute getragen“ und Hinweis auf nie Getragenes.
class OutfitsScreen extends StatefulWidget {
  final UserModel user;
  const OutfitsScreen({super.key, required this.user});

  @override
  State<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends State<OutfitsScreen> {
  late final StyleRepository _repo = context.read<StyleRepository>();
  late final InventoryRepository _inventory = context.read<InventoryRepository>();
  List<Outfit>? _outfits;
  int _clothingCount = 0;
  int _neverWornItems = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final outfits = await _repo.getOutfits(widget.user.uid);
    final clothing = await _inventory.getItems(widget.user.uid, kinds: {InventoryKind.clothing, InventoryKind.accessory});
    if (!mounted) return;
    setState(() {
      _outfits = outfits;
      _clothingCount = clothing.length;
      _neverWornItems = clothing.where((i) => i.wearCount == 0).length;
    });
  }

  Future<void> _edit([Outfit? outfit]) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(builder: (_) => OutfitEditorScreen(userid: widget.user.uid, outfit: outfit)),
    );
    if (!mounted) return;
    if (result == kDeletedResult && outfit != null) {
      await _delete(outfit);
    } else if (result == true) {
      _load();
    }
  }

  Future<void> _delete(Outfit outfit) => deleteWithUndo(
        context,
        label: outfit.name,
        delete: () => _repo.deleteOutfit(outfit.id!),
        restore: () => _repo.restoreOutfit(outfit.id!),
        onChanged: _load,
      );

  Future<void> _wear(Outfit outfit) async {
    final messenger = ScaffoldMessenger.of(context);
    await _repo.wearOutfit(outfit);
    messenger.showSnackBar(SnackBar(content: Text('„${outfit.name}“ heute getragen')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final outfits = _outfits;
    return Scaffold(
      floatingActionButton: AppFab(
        heroTag: 'outfits-fab',
        onPressed: outfits == null ? null : () => _edit(),
        label: 'Outfit',
      ),
      body: outfits == null
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pagePadding(context),
                children: [
                  if (_neverWornItems > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          IconTile(icon: Icons.lightbulb_outline_rounded, color: c.streak),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _neverWornItems == 1
                                  ? '1 Teil wurde noch nie getragen – kombinier es in einem Outfit.'
                                  : '$_neverWornItems Teile wurden noch nie getragen – kombinier sie in Outfits.',
                              style: t.bodyMedium,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  if (outfits.isEmpty)
                    EmptyState(
                      icon: Icons.checkroom_rounded,
                      title: 'Noch keine Outfits',
                      message: _clothingCount == 0
                          ? 'Leg zuerst Kleidung im Kleiderschrank an.'
                          : 'Stell Kombinationen aus deinem Kleiderschrank zusammen.',
                    ),
                  if (outfits.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '„Heute tragen“ merkt sich, wann und wie oft du ein Outfit und seine Teile trägst – '
                        'so siehst du im Kleiderschrank, was lange nicht mehr dran war.',
                        style: t.bodySmall?.copyWith(color: c.muted),
                      ),
                    ),
                  for (final o in outfits)
                    SwipeTile(
                      id: 'outfit-${o.id}',
                      startAction: SwipeAction(label: 'Heute', icon: Icons.checkroom_rounded, onPressed: () => _wear(o)),
                      onEdit: () => _edit(o),
                      onDelete: () => _delete(o),
                      child: _OutfitCard(outfit: o, onTap: () => _edit(o), onWear: () => _wear(o)),
                    ),
                ],
              ),
            ),
    );
  }
}

class _OutfitCard extends StatelessWidget {
  final Outfit outfit;
  final VoidCallback onTap;
  final VoidCallback onWear;
  const _OutfitCard({required this.outfit, required this.onTap, required this.onWear});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final worn = outfit.lastWornAt;
    final today = DateTime.now();
    final wornToday = worn != null && worn.year == today.year && worn.month == today.month && worn.day == today.day;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            StoredImage(path: outfit.imagePath, fallback: Icons.checkroom_rounded, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(outfit.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  outfit.neverWorn
                      ? 'Nie getragen · ${outfit.items.length} Teile'
                      : '${outfit.wearCount}× getragen · zuletzt ${DateFormat('d.M.', 'de_DE').format(worn!)}',
                  style: t.labelMedium?.copyWith(color: outfit.neverWorn ? c.streak : null),
                ),
              ]),
            ),
          ]),
          if (outfit.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final i in outfit.items)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(8)),
                  child: Text(i.name, style: t.labelMedium),
                ),
            ]),
          ],
          const SizedBox(height: 10),
          Tooltip(
            message: 'Zählt das Outfit und alle Teile als heute getragen',
            child: OutlinedButton.icon(
              onPressed: wornToday ? null : onWear,
              icon: Icon(wornToday ? Icons.check_rounded : Icons.today_rounded),
              label: Text(wornToday ? 'Heute getragen' : 'Heute tragen'),
            ),
          ),
        ]),
      ),
    );
  }
}
