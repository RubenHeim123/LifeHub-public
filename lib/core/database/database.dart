import 'dart:async';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:frontend/core/database/db_backups.dart';

/// Zeitstempel für `last_changed` und Sync: immer UTC mit Millisekunden („2026-10-10T08:15:00.000Z“),
/// damit Textvergleiche (`last_changed > ?`) stimmen – egal ob eingefügt oder geändert.
String syncStamp([DateTime? at]) =>
    DateTime.fromMillisecondsSinceEpoch((at ?? DateTime.now()).millisecondsSinceEpoch, isUtc: true).toIso8601String();

/// SQLite-Verbindung und Schema. Fachlicher Zugriff läuft über die Repositories
/// in `lib/features/*/repositories/`.
class DatabaseService {
  /// [path] überschreibt den Speicherort; [inMemoryDatabasePath] für Tests.
  DatabaseService({String? path}) : _path = path;

  /// Standard-Instanz der App (Datei `finance.db` im Dokumente-Ordner).
  static final DatabaseService instance = DatabaseService();

  static const int schemaVersion = 33;

  /// Tabellen ab Schema 16 – alle mit `userid` und Sync-Spalten (für Export und Kontolöschung).
  static const lifestyleTables = [
    'inventory_items', 'foods', 'meal_entries', 'nutrition_goals', 'exercises', 'workouts',
    'workout_exercises', 'planned_workouts', 'workout_sessions', 'session_sets',
    'outfits', 'outfit_items', 'wishlist_items',
    'shopping_items', 'gift_lists', 'gift_items',
    'recipes', 'meal_plan', 'shopping_sources', 'meal_batches', 'cook_logs',
    'journal_entries', 'pantry_reservations',
    'flash_decks', 'flash_cards', 'contacts', 'contact_notes',
  ];

  final String? _path;
  Future<Database>? _database;

  /// Schlägt das Öffnen fehl, wird es beim nächsten Zugriff neu versucht.
  Future<Database> get database => _database ??= _open().catchError((Object e) {
        _database = null;
        throw e;
      });

  Future<String> _resolvePath() async =>
      _path ?? join((await getApplicationDocumentsDirectory()).path, 'finance.db');

  /// Kopien der Datenbank vor Updates und vor dem Wiederherstellen (Ordner `db_backups/` daneben).
  late final DbBackupStore backups = DbBackupStore.lazy(() async => join(dirname(await _resolvePath()), 'db_backups'));

  /// Öffnet die Datenbank so, dass ein Update nie Daten kostet:
  /// - vor jedem Schema-Update wird die Datei gesichert,
  /// - schlägt das Update fehl, bleibt der alte Stand (notfalls aus der Sicherung) und es gibt
  ///   eine [DatabaseUpgradeException] statt eines halb umgebauten Zustands,
  /// - eine neuere Datenbank (ältere App installiert) wird unverändert geöffnet statt abgelehnt.
  Future<Database> _open() async {
    final path = await _resolvePath();
    final existing = await _versionOf(path);
    if (existing != null && existing > schemaVersion) return openDatabase(path, version: existing);

    DbBackup? backup;
    if (existing != null && existing > 0 && existing < schemaVersion) {
      backup = await backups.create(path, version: existing, reason: BackupReason.update);
    }
    try {
      return await openDatabase(path, version: schemaVersion, onCreate: _onCreate, onUpgrade: _onUpgrade);
    } catch (e) {
      if (backup == null) rethrow;
      await _replaceFile(path, backup.file.path);
      throw DatabaseUpgradeException(fromVersion: existing!, toVersion: schemaVersion, backup: backup, cause: e);
    }
  }

