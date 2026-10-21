import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/receipts/services/receipt_scanner.dart';
import 'package:frontend/core/di/app_providers.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/fitness/services/barcode_scanner.dart';
import 'package:frontend/features/fitness/services/open_food_facts_service.dart';
import 'package:frontend/core/services/image_store.dart';
import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/core/services/device_calendar_service.dart';
import 'package:frontend/core/services/dictation_service.dart';
import 'package:frontend/core/ui/dictation_overlay.dart';
import 'package:frontend/features/fitness/services/food_photo_scanner.dart';
import 'package:frontend/features/fitness/services/meal_photo_ai.dart';

bool _ffiReady = false;

/// Frische, leere Datenbank (eigene Temp-Datei) mit vollständigem App-Schema.
DatabaseService createTestDatabase() {
  if (!_ffiReady) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiReady = true;
  }
  final dir = Directory.systemTemp.createTempSync('lifehub_test_');
  return DatabaseService(path: p.join(dir.path, 'test.db'));
}

Future<UserModel> createTestUser(DatabaseService db, {String email = 'test@example.com'}) async {
  final users = UserRepository(db: db);
  // Hash im aktuellen Format, sonst fragt die App nach einem neuen Passwort (Dialog blockiert Taps).
  final uid = await users.createUser(UserModel(uid: 0, email: email, password: r'pbkdf2_sha256$1$AAAA$AAAA'));
  return users.getUser(uid);
}

Future<void> createTestAccount(DatabaseService db, int uid, String name, {double amount = 0}) {
  return AccountRepository(db: db).createAccount(Account(
    accountName: name,
    accountUserid: uid,
    accountFontFamily: 'MaterialIcons',
    accountIconName: 'wallet',
    accountCodePoint: Icons.wallet.codePoint,
    accountAmount: amount,
  ));
}

Future<double> balanceOf(DatabaseService db, int uid, String name) async {
  final accounts = await AccountRepository(db: db).getAllAccounts(uid);
  return accounts.firstWhere((a) => a.accountName == name).accountAmount;
}

/// Bildablage des Vision Boards in einem eigenen Temp-Ordner.
VisionImageStore testImageStore() {
  final dir = Directory.systemTemp.createTempSync('lifehub_images_');
  return VisionImageStore(baseDir: () async => dir);
}

InventoryImageStore testInventoryImageStore() {
  final dir = Directory.systemTemp.createTempSync('lifehub_inventory_images_');
  return InventoryImageStore(baseDir: () async => dir);
}

ReceiptImageStore testReceiptImageStore() {
  final dir = Directory.systemTemp.createTempSync('lifehub_receipt_images_');
  return ReceiptImageStore(baseDir: () async => dir);
}

/// Scanner, der ohne Kamera sofort [code] liefert (oder `null` = abgebrochen).
/// Liefert statt Kamera und Texterkennung feste Zeilen (oder `null` = abgebrochen).
class FakeReceiptScanner extends ReceiptScanner {
  FakeReceiptScanner(this.lines, {this.imagePath});
  final List<String>? lines;

  /// Gespeichertes Foto (relativ), wie es der echte Scanner liefert.
  final String? imagePath;

  @override
  Future<ReceiptScan?> scan({bool fromGallery = false}) async => lines == null ? null : ReceiptScan(imagePath: imagePath, lines: lines!);
}

class FakeBarcodeScanner extends BarcodeScanner {
  final String? code;
  const FakeBarcodeScanner(this.code);

  @override
  Future<String?> scan(BuildContext context) async => code;
}

/// Open Food Facts ohne Netz: [products] (Barcode → JSON-Produkt) oder 404.
OpenFoodFactsService fakeOpenFoodFacts([Map<String, Map<String, dynamic>> products = const {}]) {
  return OpenFoodFactsService(
    client: MockClient((request) async {
      final code = request.url.pathSegments.last.replaceAll('.json', '');
      final product = products[code];
      if (product == null) return http.Response('{"status":0}', 404);
      return http.Response.bytes(utf8.encode(jsonEncode({'status': 1, 'product': product})), 200);
    }),
  );
}

/// Open Food Facts ohne Internetverbindung (jede Anfrage schlägt fehl).
OpenFoodFactsService offlineOpenFoodFacts() =>
    OpenFoodFactsService(client: MockClient((_) async => throw const SocketException('offline')));

