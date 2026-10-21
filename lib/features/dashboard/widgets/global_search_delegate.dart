import 'package:flutter/material.dart';
import 'package:frontend/features/habits/repositories/habit_repository.dart';
import 'package:frontend/features/habits/screens/add_habit_screen.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/features/calendar/screens/add_update_appointment_screen.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/finance/models/transaction.dart' as tr;
import 'package:frontend/features/todos/models/todo.dart';
import 'package:frontend/features/finance/screens/add_update_transactions.dart';
import 'package:frontend/features/todos/screens/add_update_todo_screen.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/habits/models/habit.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';
import 'package:frontend/features/inventory/screens/item_editor_screen.dart';
import 'package:frontend/features/inventory/widgets/inventory_widgets.dart';
import 'package:intl/intl.dart';
import 'package:frontend/features/contacts/models/contact.dart';
import 'package:frontend/features/contacts/repositories/contact_repository.dart';
import 'package:frontend/features/contacts/screens/contacts_screen.dart';
import 'package:frontend/features/contacts/widgets/contact_widgets.dart';
import 'package:frontend/features/journal/models/journal_entry.dart';
import 'package:frontend/features/journal/repositories/journal_repository.dart';
import 'package:frontend/features/journal/screens/journal_editor_screen.dart';

/// Öffnet einen Treffer im Editor. Wählt man dort „Löschen“, wird mit „Rückgängig“ gelöscht.
Future<void> _openFromSearch(
  BuildContext context,
  Widget editor, {
  required String label,
  Future<void> Function(BuildContext context)? delete,
  Future<void> Function(BuildContext context)? restore,
}) async {
  final navigator = Navigator.of(context);
  final result = await navigator.push<Object?>(MaterialPageRoute(builder: (_) => editor));
  if (result != kDeletedResult || delete == null || restore == null) return;
  final host = navigator.context;
  if (!host.mounted) return;
  await deleteWithUndo(host, label: label, delete: () => delete(host), restore: () => restore(host));
}

class GlobalSearchDelegate extends SearchDelegate<String> {
  final int userId;
  final DatabaseService db;
  GlobalSearchDelegate({required this.userId, required this.db}) : super(searchFieldLabel: 'Suchen …');

  @override
  List<Widget> buildActions(BuildContext context) {
    final c = AppColors.of(context);
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: Icon(Icons.clear, color: c.accentText),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final c = AppColors.of(context);
    if (query.trim().isEmpty) return const SizedBox.shrink();

    return FutureBuilder<Map<String, List<dynamic>>>(
      future: _performSearch(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: c.accentText));
        }
        if (snapshot.hasError) {
          return EmptyState(icon: Icons.error_outline_rounded, title: 'Suche fehlgeschlagen', message: errorText(snapshot.error!));
        }

        final data = snapshot.data;
        if (data == null || data.values.every((list) => list.isEmpty)) {
          return EmptyState(icon: Icons.search_off_rounded, title: 'Nichts gefunden', message: 'Zu „${query.trim()}“ gibt es keine Treffer.');
        }