  /// Schema-Version einer vorhandenen Datei, sonst `null` (neu oder nicht lesbar).
  static Future<int?> _versionOf(String path) async {
    if (path == inMemoryDatabasePath || !File(path).existsSync()) return null;
    try {
      final db = await openDatabase(path, readOnly: true, singleInstance: false);
      try {
        return await db.getVersion();
      } finally {
        await db.close();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<void> _replaceFile(String target, String source) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final side = File('$target$suffix');
      if (side.existsSync()) await side.delete();
    }
    await File(source).copy(target);
    for (final suffix in ['-wal', '-shm']) {
      final side = File('$source$suffix');
      if (side.existsSync()) await side.copy('$target$suffix');
    }
  }

  /// Sichert den aktuellen Stand von Hand.
  Future<DbBackup> backupNow() async {
    final path = await _resolvePath();
    final version = (await (await database).getVersion());
    await close();
    return backups.create(path, version: version, reason: BackupReason.manual);
  }

  /// Ersetzt die Datenbank durch [file] (eine Sicherung oder eine geteilte Kopie). Vorher wird
  /// der aktuelle Stand gesichert; danach läuft beim Öffnen das nötige Update.
  Future<void> restoreBackup(File file) async {
    final version = await _checkBackup(file);
    final path = await _resolvePath();
    final current = await (await database).getVersion();
    await close();
    // Die Quelle zuerst kopieren – sie könnte beim Aufräumen der Sicherungen wegfallen.
    final staged = File('$path.restore');
    await file.copy(staged.path);
    await backups.create(path, version: current, reason: BackupReason.beforeRestore);
    await _replaceFile(path, staged.path);
    await staged.delete();
    if (version < schemaVersion) {
      // Kein zusätzliches „Vor dem Update“: der Stand ist ja gerade die Sicherung selbst.
      final db = await openDatabase(path, version: schemaVersion, onCreate: _onCreate, onUpgrade: _onUpgrade);
      await db.close();
    }
  }

  /// Prüft, ob [file] eine LifeHub-Datenbank ist, die diese App lesen kann; liefert die Version.
  static Future<int> _checkBackup(File file) async {
    Database? db;
    try {
      db = await openDatabase(file.path, readOnly: true, singleInstance: false);
      final version = await db.getVersion();
      final users = await db.query('sqlite_master', where: "type = 'table' AND name = 'users'");
      if (users.isEmpty || version < 1) throw const BackupException('Die Datei ist keine LifeHub-Sicherung.');
      if (version > schemaVersion) {
        throw const BackupException('Die Sicherung stammt von einer neueren App-Version – bitte erst die App aktualisieren.');
      }
      return version;
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException('Die Datei ist keine LifeHub-Sicherung.');
    } finally {
      await db?.close();
    }
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS todos(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          description TEXT,
          dueDate TEXT,
          isCompleted INTEGER,
          userid INTEGER,
          FOREIGN KEY (userid) REFERENCES users (uid) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS appointments(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT,
          description TEXT,
          date TEXT,
          userid INTEGER,
          FOREIGN KEY (userid) REFERENCES users (uid) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS habits(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          frequency TEXT,
          userid INTEGER,
          FOREIGN KEY (userid) REFERENCES users (uid) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS habit_records(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          habitId INTEGER,
          date TEXT,
          FOREIGN KEY (habitId) REFERENCES habits (id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 4) {
      // Habit customization
      await db.execute('ALTER TABLE habits ADD COLUMN colorValue INTEGER DEFAULT 4280391411');
      await db.execute('ALTER TABLE habits ADD COLUMN iconCodePoint INTEGER DEFAULT 58249');
      await db.execute('ALTER TABLE habits ADD COLUMN iconFontFamily TEXT DEFAULT "MaterialIcons"');
    }
    if (oldVersion < 5) {
      // Performance Indices
      await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_userid ON transactions (userid)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions (date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_todos_userid ON todos (userid)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_appointments_userid ON appointments (userid)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_habits_userid ON habits (userid)');
    }
    if (oldVersion < 7) {
      // Gamification
      await db.execute('ALTER TABLE users ADD COLUMN experiencePoints INTEGER DEFAULT 0');
    }
    if (oldVersion < 8) {
      // Financial Goals
      await db.execute('''
        CREATE TABLE IF NOT EXISTS financial_goals(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          targetAmount REAL,
          selectedAccountNames TEXT,
          colorHex TEXT,
          deadline TEXT,
          userid INTEGER,
          FOREIGN KEY (userid) REFERENCES users (uid) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 9) {
      await db.execute('ALTER TABLE transactions ADD COLUMN imagePath TEXT');
    }
    if (oldVersion < 10) {
      await db.execute('ALTER TABLE users ADD COLUMN isBiometricEnabled INTEGER DEFAULT 0');
    }
    if (oldVersion < 11) {
      // Delta Sync Support: tracking columns and sync_sessions table
      final tables = [
        'accounts', 'categories', 'transactions', 'fixed_transactions', 
        'todos', 'appointments', 'habits', 'habit_records', 'financial_goals'
      ];
      for (var table in tables) {
        await db.execute('ALTER TABLE $table ADD COLUMN last_changed TEXT');
        await db.execute('UPDATE $table SET last_changed = CURRENT_TIMESTAMP');
        await db.execute('ALTER TABLE $table ADD COLUMN is_deleted INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE $table ADD COLUMN server_id TEXT');
      }
      
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          target_device_id TEXT,
          last_sync_timestamp TEXT,
          status TEXT
        )
      ''');
    }
    if (oldVersion < 12) {
      // Fix for devices that created DB at v11 without habit customization columns
      try { await db.execute('ALTER TABLE habits ADD COLUMN colorValue INTEGER DEFAULT 4280391411'); } catch (_) {}
      try { await db.execute('ALTER TABLE habits ADD COLUMN iconCodePoint INTEGER DEFAULT 58249'); } catch (_) {}
      try { await db.execute('ALTER TABLE habits ADD COLUMN iconFontFamily TEXT DEFAULT "MaterialIcons"'); } catch (_) {}
    }
    if (oldVersion < 13) {
      try { await db.execute("ALTER TABLE habits ADD COLUMN selectedDays TEXT DEFAULT '[1,2,3,4,5,6,7]'"); } catch (_) {}
    }
    if (oldVersion < 14) {
      // Termindauer in Minuten (bestehende Termine bekommen 60 Minuten)
      try { await db.execute('ALTER TABLE appointments ADD COLUMN durationMinutes INTEGER DEFAULT 60'); } catch (_) {}
    }
    if (oldVersion < 15) {
      // Vision Board: Ziele mit Schritt-für-Schritt-Plan, verknüpft mit To-Dos und Terminen
      await db.execute('ALTER TABLE todos ADD COLUMN goalStepId INTEGER');
      await db.execute('ALTER TABLE appointments ADD COLUMN goalStepId INTEGER');
      await _createVisionTables(db);
    }
    if (oldVersion < 16) {
      await _createLifestyleTables(db);
    } else {
      if (oldVersion < 17) {
        // Übungen können auf den mitgelieferten Übungskatalog verweisen
        await db.execute('ALTER TABLE exercises ADD COLUMN catalogKey TEXT');
      }
      if (oldVersion < 18) {
        // Workouts mit Trainingsform (Stufenintervall, Supersatz …) und Timer
        await db.execute('ALTER TABLE workouts ADD COLUMN method TEXT');
      }
      if (oldVersion < 19) {
        // Einkaufsliste und Geschenke-Wunschlisten
        await _createListTables(db);
      }
      if (oldVersion < 20) {
        // Trinkziel in den Ernährungszielen
        try {
          await db.execute('ALTER TABLE nutrition_goals ADD COLUMN waterMl REAL');
        } catch (_) {}
      }
    }
    if (oldVersion < 20) {
      // Erinnerung vor Terminen (bisher fest 30 min)
      try {
        await db.execute('ALTER TABLE appointments ADD COLUMN reminderMinutes INTEGER DEFAULT 30');
      } catch (_) {}
    }
    if (oldVersion < 21) {
      // Ganztägige Einträge (z. B. Geburtstage) und jährliche Wiederholung
      for (final column in ['allDay', 'repeatYearly']) {
        try {
          await db.execute('ALTER TABLE appointments ADD COLUMN $column INTEGER DEFAULT 0');
        } catch (_) {}
      }
    }
    if (oldVersion >= 16 && oldVersion < 22) {
      // Essensplan mit eigenen Rezepten (bei < 16 legt _createLifestyleTables sie an)
      await _createMealPlanTables(db);
    }
    if (oldVersion < 23) {
      // Wiederholungen für To-Dos (z. B. jeden Freitag) und Termine (Regel statt nur „jährlich“)
      for (final (table, column) in [
        ('todos', 'repeat TEXT'),
        ('todos', 'repeatStart TEXT'),
        ('todos', 'seriesId INTEGER'),
        ('appointments', 'repeat TEXT'),
      ]) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN $column');
        } catch (_) {}
      }
      try {
        await db.rawUpdate('UPDATE appointments SET repeat = ? WHERE repeatYearly = 1 AND repeat IS NULL',
            [r'{"freq":"yearly","interval":1}']);
      } catch (_) {}
    }
    if (oldVersion < 24) {
      // Einkaufsliste mit Mengen je Herkunft (Rezept, selbst eingetragen) und Packungsgrößen
      for (final (table, column) in [
        ('shopping_items', 'amount REAL'),
        ('shopping_items', 'unit TEXT'),
        ('shopping_items', 'foodId INTEGER'),
        ('shopping_items', 'boughtAmount REAL'),
        ('foods', 'packSizes TEXT'),
      ]) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN $column');
        } catch (_) {}
      }
      await _createShoppingSources(db);
    }
    if (oldVersion >= 22 && oldVersion < 25) {
      // Koch-Blöcke (Rezept auf Tage verteilt) und Koch-Protokoll mit Vorratsverbrauch
      try {
        await db.execute('ALTER TABLE meal_plan ADD COLUMN batchId INTEGER');
      } catch (_) {}
      await _createCookingTables(db);
    }
    if (oldVersion < 26) {
      // Einheitliche UTC-Zeitstempel für den Sync; Sync-Sitzungen je Nutzer (alte → einmal Vollabgleich)
      try {
        await db.execute('ALTER TABLE sync_sessions ADD COLUMN userid INTEGER');
      } catch (_) {}
      try {
        await db.delete('sync_sessions');
      } catch (_) {}
      await _normalizeSyncStamps(db);
      await _installSyncTriggers(db);
      // Packungsgrößen mit ';' trennen, damit „1,5“ als Dezimalzahl lesbar bleibt
      try {
        await db.execute("UPDATE foods SET packSizes = REPLACE(packSizes, ',', ';') WHERE packSizes IS NOT NULL");
      } catch (_) {}
    }
    if (oldVersion < 27) {
      // Belegfotos relativ zum App-Ordner speichern (der absolute Pfad ändert sich z. B. nach Restore/Gerätewechsel)
      try {
        await db.execute("UPDATE transactions SET imagePath = substr(imagePath, instr(imagePath, 'receipt_images')) "
            "WHERE instr(imagePath, 'receipt_images') > 1");
      } catch (_) {}
    }
    if (oldVersion < 28) {
      await _createJournalTables(db);
      await _installSyncTriggers(db);
    }
    if (oldVersion < 29) {
      // Koch-Termin im Kalender und Vorrats-Reservierungen je Koch-Block
      for (final column in ['cookTime TEXT', 'durationMin INTEGER', 'appointmentId INTEGER', 'ingredientsPlanned INTEGER DEFAULT 0']) {
        try {
          await db.execute('ALTER TABLE meal_batches ADD COLUMN $column');
        } catch (_) {} // schon da (über _createCookingTables angelegt)
      }
      await _createReservationTables(db);
      await _installSyncTriggers(db);
    }
    if (oldVersion < 30) {
      // Einzelne Lebensmittel im Essensplan, Karteikarten, Kontakte
      for (final column in ['foodId INTEGER', 'grams REAL', 'itemId INTEGER']) {
        try {
          await db.execute('ALTER TABLE meal_plan ADD COLUMN $column');
        } catch (_) {}
      }
      await _createLearningAndContactTables(db);
      await _installSyncTriggers(db);
    }
    if (oldVersion < 31) {
      // Gerichte (Portionen statt pro 100 g) und Schalter „Vorrat nutzen“ / „Einkaufen“ je Koch-Block
      for (final (table, column) in [
        ('foods', 'isDish INTEGER DEFAULT 0'),
        ('meal_entries', 'portions REAL'),
        ('meal_batches', 'usePantry INTEGER DEFAULT 1'),
        ('meal_batches', 'shop INTEGER DEFAULT 1'),
      ]) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN $column');
        } catch (_) {} // schon da (frisch angelegt)
      }
    }
    if (oldVersion < 32) {
      // Einkauf ↔ Kassenzettel: Vorratsartikel kennen ihre Herkunft (Einkaufsliste) und ihren Bon,
      // Einkaufsartikel den beim Abhaken gescannten Barcode
      for (final (table, column) in [
        ('inventory_items', 'fromShopping INTEGER DEFAULT 0'),
        ('inventory_items', 'receiptTxId INTEGER'),
        ('shopping_items', 'barcode TEXT'),
      ]) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN $column');
        } catch (_) {} // schon da (frisch angelegt)
      }
    }
    if (oldVersion < 33) await _createDeviceCalendarLinks(db);
  }

  /// Welcher LifeHub-Termin welchem Termin im Handy-Kalender entspricht (ab Schema 33). Gilt nur für
  /// dieses Gerät – deshalb ohne Sync-Spalten, nicht im Export und nicht im Delta-Sync.
  Future<void> _createDeviceCalendarLinks(Database db) => db.execute('CREATE TABLE IF NOT EXISTS device_calendar_links('
      'appointmentId INTEGER PRIMARY KEY, calendarId TEXT, eventId TEXT)');

  /// Karteikarten (Stapel, Karten mit Wiederholungsplan) und Kontakte mit Notizen (ab Schema 30).
  Future<void> _createLearningAndContactTables(Database db) async {
    const sync = 'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT';
    await db.execute('CREATE TABLE IF NOT EXISTS flash_decks(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, color INTEGER, $sync)');
    await db.execute('CREATE TABLE IF NOT EXISTS flash_cards(id INTEGER PRIMARY KEY AUTOINCREMENT, deckId INTEGER, front TEXT, back TEXT, '
        'due TEXT, intervalDays REAL DEFAULT 0, ease REAL DEFAULT 2.5, reps INTEGER DEFAULT 0, lapses INTEGER DEFAULT 0, $sync)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_flash_cards_deck ON flash_cards (deckId)');
    await db.execute('CREATE TABLE IF NOT EXISTS contacts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, nickname TEXT, relation TEXT, '
        'phone TEXT, email TEXT, address TEXT, birthday TEXT, notes TEXT, appointmentId INTEGER, $sync)');
    await db.execute('CREATE TABLE IF NOT EXISTS contact_notes(id INTEGER PRIMARY KEY AUTOINCREMENT, contactId INTEGER, text TEXT, '
        'date TEXT, followUp INTEGER DEFAULT 0, done INTEGER DEFAULT 0, created TEXT, $sync)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_contact_notes_contact ON contact_notes (contactId)');
  }

  /// Koch-Blöcke und Koch-Protokoll (ab Schema 25).
  Future<void> _createCookingTables(Database db) async {
    const sync = 'userid INTEGER, last_changed TEXT DEFAULT CURRENT_TIMESTAMP, is_deleted INTEGER DEFAULT 0, server_id TEXT';
    await db.execute('CREATE TABLE IF NOT EXISTS meal_batches(id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'recipeKey TEXT, recipeId INTEGER, name TEXT, factor REAL DEFAULT 1, cookDate TEXT, cookedAt TEXT, '
        'cookTime TEXT, durationMin INTEGER, appointmentId INTEGER, ingredientsPlanned INTEGER DEFAULT 0, '
        'usePantry INTEGER DEFAULT 1, shop INTEGER DEFAULT 1, $sync)');
    await db.execute('CREATE TABLE IF NOT EXISTS cook_logs(id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'batchId INTEGER, recipeKey TEXT, recipeId INTEGER, name TEXT, date TEXT, usages TEXT, $sync)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_meal_batches_cookDate ON meal_batches (cookDate)');
  }

  /// Für einen Koch-Block reservierte Vorratsmengen (ab Schema 29). `amount` in der Einheit des
  /// Vorratsartikels; `null` = Menge nicht vergleichbar (z. B. 1 TL aus einer Packung).
  Future<void> _createReservationTables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS pantry_reservations(id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'batchId INTEGER, itemId INTEGER, ingredient TEXT, amount REAL, unit TEXT, '
        'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pantry_reservations_item ON pantry_reservations (itemId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pantry_reservations_batch ON pantry_reservations (batchId)');
  }

  /// Woher die Menge eines Einkaufsartikels stammt (ab Schema 24).
  Future<void> _createShoppingSources(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS shopping_sources(
          id INTEGER PRIMARY KEY AUTOINCREMENT, itemId INTEGER, amount REAL, unit TEXT, label TEXT,
          recipeKey TEXT, recipeId INTEGER, batchId INTEGER,
          userid INTEGER, last_changed TEXT DEFAULT CURRENT_TIMESTAMP, is_deleted INTEGER DEFAULT 0, server_id TEXT)''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_shopping_sources_itemId ON shopping_sources (itemId)');
  }

  /// Inventar (Vorrat, Kleidung), Ernährung, Training und Style.
  Future<void> _createLifestyleTables(Database db) async {
    const sync = '''
          userid INTEGER,
          last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
          is_deleted INTEGER DEFAULT 0,
          server_id TEXT''';
    Future<void> table(String name, String columns) => db.execute(
        'CREATE TABLE IF NOT EXISTS $name(id INTEGER PRIMARY KEY AUTOINCREMENT, $columns, $sync)');

    await table('inventory_items', '''
          kind TEXT, name TEXT, category TEXT, location TEXT,
          quantity REAL DEFAULT 1, unit TEXT, brand TEXT, barcode TEXT,
          purchaseDate TEXT, expiryDate TEXT, openedDate TEXT, condition TEXT,
          imagePath TEXT, size TEXT, color TEXT, season TEXT,
          lastUsedAt TEXT, wearCount INTEGER DEFAULT 0, price REAL, notes TEXT, foodId INTEGER,
          fromShopping INTEGER DEFAULT 0, receiptTxId INTEGER''');
    await table('foods', '''
          name TEXT, brand TEXT, barcode TEXT,
          kcal REAL DEFAULT 0, protein REAL DEFAULT 0, carbs REAL DEFAULT 0, fat REAL DEFAULT 0,
          servingGrams REAL, packSizes TEXT, isDish INTEGER DEFAULT 0''');
    await table('meal_entries', '''
          date TEXT, meal TEXT, foodId INTEGER, name TEXT, grams REAL,
          kcal REAL, protein REAL, carbs REAL, fat REAL, portions REAL''');
    await table('nutrition_goals', 'kcal REAL, protein REAL, carbs REAL, fat REAL, waterMl REAL');
    await table('exercises', 'name TEXT, type TEXT, metric TEXT, notes TEXT, catalogKey TEXT');
    await table('workouts', 'name TEXT, notes TEXT, repeatWeekdays TEXT, method TEXT');
    await table('workout_exercises', '''
          workoutId INTEGER, exerciseId INTEGER, sets INTEGER, reps INTEGER,
          durationSec INTEGER, distanceKm REAL, position INTEGER DEFAULT 0''');
    await table('planned_workouts', 'date TEXT, workoutId INTEGER, name TEXT, status TEXT, sessionId INTEGER');
    await table('workout_sessions', 'plannedId INTEGER, workoutId INTEGER, name TEXT, date TEXT, durationMin INTEGER, notes TEXT');
    await table('session_sets', '''
          sessionId INTEGER, exerciseId INTEGER, setIndex INTEGER,
          reps INTEGER, durationSec INTEGER, distanceKm REAL, done INTEGER DEFAULT 0''');
    await table('outfits', 'name TEXT, imagePath TEXT, lastWornAt TEXT, wearCount INTEGER DEFAULT 0');
    await table('outfit_items', 'outfitId INTEGER, itemId INTEGER');
    await table('wishlist_items', '''
          name TEXT, price REAL, url TEXT, imagePath TEXT, priority INTEGER DEFAULT 2,
          status TEXT DEFAULT 'open', boughtItemId INTEGER''');
    await _createListTables(db);
    await _createMealPlanTables(db);

    for (final (t, c) in [
      ('inventory_items', 'userid'), ('inventory_items', 'expiryDate'), ('foods', 'userid'),
      ('meal_entries', 'date'), ('exercises', 'userid'), ('workouts', 'userid'),
      ('workout_exercises', 'workoutId'), ('planned_workouts', 'date'), ('session_sets', 'sessionId'),
      ('outfits', 'userid'), ('outfit_items', 'outfitId'), ('wishlist_items', 'userid'),
    ]) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${t}_$c ON $t ($c)');
    }
  }

  /// Essensplan und eigene Rezepte (ab Schema 22).
  Future<void> _createMealPlanTables(Database db) async {
    const sync = '''
          userid INTEGER,
          last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
          is_deleted INTEGER DEFAULT 0,
          server_id TEXT''';
    Future<void> table(String name, String columns) => db.execute(
        'CREATE TABLE IF NOT EXISTS $name(id INTEGER PRIMARY KEY AUTOINCREMENT, $columns, $sync)');

    await table('recipes', '''
          name TEXT, summary TEXT, meals TEXT, servings INTEGER DEFAULT 1, minutes INTEGER DEFAULT 0,
          ingredients TEXT, steps TEXT, kcal REAL DEFAULT 0, protein REAL DEFAULT 0, carbs REAL DEFAULT 0,
          fat REAL DEFAULT 0, gramsPerServing REAL''');
    await table('meal_plan', '''
          date TEXT, meal TEXT, time INTEGER, recipeKey TEXT, recipeId INTEGER, name TEXT,
          servings REAL DEFAULT 1, note TEXT, mealEntryId INTEGER, batchId INTEGER, foodId INTEGER, grams REAL, itemId INTEGER''');
    await _createCookingTables(db);
    for (final (t, c) in [('recipes', 'userid'), ('meal_plan', 'date')]) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${t}_$c ON $t ($c)');
    }
  }

  /// Einkaufsliste und Geschenke-Wunschlisten (ab Schema 19).
  Future<void> _createListTables(Database db) async {
    const sync = '''
          userid INTEGER,
          last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
          is_deleted INTEGER DEFAULT 0,
          server_id TEXT''';
    Future<void> table(String name, String columns) => db.execute(
        'CREATE TABLE IF NOT EXISTS $name(id INTEGER PRIMARY KEY AUTOINCREMENT, $columns, $sync)');

    await table('shopping_items',
        'name TEXT, category TEXT, quantity TEXT, done INTEGER DEFAULT 0, doneAt TEXT, amount REAL, unit TEXT, foodId INTEGER, boughtAmount REAL, barcode TEXT');
    await table('gift_lists', 'person TEXT, occasion TEXT, date TEXT, notes TEXT');
    await table('gift_items', "listId INTEGER, name TEXT, price REAL, url TEXT, notes TEXT, status TEXT DEFAULT 'idea'");
    await _createShoppingSources(db);
    for (final (t, c) in [('shopping_items', 'userid'), ('gift_lists', 'userid'), ('gift_items', 'listId')]) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${t}_$c ON $t ($c)');
    }
  }

  /// Vision Board: Bereiche → Ziele → Plan-Schritte. To-Dos und Termine verweisen
  /// über `goalStepId` auf einen Schritt.
  Future<void> _createVisionTables(Database db) async {
    const sync = '''
          last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
          is_deleted INTEGER DEFAULT 0,
          server_id TEXT''';
    await db.execute('''
        CREATE TABLE IF NOT EXISTS vision_areas(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userid INTEGER,
          title TEXT,
          imagePath TEXT,
          colorValue INTEGER,
          position INTEGER DEFAULT 0,
$sync
        )
      ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS vision_goals(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          areaId INTEGER,
          userid INTEGER,
          title TEXT,
          note TEXT,
          isAchieved INTEGER DEFAULT 0,
          position INTEGER DEFAULT 0,
$sync
        )
      ''');
    await db.execute('''
        CREATE TABLE IF NOT EXISTS goal_steps(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          goalId INTEGER,
          userid INTEGER,
          title TEXT,
          description TEXT,
          isDone INTEGER DEFAULT 0,
          position INTEGER DEFAULT 0,
$sync
        )
      ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_vision_areas_userid ON vision_areas (userid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_vision_goals_areaId ON vision_goals (areaId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_goal_steps_goalId ON goal_steps (goalId)');
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
        CREATE TABLE accounts(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          accountName TEXT,
          accountUserid INTEGER,
          accountIconName TEXT,
          accountCodePoint INTEGER,
          accountFontFamily TEXT,
          accountAmount REAL,
          last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
          is_deleted INTEGER DEFAULT 0,
          server_id TEXT,
          FOREIGN KEY (accountUserid) REFERENCES users (uid) ON DELETE CASCADE
        )
      ''');
    await db.execute('''
  CREATE TABLE categories(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    categoryName TEXT,
    categoryUserid INTEGER,
    categoryIconName TEXT,
          categoryCodePoint INTEGER,
          categoryFontFamily TEXT,
    transactionType TEXT,
    monthlyBudget REAL DEFAULT 0.0,
    last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
    is_deleted INTEGER DEFAULT 0,
    server_id TEXT,
    FOREIGN KEY (categoryUserid) REFERENCES users (uid) ON DELETE CASCADE
  )
''');
    await db.execute('''
  CREATE TABLE fixed_transactions(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    start_time TEXT,
    end_time TEXT,
    next_time TEXT,
    interval TEXT,
    amount REAL,
    category TEXT,
    description TEXT,
    account TEXT,
    transactionType TEXT,
    userid INTEGER,
    last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
    is_deleted INTEGER DEFAULT 0,
    server_id TEXT,
    FOREIGN KEY (userid) REFERENCES users (uid) ON DELETE CASCADE
  )
''');
    await db.execute('''
  CREATE TABLE transactions(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT,
    amount REAL,
    category TEXT,
    description TEXT,
    account TEXT,
    transactionType TEXT,
    userid INTEGER,
    imagePath TEXT,
    last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
    is_deleted INTEGER DEFAULT 0,
    server_id TEXT,
    FOREIGN KEY (userid) REFERENCES users (uid) ON DELETE CASCADE
  )
''');
    await db.execute('''
  CREATE TABLE users(
    uid INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT,
    password TEXT,
    display_name TEXT,
    age INTEGER,
    phonenumber TEXT,
    created_time TEXT,
    experiencePoints INTEGER DEFAULT 0,
    isBiometricEnabled INTEGER DEFAULT 0
  )
''');
    await db.execute('''
  CREATE TABLE todos(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT,
    description TEXT,
    dueDate TEXT,
    isCompleted INTEGER,
    userid INTEGER,
    goalStepId INTEGER,
    repeat TEXT,
    repeatStart TEXT,
    seriesId INTEGER,
    last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
    is_deleted INTEGER DEFAULT 0,
    server_id TEXT,
    FOREIGN KEY (userid) REFERENCES users (uid) ON DELETE CASCADE
  )
''');
    await db.execute('''
  CREATE TABLE appointments(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT,
    description TEXT,
    date TEXT,
    durationMinutes INTEGER DEFAULT 60,
    userid INTEGER,
    goalStepId INTEGER,
    reminderMinutes INTEGER DEFAULT 15,
    allDay INTEGER DEFAULT 0,
    repeatYearly INTEGER DEFAULT 0,
    repeat TEXT,
    last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
    is_deleted INTEGER DEFAULT 0,
    server_id TEXT,
    FOREIGN KEY (userid) REFERENCES users (uid) ON DELETE CASCADE
  )
''');
    await db.execute('''
  CREATE TABLE habits(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    frequency TEXT,
    userid INTEGER,
    colorValue INTEGER DEFAULT 4280391411,
    iconCodePoint INTEGER DEFAULT 58249,
    iconFontFamily TEXT DEFAULT "MaterialIcons",
    selectedDays TEXT DEFAULT '[1,2,3,4,5,6,7]',
    last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
    is_deleted INTEGER DEFAULT 0,
    server_id TEXT,
    FOREIGN KEY (userid) REFERENCES users (uid) ON DELETE CASCADE
  )
''');
    await db.execute('''
  CREATE TABLE habit_records(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    habitId INTEGER,
    date TEXT,
    last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
    is_deleted INTEGER DEFAULT 0,
    server_id TEXT,
    FOREIGN KEY (habitId) REFERENCES habits (id) ON DELETE CASCADE
  )
''');
    // Performance Indices
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_userid ON transactions (userid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions (date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_todos_userid ON todos (userid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_appointments_userid ON appointments (userid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_habits_userid ON habits (userid)');

    // Financial Goals
    await db.execute('''
        CREATE TABLE IF NOT EXISTS financial_goals(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          targetAmount REAL,
          selectedAccountNames TEXT,
          colorHex TEXT,
          deadline TEXT,
          userid INTEGER,
          last_changed TEXT DEFAULT CURRENT_TIMESTAMP,
          is_deleted INTEGER DEFAULT 0,
          server_id TEXT,
          FOREIGN KEY (userid) REFERENCES users (uid) ON DELETE CASCADE
        )
      ''');
      
    await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          target_device_id TEXT,
          last_sync_timestamp TEXT,
          status TEXT,
          userid INTEGER
        )
      ''');

    await _createVisionTables(db);
    await _createLifestyleTables(db);
    await _createJournalTables(db);
    await _createReservationTables(db);
    await _createLearningAndContactTables(db);
    await _createDeviceCalendarLinks(db);
    await _installSyncTriggers(db);
  }

  /// Journal: ein Eintrag je Tag mit Stimmung, Antworten auf Leitfragen (JSON) und freiem Text (ab Schema 28).
  Future<void> _createJournalTables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS journal_entries(id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'date TEXT, mood INTEGER, text TEXT, answers TEXT, '
        'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_journal_entries_user_date ON journal_entries (userid, date)');
  }

  /// Hält `last_changed` in allen Tabellen im [syncStamp]-Format: Einfügungen bekommen per Trigger
  /// die aktuelle UTC-Zeit (statt CURRENT_TIMESTAMP „2026-10-10 08:15:00“, das beim Textvergleich
  /// vor jedem „…T…“ desselben Tages einsortiert würde), lokale Zeiten werden nach UTC umgerechnet.
  /// Neue Tabellen mit `last_changed` brauchen nach einer Migration erneut diesen Aufruf.
  Future<void> _installSyncTriggers(Database db) async {
    const now = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'");
    for (final row in tables) {
      final table = row['name'] as String;
      final columns = (await db.rawQuery('PRAGMA table_info($table)')).map((c) => c['name']);
      if (!columns.contains('last_changed')) continue;
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS sync_insert_$table AFTER INSERT ON $table
        WHEN NEW.last_changed IS NULL OR NEW.last_changed NOT LIKE '%Z'
        BEGIN UPDATE $table SET last_changed = $now WHERE rowid = NEW.rowid; END''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS sync_update_$table AFTER UPDATE OF last_changed ON $table
        WHEN NEW.last_changed IS NOT NULL AND NEW.last_changed NOT LIKE '%Z'
        BEGIN UPDATE $table SET last_changed = strftime('%Y-%m-%dT%H:%M:%fZ', NEW.last_changed, 'utc') WHERE rowid = NEW.rowid; END''');
    }
  }

  /// Schema 26: bestehende `last_changed`-Werte vereinheitlichen. CURRENT_TIMESTAMP-Werte („… …“) sind
  /// schon UTC, ISO-Werte („…T…“) waren lokale Zeit.
  Future<void> _normalizeSyncStamps(Database db) async {
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'");
    for (final row in tables) {
      final table = row['name'] as String;
      final columns = (await db.rawQuery('PRAGMA table_info($table)')).map((c) => c['name']);
      if (!columns.contains('last_changed')) continue;
      await db.execute("UPDATE $table SET last_changed = strftime('%Y-%m-%dT%H:%M:%fZ', last_changed) "
          "WHERE last_changed LIKE '____-__-__ __:__:__%' AND last_changed NOT LIKE '%Z'");
      await db.execute("UPDATE $table SET last_changed = strftime('%Y-%m-%dT%H:%M:%fZ', last_changed, 'utc') "
          "WHERE last_changed LIKE '____-__-__T%' AND last_changed NOT LIKE '%Z'");
      await db.execute("UPDATE $table SET last_changed = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE last_changed IS NULL");
    }
  }

  Future<void> deleteDatabaseFile() async {
    await close();
    await databaseFactory.deleteDatabase(await _resolvePath());
  }

  /// Macht ein weich gelöschtes Element wieder sichtbar („Rückgängig“).
  Future<void> restoreRow(String table, int id) async {
    final db = await database;
    await db.update(table, {'is_deleted': 0, 'last_changed': syncStamp()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db == null) return;
    try {
      await (await db).close();
    } catch (_) {} // Öffnen war fehlgeschlagen – nichts zu schließen
  }
}