/// Merkt sich geplante Erinnerungen statt echte Benachrichtigungen zu senden.
class RecordingNotifications extends NotificationService {
  RecordingNotifications() : super.forTesting();
  final scheduled = <int, (String, String, DateTime)>{};

  @override
  Future<void> scheduleNotification({required int id, required String title, required String body, required DateTime scheduledDate}) async =>
      scheduled[id] = (title, body, scheduledDate);

  /// Tägliche Erinnerungen: ID → (Titel, Stunde, Minute).
  final daily = <int, (String, int, int)>{};

  @override
  Future<void> scheduleDaily({required int id, required String title, required String body, required int hour, required int minute}) async =>
      daily[id] = (title, hour, minute);

  @override
  Future<void> cancelNotification(int id) async {
    scheduled.remove(id);
    daily.remove(id);
  }

  @override
  Future<void> cancelAllNotifications() async {
    scheduled.clear();
    daily.clear();
  }
}

/// Spracherkennung ohne Mikrofon: liefert beim Start sofort [words] (oder ist nicht verfügbar).
class FakeDictation extends DictationService {
  FakeDictation({this.words = '', this.available = true});
  String words;
  final bool available;
  int starts = 0;

  @override
  Future<bool> start({required void Function(String text, bool isFinal) onResult, VoidCallback? onDone}) async {
    starts++;
    if (!available) return false;
    onResult(words, true);
    onDone?.call();
    return true;
  }

  @override
  Future<void> stop() async {}
}

/// Foto ohne Kamera: liefert ein 1×1-Bild und (für Nährwerttabellen) feste Textzeilen.
class FakeFoodPhotoScanner extends FoodPhotoScanner {
  FakeFoodPhotoScanner({this.lines = const [], this.cancelled = false});
  final List<String> lines;
  final bool cancelled;
  static final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

  @override
  Future<FoodPhoto?> pick({bool fromGallery = false}) async => cancelled ? null : FoodPhoto('fake.jpg', _png);

  @override
  Future<List<String>> readLines(FoodPhoto photo) async => lines;

  @override
  Future<void> discard(FoodPhoto photo) async {}
}

/// KI-Schätzung ohne Netz: liefert [result] bzw. wirft [error].
class FakeMealPhotoAi extends MealPhotoAi {
  FakeMealPhotoAi({this.result, this.error, this.keyProblem});
  final MealEstimate? result;
  final Object? error;
  final String? keyProblem;
  int calls = 0;

  @override
  Future<MealEstimate> estimate(Uint8List jpeg) async {
    calls++;
    if (error != null) throw error!;
    return result!;
  }

  @override
  Future<String?> checkKey(String key) async => keyProblem;
}

/// Handy-Kalender im Speicher: [calendars] mit [events]; zählt, was LifeHub hineinschreibt.
class FakeDeviceCalendar extends DeviceCalendarService {
  FakeDeviceCalendar({this.access = true, List<DeviceCalendar>? calendars, List<ExternalEvent>? events, this.failWrites = false})
      : calendarList = calendars ?? [],
        events = events ?? [];

  bool access;
  final List<DeviceCalendar> calendarList;
  final List<ExternalEvent> events;

  /// Simuliert einen kaputten Kalender-Provider beim Schreiben.
  bool failWrites;

  /// Von LifeHub geschriebene Termine: eventId → (calendarId, Entwurf).
  final written = <String, (String, DeviceEventDraft)>{};
  final deleted = <String>[];
  final deletedCalendars = <String>[];
  var _nextId = 100;

  @override
  Future<bool> hasAccess() async => access;

  @override
  Future<bool> requestAccess() async => access;

  @override
  Future<List<DeviceCalendar>> calendars() async => access ? List.of(calendarList) : const [];

  @override
  Future<List<ExternalEvent>> eventsBetween(Set<String> calendarIds, DateTime from, DateTime to) async => [
        if (access)
          for (final e in events)
            if (calendarIds.contains(e.calendarId) && e.end.isAfter(from) && e.start.isBefore(to)) e,
      ];

  @override
  Future<String?> ensureCalendar(String name, int color) async {
    final existing = calendarList.where((c) => c.name == name).firstOrNull;
    if (existing != null) return existing.id;
    final id = 'cal-${_nextId++}';
    calendarList.add(DeviceCalendar(id: id, name: name, color: color, writable: true));
    return id;
  }

