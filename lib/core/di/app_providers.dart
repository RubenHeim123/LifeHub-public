import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:frontend/core/services/device_calendar_service.dart';
import 'package:frontend/features/calendar/services/calendar_sync.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/features/auth/services/auth.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/financial_goal_repository.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/finance/services/export_service.dart';
import 'package:frontend/features/finance/services/local_sync_service.dart';
import 'package:frontend/features/finance/services/prediction_service.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/features/fitness/repositories/workout_repository.dart';
import 'package:frontend/features/fitness/services/barcode_scanner.dart';
import 'package:frontend/features/fitness/services/open_food_facts_service.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/lists/repositories/lists_repository.dart';
import 'package:frontend/features/receipts/services/receipt_import_service.dart';
import 'package:frontend/features/receipts/services/receipt_scanner.dart';
import 'package:frontend/features/meals/repositories/meal_plan_repository.dart';
import 'package:frontend/features/style/repositories/style_repository.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/vision/repositories/vision_repository.dart';
import 'package:frontend/core/services/image_store.dart';
import 'package:frontend/core/services/dictation_service.dart';
import 'package:frontend/features/fitness/services/food_photo_scanner.dart';
import 'package:frontend/features/fitness/services/meal_photo_ai.dart';
import 'package:frontend/features/contacts/repositories/contact_repository.dart';
import 'package:frontend/features/journal/repositories/journal_repository.dart';
import 'package:frontend/features/learning/repositories/learning_repository.dart';

/// Alle Repositories und Services der App. Widgets holen sie mit
/// `context.read<XRepository>()`; Tests übergeben eigene Instanzen/Fakes.
List<SingleChildWidget> appProviders(
  DatabaseService db, {
  NotificationService? notifications,
  VisionImageStore? visionImages,
  InventoryImageStore? inventoryImages,
  OpenFoodFactsService? openFoodFacts,
  BarcodeScanner? barcodeScanner,
  ReceiptScanner? receiptScanner,
  ReceiptImageStore? receiptImages,
  DictationService? dictation,
  FoodPhotoScanner? foodPhotos,
  MealPhotoAi? mealPhotoAi,
  AiKeyStore? aiKeys,
  DeviceCalendarService? deviceCalendar,
}) {
  final n = notifications ?? NotificationService();
  final receiptStore = receiptImages ?? ReceiptImageStore();
  final keys = aiKeys ?? const AiKeyStore();
  final users = UserRepository(db: db);
  final accounts = AccountRepository(db: db);
  final categories = CategoryRepository(db: db);
  final transactions = TransactionRepository(db: db, notifications: n);
  final inventory = InventoryRepository(db: db, notifications: n);
  final nutrition = NutritionRepository(db: db, inventory: inventory);
  final lists = ListsRepository(db: db, inventory: inventory);
  final calendarSync = CalendarSync(device: deviceCalendar ?? const DeviceCalendarService());
  final appointments = AppointmentRepository(db: db, notifications: n, calendarSync: calendarSync);
  final export = ExportService(
    db: db,
    users: users,
    accounts: accounts,
    categories: categories,
    transactions: transactions,
  );

  return [
    Provider<DatabaseService>.value(value: db),
    Provider<NotificationService>.value(value: n),
    Provider<DictationService>.value(value: dictation ?? DictationService()),
    Provider<FoodPhotoScanner>.value(value: foodPhotos ?? const FoodPhotoScanner()),
    Provider<AiKeyStore>.value(value: keys),
    Provider<MealPhotoAi>.value(value: mealPhotoAi ?? MealPhotoAi(keys: keys)),
    Provider<UserRepository>.value(value: users),
    Provider<AccountRepository>.value(value: accounts),
    Provider<CategoryRepository>.value(value: categories),
    Provider<TransactionRepository>.value(value: transactions),
    Provider<FinancialGoalRepository>.value(value: FinancialGoalRepository(db: db)),
    Provider<TodoRepository>.value(value: TodoRepository(db: db, notifications: n)),
    Provider<AppointmentRepository>.value(value: appointments),
    Provider<CalendarSync>.value(value: calendarSync),
    Provider<HabitRepository>.value(value: HabitRepository(db: db)),
    Provider<JournalRepository>.value(value: JournalRepository(db: db, notifications: n)),
    Provider<ContactRepository>.value(value: ContactRepository(db: db, appointments: appointments, notifications: n)),
    Provider<LearningRepository>.value(value: LearningRepository(db: db)),
    Provider<VisionRepository>.value(value: VisionRepository(db: db)),
    Provider<VisionImageStore>.value(value: visionImages ?? VisionImageStore()),
    Provider<InventoryRepository>.value(value: inventory),
    Provider<NutritionRepository>.value(value: nutrition),
    Provider<WorkoutRepository>.value(value: WorkoutRepository(db: db)),
    Provider<ListsRepository>.value(value: lists),
    Provider<MealPlanRepository>.value(value: MealPlanRepository(db: db, lists: lists, inventory: inventory, appointments: appointments)),
    Provider<StyleRepository>.value(value: StyleRepository(db: db, inventory: inventory, transactions: transactions)),
    Provider<FoodLookupService>.value(
      value: FoodLookupService(nutrition: nutrition, openFoodFacts: openFoodFacts ?? OpenFoodFactsService()),
    ),
    Provider<BarcodeScanner>.value(value: barcodeScanner ?? const BarcodeScanner()),
    Provider<ReceiptImageStore>.value(value: receiptStore),
    Provider<ReceiptScanner>.value(value: receiptScanner ?? ReceiptScanner(images: receiptStore)),
    Provider<ReceiptImportService>.value(value: ReceiptImportService(transactions: transactions, inventory: inventory)),
    Provider<InventoryImageStore>.value(value: inventoryImages ?? InventoryImageStore()),
    Provider<AuthService>.value(value: AuthService(users: users, accounts: accounts, categories: categories)),
    Provider<PredictionService>.value(value: PredictionService(transactions: transactions, accounts: accounts)),
    Provider<ExportService>.value(value: export),
    Provider<LocalSyncService>.value(value: LocalSyncService(db: db, exportService: export)),
  ];
}