        return ListView(
          padding: detailPadding(context),
          children: [
            if (data['contacts']!.isNotEmpty) ...[
              _sectionHeader('Kontakte'),
              ...data['contacts']!.map((item) {
                final Contact p = item;
                return _glassCard(
                  child: ListTile(
                    leading: ContactAvatar(contact: p, size: 36),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: p.relation == null ? null : Text(p.relation!, style: const TextStyle(fontSize: 12)),
                    onTap: () => openContact(context, p.id!),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
            if (data['transactions']!.isNotEmpty) ...[
              _sectionHeader('Finanzen'),
              ...data['transactions']!.map((item) {
                final tr.Transaction t = item;
                return _glassCard(
                  child: ListTile(
                    leading: Icon(Icons.receipt_long, color: c.accentText),
                    title: Text(t.description, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${DateFormat('dd.MM.yyyy').format(t.date)} - ${t.category}', style: const TextStyle(fontSize: 12)),
                    trailing: Text(
                      formatEuro(t.signedAmount, decimals: 2, sign: true),
                      style: TextStyle(
                        color: t.transactionType.isExpense ? c.negative : c.positive,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    onTap: () => _openFromSearch(
                      context,
                      AddUpdateTransaction(userid: userId, transaction: t),
                      label: t.description.isNotEmpty ? t.description : t.category,
                      delete: (c) => c.read<TransactionRepository>().deleteTransaction(t.id!),
                      restore: (c) => c.read<TransactionRepository>().restoreTransaction(t.id!),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
            if (data['todos']!.isNotEmpty) ...[
              _sectionHeader('Aufgaben (To-Dos)'),
              ...data['todos']!.map((item) {
                final Todo t = item;
                return _glassCard(
                  child: ListTile(
                    leading: Icon(
                      t.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: t.isCompleted ? c.positive : c.accentText,
                    ),
                    title: Text(t.title, style: TextStyle(decoration: t.isCompleted ? TextDecoration.lineThrough : null, fontWeight: FontWeight.w600)),
                    subtitle: Text(t.dueDate != null ? DateFormat('dd.MM.yyyy').format(t.dueDate!) : 'Kein Datum', style: const TextStyle(fontSize: 12)),
                    onTap: () => _openFromSearch(
                      context,
                      AddUpdateTodoScreen(userid: userId, todo: t),
                      label: t.title,
                      delete: (c) => c.read<TodoRepository>().deleteTodo(t.id!),
                      restore: (c) => c.read<TodoRepository>().restoreTodo(t),
                    ),
                  ),
                );
              }),
            ],

            if (data['appointments']!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _sectionHeader('Termine'),
              ...data['appointments']!.map((item) {
                final Appointment a = item;
                return _glassCard(
                  child: ListTile(
                    leading: Icon(Icons.calendar_today, color: c.accentText),
                    title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [
                        DateFormat(a.allDay ? 'dd.MM.yyyy' : 'dd.MM.yyyy HH:mm').format(a.date),
                        if (a.repeatYearly) 'jährlich',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12)),
                    onTap: () => _openFromSearch(
                      context,
                      AddUpdateAppointmentScreen(userid: userId, appointment: a),
                      label: a.title,
                      delete: (c) => c.read<AppointmentRepository>().deleteAppointment(a.id!),
                      restore: (c) => c.read<AppointmentRepository>().restoreAppointment(a),
                    ),
                  ),
                );
              }),
            ],

            if (data['inventory']!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _sectionHeader('Inventar'),
              ...data['inventory']!.map((item) {
                final InventoryItem i = item;
                return _glassCard(
                  child: ListTile(
                    leading: InventoryThumb(item: i, size: 36),
                    title: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [i.kind.label, if (i.location != null) i.location!, if (expiryText(i).isNotEmpty) expiryText(i)].join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => _openFromSearch(
                      context,
                      ItemEditorScreen(userid: userId, kind: i.kind, item: i),
                      label: i.name,
                      delete: (c) => c.read<InventoryRepository>().deleteItem(i.id!),
                      restore: (c) => c.read<InventoryRepository>().restoreItem(i),
                    ),
                  ),
                );
              }),
            ],

            if (data['habits']!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _sectionHeader('Gewohnheiten'),
              ...data['habits']!.map((item) {
                final Habit h = item;
                return _glassCard(
                  child: ListTile(
                    leading: Icon(
                      IconData(h.iconCodePoint, fontFamily: h.iconFontFamily),
                      color: Color(h.colorValue),
                    ),
                    title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(h.selectedDays.length >= 7 ? 'Jeden Tag' : '${h.selectedDays.length}× pro Woche',
                        style: const TextStyle(fontSize: 12)),
                    onTap: () => _openFromSearch(
                      context,
                      AddHabitScreen(userid: userId, habit: h),
                      label: h.name,
                      delete: (c) => c.read<HabitRepository>().deleteHabit(h.id!),
                      restore: (c) => c.read<HabitRepository>().restoreHabit(h.id!),
                    ),
                  ),
                );
              }),
            ],

            if (data['journal']!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _sectionHeader('Journal'),
              ...data['journal']!.map((item) {
                final JournalEntry e = item;
                return _glassCard(
                  child: ListTile(
                    leading: Text(e.mood?.emoji ?? '📝', style: const TextStyle(fontSize: 24)),
                    title: Text(DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(e.date), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(e.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    onTap: () => openJournalEditor(context, userid: userId, entry: e),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String title) => GroupLabel(title);

  /// Treffer als Karte im App-Stil (statt Glas-Effekt, der im hellen Modus kaum sichtbar war).
  Widget _glassCard({required Widget child}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(padding: EdgeInsets.zero, child: child),
      );

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Alles durchsuchen',
        message: 'Buchungen, To-Dos, Termine, Vorrat, Habits, Journal und Kontakte.',
      );
    }
    return buildResults(context);
  }

  Future<Map<String, List<dynamic>>> _performSearch(String query) async {
    final database = await db.database;
    final String searchPattern = '%${query.toLowerCase()}%';

    final tMaps = await database.query(
      'transactions',
      where: 'userid = ? AND is_deleted = 0 AND (LOWER(description) LIKE ? OR LOWER(category) LIKE ?)',
      whereArgs: [userId, searchPattern, searchPattern],
      limit: 10,
    );

    final todoMaps = await database.query(
      'todos',
      where: 'userid = ? AND is_deleted = 0 AND LOWER(title) LIKE ?',
      whereArgs: [userId, searchPattern],
      limit: 10,
    );

    final appointmentMaps = await database.query(
      'appointments',
      where: 'userid = ? AND is_deleted = 0 AND LOWER(title) LIKE ?',
      whereArgs: [userId, searchPattern],
      limit: 10,
    );

    final habitMaps = await database.query(
      'habits',
      where: 'userid = ? AND is_deleted = 0 AND LOWER(name) LIKE ?',
      whereArgs: [userId, searchPattern],
      limit: 10,
    );

    final inventoryMaps = await database.query(
      'inventory_items',
      where: 'userid = ? AND is_deleted = 0 AND (LOWER(name) LIKE ? OR LOWER(brand) LIKE ? OR LOWER(location) LIKE ? '
          'OR LOWER(color) LIKE ? OR LOWER(category) LIKE ?)',
      whereArgs: [userId, searchPattern, searchPattern, searchPattern, searchPattern, searchPattern],
      limit: 10,
    );

    final journal = (await JournalRepository(db: db).getEntries(userId, search: query)).take(10).toList();

    final contacts = (await ContactRepository(db: db).getContacts(userId, search: query)).take(10).toList();

    return {
      'contacts': contacts,
      'journal': journal,
      'inventory': inventoryMaps.map(InventoryItem.fromMap).toList(),
      'transactions': tMaps.map((m) => tr.Transaction.fromMap(m)).toList(),
      'todos': todoMaps.map((m) => Todo.fromMap(m)).toList(),
      'appointments': appointmentMaps.map((m) => Appointment.fromMap(m)).toList(),
      'habits': habitMaps.map((m) => Habit.fromMap(m)).toList(),
    };
  }
}