  @override
  Future<String?> upsertEvent(String calendarId, DeviceEventDraft e, {String? eventId}) async {
    if (failWrites) throw Exception('Kalender nicht erreichbar');
    final id = eventId != null && written.containsKey(eventId) ? eventId : 'ev-${_nextId++}';
    written[id] = (calendarId, e);
    return id;
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    written.remove(eventId);
    deleted.add(eventId);
  }

  @override
  Future<void> deleteCalendar(String calendarId) async {
    calendarList.removeWhere((c) => c.id == calendarId);
    written.removeWhere((_, v) => v.$1 == calendarId);
    deletedCalendars.add(calendarId);
  }
}

/// Screen mit allen App-Providern auf [db] rendern.
Widget testApp(
  DatabaseService db,
  Widget home, {
  NotificationService? notifications,
  bool dark = false,
  OpenFoodFactsService? openFoodFacts,
  BarcodeScanner barcodeScanner = const FakeBarcodeScanner(null),
  ReceiptScanner? receiptScanner,
  ReceiptImageStore? receiptImages,
  DictationService? dictation,
  FoodPhotoScanner? foodPhotos,
  MealPhotoAi? mealPhotoAi,
  DeviceCalendarService? deviceCalendar,
}) {
  return MultiProvider(
    providers: appProviders(
      db,
      notifications: notifications,
      visionImages: testImageStore(),
      inventoryImages: testInventoryImageStore(),
      openFoodFacts: openFoodFacts ?? fakeOpenFoodFacts(),
      barcodeScanner: barcodeScanner,
      receiptScanner: receiptScanner ?? FakeReceiptScanner(null),
      receiptImages: receiptImages ?? testReceiptImageStore(),
      dictation: dictation ?? FakeDictation(),
      foodPhotos: foodPhotos ?? FakeFoodPhotoScanner(),
      mealPhotoAi: mealPhotoAi ?? FakeMealPhotoAi(),
      deviceCalendar: deviceCalendar ?? FakeDeviceCalendar(access: false),
    ),
    // Ohne GoogleFonts (AppTheme lädt Schriften aus dem Netz).
    child: MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
        extensions: [dark ? AppColors.dark : AppColors.light],
      ),
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => DictationOverlay(child: child!),
      home: home,
    ),
  );
}

/// Hohe Testfläche, damit lange Formulare ohne Scrollen bedienbar sind.
void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Startseite mit Button "öffnen", der [page] pusht. So kann ein Formular sich
/// wie in der App per `Navigator.pop` schließen; das Ergebnis steht danach als Text da.
Widget launcher(Widget page) => Scaffold(body: _LauncherBody(page: page));

class _LauncherBody extends StatefulWidget {
  final Widget page;
  const _LauncherBody({required this.page});

  @override
  State<_LauncherBody> createState() => _LauncherBodyState();
}

class _LauncherBodyState extends State<_LauncherBody> {
  String _result = '';

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextButton(
        onPressed: () async {
          final r = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => widget.page));
          setState(() => _result = 'result:$r');
        },
        child: const Text('öffnen'),
      ),
      Text(_result),
    ]);
  }
}

/// Tippt ein Dropdown-Feld (per Beschriftung der umgebenden Karte) an und wählt [option].
/// Versucht es erneut, solange die Einträge noch aus der DB geladen werden.
Future<void> selectDropdown(WidgetTester tester, String cardLabel, String option,
    {Duration timeout = const Duration(seconds: 45)}) async {
  final end = DateTime.now().add(timeout);
  while (true) {
    final card = find.ancestor(of: find.text(cardLabel), matching: find.byType(Container)).first;
    final dropdown = find.descendant(of: card, matching: find.byWidgetPredicate((w) => w is DropdownButton));
    await tester.tap(dropdown.first);
    await tester.pumpAndSettle();
    final item = find.descendant(of: find.byType(Scrollable), matching: find.text(option));
    if (item.evaluate().isNotEmpty) {
      await tester.tap(item.last);
      await tester.pumpAndSettle();
      return;
    }
    // Menü (falls offen) schließen, kurz echte Zeit für die DB lassen, erneut versuchen.
    if (find.byType(Scrollable).evaluate().length > 1) await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    if (DateTime.now().isAfter(end)) throw TestFailure('Dropdown "$cardLabel" enthält "$option" nicht');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

/// Text in das Eingabefeld der Formularkarte mit Beschriftung [cardLabel] schreiben.
Future<void> enterInCard(WidgetTester tester, String cardLabel, String text) {
  final card = find.ancestor(of: find.text(cardLabel), matching: find.byType(Container)).first;
  return tester.enterText(find.descendant(of: card, matching: find.byType(TextFormField)), text);
}

/// Befüllt die DB in Widget-Tests außerhalb der Fake-Zeit und schließt die Verbindung
/// danach. Der Screen öffnet sie dann neu in seiner eigenen Zone – sonst blockiert
/// sqflites Transaktions-Lock zwischen echter und Fake-Zeit.
Future<T> seedDb<T>(WidgetTester tester, DatabaseService db, Future<T> Function() seed) async {
  return (await tester.runAsync(() async {
    final result = await seed();
    await db.close();
    return result;
  })) as T;
}

/// Wartet (mit echter Zeit, für DB und Isolates), bis [finder] etwas findet.
/// Achtung: `find.text` findet auch Text in Eingabefeldern – nach dem Absenden
/// eines Dialogs/Formulars erst mit [pumpUntilGone] auf das Schließen warten.
Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 45)}) =>
    _pumpUntil(tester, () => finder.evaluate().isNotEmpty, '$finder', timeout);

