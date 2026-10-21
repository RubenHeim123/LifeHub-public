import 'package:flutter/material.dart';

import 'package:frontend/app/app_tabs.dart';
import 'package:frontend/app/tab_style.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/hub_tabs.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/contacts/screens/contacts_screen.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/screens/inventory_screen.dart';
import 'package:frontend/features/learning/screens/learning_screen.dart';
import 'package:frontend/features/lists/screens/gifts_screen.dart';
import 'package:frontend/features/style/screens/outfits_screen.dart';
import 'package:frontend/features/style/screens/wishlist_screen.dart';

extension MoreSectionInfo on MoreSection {
  String get label => switch (this) {
        MoreSection.learning => 'Lernen',
        MoreSection.contacts => 'Kontakte',
        MoreSection.gifts => 'Geschenke',
        MoreSection.wardrobe => 'Kleiderschrank',
        MoreSection.outfits => 'Outfits',
        MoreSection.wishlist => 'Wunschliste',
      };

  String get hint => switch (this) {
        MoreSection.learning => 'Karteikarten',
        MoreSection.contacts => 'Menschen und Notizen',
        MoreSection.gifts => 'Ideen je Person',
        MoreSection.wardrobe => 'Kleidung und Pflege',
        MoreSection.outfits => 'Zusammenstellen',
        MoreSection.wishlist => 'Wünsche und Budget',
      };

  IconData get icon => switch (this) {
        MoreSection.learning => Icons.school_rounded,
        MoreSection.contacts => Icons.people_alt_rounded,
        MoreSection.gifts => Icons.card_giftcard_rounded,
        MoreSection.wardrobe => Icons.checkroom_rounded,
        MoreSection.outfits => Icons.style_rounded,
        MoreSection.wishlist => Icons.favorite_border_rounded,
      };
}

Widget _page(UserModel user, MoreSection s) => switch (s) {
      MoreSection.learning => LearningScreen(user: user),
      MoreSection.contacts => ContactsScreen(user: user),
      MoreSection.gifts => GiftsScreen(user: user),
      MoreSection.wardrobe => InventoryScreen(
          user: user,
          kinds: const {InventoryKind.clothing, InventoryKind.accessory, InventoryKind.care},
          addKind: InventoryKind.clothing,
          addKinds: const [InventoryKind.clothing, InventoryKind.accessory, InventoryKind.care],
          gridByDefault: true,
        ),
      MoreSection.outfits => OutfitsScreen(user: user),
      MoreSection.wishlist => WishlistScreen(user: user),
    };

/// Eine Seite aus „Mehr“ mit Titelleiste und Zurück.
class MoreSectionPage extends StatelessWidget {
  final UserModel user;
  final MoreSection section;
  const MoreSectionPage({super.key, required this.user, required this.section});

  @override
  Widget build(BuildContext context) => Scaffold(appBar: ModernAppBar(title: section.label), body: _page(user, section));
}

/// Öffnet eine Seite aus „Mehr“ als eigene Seite (auch von Heute aus, z. B. Kontakte).
Future<void> openMoreSection(BuildContext context, UserModel user, MoreSection section) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MoreSectionPage(user: user, section: section)));

/// Tab „Mehr“: seltener genutzte Bereiche als Kacheln.
class MoreScreen extends StatelessWidget {
  final UserModel user;
  const MoreScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return TabPage(
      title: AppTab.more.style.label,
      icon: AppTab.more.style.activeIcon,
      color: AppTab.more.style.toneOf(context),
      child: ListView(
        padding: pagePadding(context),
        children: [
          LayoutBuilder(builder: (context, box) {
            const gap = 10.0;
            final width = (box.maxWidth - gap) / 2;
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (final s in MoreSection.values)
                SizedBox(
                  width: width,
                  child: AppCard(
                    onTap: () => openMoreSection(context, user, s),
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      IconTile(icon: s.icon, color: c.accentText),
                      const SizedBox(height: 10),
                      Text(s.label, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(s.hint, style: t.labelMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
            ]);
          }),
        ],
      ),
    );
  }
}
