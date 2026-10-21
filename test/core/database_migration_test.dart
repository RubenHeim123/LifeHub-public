import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:frontend/core/database/database.dart';

import '../helpers/test_app.dart';

/// Upgrade einer bestehenden Datenbank (Version 14) auf das aktuelle Schema.
void main() {
  test('upgrade from v14 adds vision, inventory, fitness and style tables without losing data', () async {
    createTestDatabase(); // initialisiert sqflite ffi
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'old.db');

    final old = await openDatabase(path, version: 14, onCreate: (db, _) async {
      await db.execute('CREATE TABLE todos(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, userid INTEGER, '
          'isCompleted INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.execute('CREATE TABLE appointments(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, date TEXT, '
          'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('todos', {'title': 'Alt', 'userid': 1, 'isCompleted': 0});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;

    expect(await db.getVersion(), DatabaseService.schemaVersion);
    final todoColumns = (await db.rawQuery('PRAGMA table_info(todos)')).map((r) => r['name']);
    final appointmentColumns = (await db.rawQuery('PRAGMA table_info(appointments)')).map((r) => r['name']);
    expect(todoColumns, contains('goalStepId'));
    expect(appointmentColumns, contains('goalStepId'));
    for (final table in ['vision_areas', 'vision_goals', 'goal_steps', ...DatabaseService.lifestyleTables]) {
      expect(await db.query('sqlite_master', where: 'name = ?', whereArgs: [table]), hasLength(1), reason: table);
    }
    expect((await db.query('todos')).single['title'], 'Alt');
    await service.close();
  });

  test('upgrade from v16 links exercises to the catalog and adds training methods', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v16.db');
    final old = await openDatabase(path, version: 16, onCreate: (db, _) async {
      await db.execute('CREATE TABLE exercises(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, type TEXT, metric TEXT, '
          'notes TEXT, userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.execute('CREATE TABLE workouts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, notes TEXT, '
          'repeatWeekdays TEXT, userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('exercises', {'name': 'Liegestütze', 'userid': 1});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    final columns = (await db.rawQuery('PRAGMA table_info(exercises)')).map((r) => r['name']);
    expect(columns, contains('catalogKey'));
    final workoutColumns = (await db.rawQuery('PRAGMA table_info(workouts)')).map((r) => r['name']);
    expect(workoutColumns, contains('method'));
    for (final table in ['shopping_items', 'gift_lists', 'gift_items']) {
      expect(await db.query('sqlite_master', where: 'name = ?', whereArgs: [table]), hasLength(1), reason: table);
    }
    expect((await db.query('exercises')).single['name'], 'Liegestütze');
    await service.close();
  });

  test('upgrade from v21 adds the meal plan and own recipes', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v21.db');
    final old = await openDatabase(path, version: 21, onCreate: (db, _) async {
      await db.execute('CREATE TABLE meal_entries(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, meal TEXT, name TEXT, '
          'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('meal_entries', {'date': '2026-09-30', 'meal': 'lunch', 'name': 'Dal', 'userid': 1});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    expect(await db.getVersion(), DatabaseService.schemaVersion);
    for (final table in ['recipes', 'meal_plan']) {
      expect(await db.query('sqlite_master', where: 'name = ?', whereArgs: [table]), hasLength(1), reason: table);
    }
    expect((await db.query('meal_entries')).single['name'], 'Dal');
    await service.close();
  });

  test('upgrade from v22 adds recurring todos and turns yearly appointments into a repeat rule', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v22.db');
    final old = await openDatabase(path, version: 22, onCreate: (db, _) async {
      await db.execute('CREATE TABLE todos(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, dueDate TEXT, '
          'isCompleted INTEGER, userid INTEGER, goalStepId INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.execute('CREATE TABLE appointments(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, date TEXT, userid INTEGER, '
          'allDay INTEGER DEFAULT 0, repeatYearly INTEGER DEFAULT 0, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('todos', {'title': 'Alt', 'userid': 1, 'isCompleted': 0});
      await db.insert('appointments', {'title': 'Geburtstag', 'date': '1990-03-12T00:00:00.000', 'userid': 1, 'allDay': 1, 'repeatYearly': 1});
      await db.insert('appointments', {'title': 'Arzt', 'date': '2026-10-05T10:00:00.000', 'userid': 1});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    final todoColumns = (await db.rawQuery('PRAGMA table_info(todos)')).map((r) => r['name']);
    expect(todoColumns, containsAll(['repeat', 'repeatStart', 'seriesId']));
    final appointments = await db.query('appointments', orderBy: 'id');
    expect(appointments.first['repeat'], contains('yearly'));
    expect(appointments.last['repeat'], isNull);
    expect((await db.query('todos')).single['title'], 'Alt');
    await service.close();
  });

  test('upgrade from v23 adds shopping amounts, sources and pack sizes', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v23.db');
    final old = await openDatabase(path, version: 23, onCreate: (db, _) async {
      await db.execute('CREATE TABLE shopping_items(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, category TEXT, quantity TEXT, '
          'done INTEGER DEFAULT 0, doneAt TEXT, userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.execute('CREATE TABLE foods(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, userid INTEGER, '
          'last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('shopping_items', {'name': 'Quark', 'quantity': '600 g', 'userid': 1});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    final columns = (await db.rawQuery('PRAGMA table_info(shopping_items)')).map((r) => r['name']);
    expect(columns, containsAll(['amount', 'unit', 'foodId', 'boughtAmount']));
    expect((await db.rawQuery('PRAGMA table_info(foods)')).map((r) => r['name']), contains('packSizes'));
    expect(await db.query('sqlite_master', where: 'name = ?', whereArgs: ['shopping_sources']), hasLength(1));
    expect((await db.query('shopping_items')).single['quantity'], '600 g');
    await service.close();
  });

  test('upgrade from v24 adds cooking batches and cook logs', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v24.db');
    final old = await openDatabase(path, version: 24, onCreate: (db, _) async {
      await db.execute('CREATE TABLE meal_plan(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, meal TEXT, name TEXT, '
          'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('meal_plan', {'date': '2026-10-01', 'meal': 'lunch', 'name': 'Dal', 'userid': 1});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    expect((await db.rawQuery('PRAGMA table_info(meal_plan)')).map((r) => r['name']), contains('batchId'));
    for (final table in ['meal_batches', 'cook_logs']) {
      expect(await db.query('sqlite_master', where: 'name = ?', whereArgs: [table]), hasLength(1), reason: table);
    }
    expect((await db.query('meal_plan')).single['name'], 'Dal');
    await service.close();
  });

  test('upgrade from v25 unifies sync timestamps (UTC with Z) and keeps sync sessions per user', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v25.db');
    final old = await openDatabase(path, version: 25, onCreate: (db, _) async {
      await db.execute('CREATE TABLE todos(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, userid INTEGER, '
          'isCompleted INTEGER, last_changed TEXT DEFAULT CURRENT_TIMESTAMP, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.execute('CREATE TABLE sync_sessions(id INTEGER PRIMARY KEY AUTOINCREMENT, target_device_id TEXT, '
          'last_sync_timestamp TEXT, status TEXT)');
      await db.insert('todos', {'title': 'eingefügt', 'userid': 1, 'isCompleted': 0, 'last_changed': '2026-10-10 08:00:00'});
      await db.insert('todos', {'title': 'geändert', 'userid': 1, 'isCompleted': 0, 'last_changed': '2026-10-10T10:00:00.000'});
      await db.insert('sync_sessions', {'target_device_id': '192.168.0.2', 'last_sync_timestamp': '2026-10-10T09:00:00.000'});
      await db.execute('CREATE TABLE foods(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, packSizes TEXT, userid INTEGER, '
          'last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('foods', {'name': 'Hack', 'packSizes': '400,600', 'userid': 1});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    final stamps = {for (final r in await db.query('todos')) r['title']: r['last_changed']};
    expect(stamps['eingefügt'], '2026-10-10T08:00:00.000Z'); // CURRENT_TIMESTAMP war schon UTC
    expect(stamps['geändert'], endsWith('Z'));
    expect((await db.rawQuery('PRAGMA table_info(sync_sessions)')).map((r) => r['name']), contains('userid'));
    expect(await db.query('sync_sessions'), isEmpty); // einmal Vollabgleich statt falscher Deltas
    expect((await db.query('foods')).single['packSizes'], '400;600');

    await db.insert('todos', {'title': 'neu', 'userid': 1, 'isCompleted': 0});
    final inserted = (await db.query('todos', where: 'title = ?', whereArgs: ['neu'])).single['last_changed'] as String;
    expect(inserted, endsWith('Z'));
    await service.close();
  });

  test('upgrade from v26 stores receipt photos relative to the app folder', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v26.db');
    final old = await openDatabase(path, version: 26, onCreate: (db, _) async {
      await db.execute('CREATE TABLE transactions(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT, imagePath TEXT, '
          'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('transactions', {'description': 'Bon', 'imagePath': '/data/user/0/app/app_flutter/receipt_images/1_0.jpg'});
      await db.insert('transactions', {'description': 'Neu', 'imagePath': 'receipt_images/2_0.jpg'});
      await db.insert('transactions', {'description': 'Fremd', 'imagePath': '/storage/emulated/0/Pictures/foto.jpg'});
      await db.insert('transactions', {'description': 'Ohne'});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    final paths = {for (final r in await db.query('transactions')) r['description']: r['imagePath']};
    expect(paths, {
      'Bon': 'receipt_images/1_0.jpg',
      'Neu': 'receipt_images/2_0.jpg',
      'Fremd': '/storage/emulated/0/Pictures/foto.jpg', // fremde Datei bleibt, wo sie ist
      'Ohne': null,
    });
    await service.close();
  });

  test('upgrade from v27 adds the journal with sync stamps', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v27.db');
    final old = await openDatabase(path, version: 27, onCreate: (db, _) async {
      await db.execute('CREATE TABLE todos(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, userid INTEGER, '
          'isCompleted INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('todos', {'title': 'bleibt', 'userid': 1, 'isCompleted': 0});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    expect((await db.query('todos')).single['title'], 'bleibt');
    await db.insert('journal_entries', {'date': '2026-10-11', 'mood': 4, 'text': 'Erster Eintrag', 'userid': 1});
    final row = (await db.query('journal_entries')).single;
    expect(row['is_deleted'], 0);
    expect(row['last_changed'] as String, endsWith('Z')); // Sync-Trigger auch für die neue Tabelle
    await service.close();
  });

  test('upgrade from v28 adds cooking appointments and pantry reservations', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v28.db');
    final old = await openDatabase(path, version: 28, onCreate: (db, _) async {
      await db.execute('CREATE TABLE meal_batches(id INTEGER PRIMARY KEY AUTOINCREMENT, recipeKey TEXT, recipeId INTEGER, '
          'name TEXT, factor REAL DEFAULT 1, cookDate TEXT, cookedAt TEXT, userid INTEGER, last_changed TEXT, '
          'is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('meal_batches', {'name': 'Dal', 'cookDate': '2026-10-18', 'userid': 1});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    final batch = (await db.query('meal_batches')).single;
    expect(batch['name'], 'Dal');
    expect(batch['ingredientsPlanned'], 0);
    expect(batch.containsKey('appointmentId'), isTrue);
    await db.insert('pantry_reservations', {'batchId': batch['id'], 'itemId': 1, 'ingredient': 'Linsen', 'amount': 200, 'userid': 1});
    expect(((await db.query('pantry_reservations')).single['last_changed'] as String), endsWith('Z'));
    await service.close();
  });

  test('upgrade from v29 adds foods in the meal plan, flash cards and contacts', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v29.db');
    final old = await openDatabase(path, version: 29, onCreate: (db, _) async {
      await db.execute('CREATE TABLE meal_plan(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, meal TEXT, name TEXT, servings REAL, '
          'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('meal_plan', {'date': '2026-10-20', 'meal': 'lunch', 'name': 'Dal', 'servings': 1, 'userid': 1});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    final planned = (await db.query('meal_plan')).single;
    expect((planned['name'], planned.containsKey('foodId'), planned.containsKey('grams')), ('Dal', true, true));
    for (final table in ['flash_decks', 'flash_cards', 'contacts', 'contact_notes']) {
      expect(DatabaseService.lifestyleTables, contains(table));
      final id = await db.insert(table, {'userid': 1});
      final row = (await db.query(table, where: 'id = ?', whereArgs: [id])).single;
      expect(row['last_changed'] as String, endsWith('Z'), reason: table);
    }
    await service.close();
  });

  test('upgrade from v30 adds dishes, portions in the food log and the pantry/shopping switches of a cook batch', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v30.db');
    final old = await openDatabase(path, version: 30, onCreate: (db, _) async {
      await db.execute('CREATE TABLE foods(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, kcal REAL, servingGrams REAL, '
          'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.execute('CREATE TABLE meal_entries(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, grams REAL, kcal REAL, '
          'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.execute('CREATE TABLE meal_batches(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, '
          'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('foods', {'name': 'Haferflocken', 'kcal': 370, 'userid': 1});
      await db.insert('meal_entries', {'name': 'Haferflocken', 'grams': 60, 'kcal': 222, 'userid': 1});
      await db.insert('meal_batches', {'name': 'Dal', 'userid': 1});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    final food = (await db.query('foods')).single;
    expect((food['name'], food['isDish']), ('Haferflocken', 0));
    expect((await db.query('meal_entries')).single['portions'], isNull);
    final batch = (await db.query('meal_batches')).single;
    expect((batch['usePantry'], batch['shop']), (1, 1)); // bisheriges Verhalten bleibt
    await service.close();
  });

  test('upgrade from v31 links pantry items to shopping and receipts, shopping items get a barcode', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v31.db');
    final old = await openDatabase(path, version: 31, onCreate: (db, _) async {
      await db.execute('CREATE TABLE inventory_items(id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT, name TEXT, quantity REAL, '
          'unit TEXT, purchaseDate TEXT, userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.execute('CREATE TABLE shopping_items(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, done INTEGER DEFAULT 0, '
          'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('inventory_items', {'kind': 'food', 'name': 'Haferflocken', 'quantity': 500, 'unit': 'g', 'userid': 1});
      await db.insert('shopping_items', {'name': 'Tofu', 'userid': 1});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    final item = (await db.query('inventory_items')).single;
    // Alte Vorratsartikel gelten nicht als Einkauf – sonst würde für jeden alten Tag ein Bon verlangt
    expect((item['name'], item['fromShopping'], item['receiptTxId']), ('Haferflocken', 0, null));
    expect((await db.query('shopping_items')).single['barcode'], isNull);
    await service.close();
  });

  test('upgrade from v32 adds the device-only link table for the phone calendar', () async {
    createTestDatabase();
    final path = p.join(Directory.systemTemp.createTempSync('lifehub_migration_').path, 'v32.db');
    final old = await openDatabase(path, version: 32, onCreate: (db, _) async {
      await db.execute('CREATE TABLE appointments(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, date TEXT, '
          'userid INTEGER, last_changed TEXT, is_deleted INTEGER DEFAULT 0, server_id TEXT)');
      await db.insert('appointments', {'title': 'Zahnarzt', 'date': '2026-10-30T09:00:00.000', 'userid': 1});
    });
    await old.close();

    final service = DatabaseService(path: path);
    final db = await service.database;
    expect((await db.query('appointments')).single['title'], 'Zahnarzt');
    final columns = (await db.rawQuery('PRAGMA table_info(device_calendar_links)')).map((c) => c['name']).toList();
    // Ohne Sync-Spalten: die IDs gelten nur auf diesem Handy und wandern nicht in Export oder Sync
    expect(columns, ['appointmentId', 'calendarId', 'eventId']);
    await service.close();
  });
}