/// Liest in Widget-Tests aus der DB, die der Screen geöffnet hat.
///
/// Nicht `tester.runAsync` verwenden: sqflites interne Sperre läuft im Test-Takt;
/// innerhalb von `runAsync` hängt deshalb die zweite Abfrage in Folge für immer.
/// Hier läuft [read] im Test-Takt, und es wird (mit echter Zeit für die DB) weitergetaktet.
Future<T> readDb<T>(WidgetTester tester, Future<T> Function() read, {Duration timeout = const Duration(seconds: 45)}) async {
  late T result;
  Object? error;
  var done = false;
  read().then((v) {
    result = v;
    done = true;
  }, onError: (Object e) {
    error = e;
    done = true;
  });
  await _pumpUntil(tester, () => done, 'DB-Abfrage', timeout);
  if (error != null) throw error!;
  return result;
}

/// Wartet, bis [check] (z. B. eine DB-Abfrage) `true` liefert.
Future<void> pumpUntilTrue(WidgetTester tester, Future<bool> Function() check,
    {Duration timeout = const Duration(seconds: 45)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if ((await tester.runAsync(check)) ?? false) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw TestFailure('Zeitüberschreitung: Bedingung wurde nicht erfüllt');
}

/// Wartet, bis [finder] nichts mehr findet (z. B. Dialog oder Formular geschlossen).
Future<void> pumpUntilGone(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 45)}) =>
    _pumpUntil(tester, () => finder.evaluate().isEmpty, 'Verschwinden von $finder', timeout);

Future<void> _pumpUntil(WidgetTester tester, bool Function() done, String what, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    // Auch die Test-Uhr vorstellen, damit Animationen (FAB, Bottom Sheet) fertig laufen.
    await tester.pump(const Duration(milliseconds: 50));
    if (done()) {
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
  }
  throw TestFailure('Zeitüberschreitung beim Warten auf $what');
}

/// sqflite (ffi) arbeitet mit echten Futures; in Widget-Tests muss man sie
/// außerhalb der Fake-Zeit laufen lassen und danach neu zeichnen.
Future<void> settleDb(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Beendet einen Widget-Test sauber: Screen abbauen, laufende DB-Aufrufe
/// abschließen lassen, dann schließen. Direktes Schließen während ein Screen
/// noch lädt, blockiert sonst auf dem sqflite-Lock.
Future<void> disposeApp(WidgetTester tester, DatabaseService db) async {
  await tester.pumpWidget(const SizedBox());
  await settleDb(tester);
  // Ketten wie Laden → Seeding → neu Laden zu Ende laufen lassen: jede Abfrage wartet auf den sqflite-Lock.
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() async => (await db.database).rawQuery('SELECT 1'));
    await tester.pump();
  }
  await tester.runAsync(db.close);
}

/// Eintrag nach links wischen, „Löschen“ tippen und auf die Rückgängig-Meldung warten.
Future<void> swipeDelete(WidgetTester tester, Finder item) async {
  await tester.drag(item, const Offset(-400, 0));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Löschen'));
  await pumpUntil(tester, find.text('Rückgängig'));
}

/// Zurück über den Pfeil der App-Leiste (wie `tester.pageBack`, aber mit deutschem Tooltip „Zurück“).
Future<void> pageBack(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Zurück').last);
  await tester.pump();
}
