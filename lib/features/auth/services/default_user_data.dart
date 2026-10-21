import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';

/// Konten und Kategorien, die jeder neue Nutzer bei der Registrierung erhält.
class DefaultUserData {
  DefaultUserData._();

  // (Name, Icon-Codepoint, Icon-Name)
  static const _accounts = <(String, int, String)>[
    ('Girokonto', 60978, 'account_balance'),
    ('Barvermögen', 60979, 'wallet_outlined'),
    ('Trade Republic', 62562, 'query_stats_outlined'),
    ('Kreditkarte', 61327, 'credit_card_outlined'),
    ('Urlaub', 61495, 'explore_outlined'),
    ('Sparkonto', 62262, 'savings_outlined'),
    ('ING', 59194, 'real_estate_agent_outlined'),
  ];

  // (Name, Icon-Codepoint, Icon-Name, Typ)
  static const _categories = <(String, int, String, TransactionType)>[
    ('Gehalt', 62054, 'payments_outlined', TransactionType.income),
    ('Vermietung', 62190, 'real_estate_agent_outlined', TransactionType.income),
    ('Geschenke', 61229, 'card_giftcard_outlined', TransactionType.income),
    ('Überweisung', 62482, 'sync_alt_outlined', TransactionType.income),
    ('Anpassung', 61099, 'auto_fix_high_outlined', TransactionType.income),
    ('Allgemein', 61239, 'category_outlined', TransactionType.expense),
    ('Kleidung', 61260, 'checkroom_outlined', TransactionType.expense),
    ('Lebensmittel', 61513, 'fastfood_outlined', TransactionType.expense),
    ('Kindersachen', 61264, 'child_friendly_outlined', TransactionType.expense),
    ('Miete', 62190, 'real_estate_agent_outlined', TransactionType.expense),
    ('Haus', 61703, 'home_outlined', TransactionType.expense),
    ('Haushaltsmittel', 61970, 'night_shelter_outlined', TransactionType.expense),
    ('Versicherungen', 62588, 'verified_outlined', TransactionType.expense),
    ('Gesundheit', 61886, 'medical_services_outlined', TransactionType.expense),
    ('Reisen', 61572, 'flight_land_outlined', TransactionType.expense),
    ('Freizeit', 62675, 'work_off_outlined', TransactionType.expense),
    ('Haustiere', 62085, 'pets_outlined', TransactionType.expense),
    ('Bücher', 61151, 'book_outlined', TransactionType.expense),
    ('Ausflüge', 62548, 'tour_outlined', TransactionType.expense),
    ('Strom/Wasser', 984812, 'electric_bolt_outlined', TransactionType.expense),
    ('Tanken', 984842, 'propane_tank_outlined', TransactionType.expense),
    ('Auto', 61382, 'directions_car_outlined', TransactionType.expense),
    ('Schule', 62268, 'school_outlined', TransactionType.expense),
    ('Sport', 61562, 'fitness_center_outlined', TransactionType.expense),
    ('Musik', 61947, 'music_note_outlined', TransactionType.expense),
    ('Freunde', 62060, 'people_outlined', TransactionType.expense),
    ('Technische Ausrüstung', 62082, 'personal_video_outlined', TransactionType.expense),
    ('Geschenke', 61229, 'card_giftcard_outlined', TransactionType.expense),
    ('Investition', 62562, 'trending_up_outlined', TransactionType.expense),
    ('Spenden', 62196, 'redeem_outlined', TransactionType.expense),
    ('Gaming', 62410, 'sports_esports_outlined', TransactionType.expense),
    ('Überweisung', 62482, 'sync_alt_outlined', TransactionType.expense),
    ('Anpassung', 61099, 'auto_fix_high_outlined', TransactionType.expense),
  ];

  static List<Account> accounts(int uid) => [
        for (final (name, codePoint, icon) in _accounts)
          Account(
            accountName: name,
            accountCodePoint: codePoint,
            accountFontFamily: 'MaterialIcons',
            accountIconName: icon,
            accountAmount: 0.0,
            accountUserid: uid,
          ),
      ];

  static List<Category> categories(int uid) => [
        for (final (name, codePoint, icon, type) in _categories)
          Category(
            categoryName: name,
            categoryCodePoint: codePoint,
            categoryFontFamily: 'MaterialIcons',
            categoryIconName: icon,
            transactionType: type,
            categoryUserid: uid,
          ),
      ];
}
