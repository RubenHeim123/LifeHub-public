import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/contacts/repositories/contact_repository.dart';
import 'package:frontend/features/inventory/repositories/inventory_repository.dart';
import 'package:frontend/features/todos/repositories/todo_repository.dart';
import 'package:frontend/features/journal/repositories/journal_repository.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/screens/finance_hub_screen.dart';
import 'package:frontend/features/auth/screens/authenticate.dart';
import 'package:frontend/features/dashboard/screens/home.dart';
import 'package:frontend/app/app_tabs.dart';
import 'package:frontend/app/tab_style.dart';
import 'package:frontend/features/fitness/screens/training_screen.dart';
import 'package:frontend/features/food/screens/food_hub_screen.dart';
import 'package:frontend/features/more/more_screen.dart';
import 'package:frontend/features/planning/screens/planning_hub_screen.dart';
import 'package:frontend/features/auth/services/auth.dart';
import 'package:frontend/features/auth/widgets/new_password_dialog.dart';
import 'package:frontend/features/finance/repositories/transaction_repository.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/hub_tabs.dart';
import 'package:frontend/core/ui/theme.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.email});
  final String email;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppTab _tab = AppTab.today;
  UserModel? _user;

  /// Zuletzt gewählter Bereich je Tab (Planen, Essen) – ein Tipp auf den Tab führt dorthin zurück.
  final _sections = <AppTab, Enum>{};

  /// Zählt Sprünge (von Heute oder erneuter Tipp), damit der Hub mit dem neuen Bereich neu aufbaut.
  int _jump = 0;


  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final auth = context.read<AuthService>();
    final transactions = context.read<TransactionRepository>();
    final appointments = context.read<AppointmentRepository>();
    final todos = context.read<TodoRepository>();
    final inventory = context.read<InventoryRepository>();
    final journal = context.read<JournalRepository>();
    final contacts = context.read<ContactRepository>();
    try {
      final user = await auth.getCurrentUser(widget.email);
      // Einzige Stelle, an der fällige Fixkosten gebucht werden – vor dem ersten Screen,
      // damit alle Ansichten schon die aktuellen Salden sehen.
      try {
        await transactions.bookDueFixedTransactions(user.uid);
      } catch (e) {
        debugPrint('Fixkosten konnten nicht gebucht werden: $e');
      }
      // Erinnerungen dieses Nutzers (neu) planen – nach einem Abmelden sind alle entfernt,
      // jährliche (Geburtstage …) brauchen das nächste Jahr. Im Hintergrund.
      Future.wait([
        appointments.refreshReminders(user.uid),
        todos.refreshReminders(user.uid),
        inventory.refreshReminders(user.uid),
        journal.refreshReminder(user.uid),
        contacts.refreshReminders(user.uid),
      ]).catchError((Object e) {
        debugPrint('Erinnerungen: $e');
        return const <void>[];
      });
      if (!mounted) return;
      setState(() => _user = user);
      if (auth.needsNewPassword(user)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showNewPasswordDialog(context, auth: auth, user: user);
        });
      }
    } catch (error) {
      debugPrint('Error loading user: $error');
      await auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Authenticate()),
          (route) => false,
        );
      }
    }
  }

  /// Sprung von Heute in einen Tab, optional direkt in einen Bereich.
  void _open(AppTab tab, [Enum? section]) => setState(() {
        _tab = tab;
        if (section != null) _sections[tab] = section;
        _jump++;
      });

  /// Tipp in der Leiste: zurück zum zuletzt gewählten Bereich; auf den aktiven Tab → erster Bereich.
  void _tapTab(AppTab tab) => setState(() {
        if (tab == _tab) {
          _sections.remove(tab);
          _jump++;
        }
        _tab = tab;
      });

  Widget _screen() {
    final user = _user!;
    return switch (_tab) {
      AppTab.today => Home(user: user, onTabNav: _open),
      AppTab.plan => PlanningHubScreen(
          user: user,
          initialSection: _sections[AppTab.plan] as PlanSection? ?? PlanSection.todos,
          onSectionChanged: (s) => _sections[AppTab.plan] = s,
        ),
      AppTab.food => FoodHubScreen(
          user: user,
          initialSection: _sections[AppTab.food] as FoodSection? ?? FoodSection.nutrition,
          onSectionChanged: (s) => _sections[AppTab.food] = s,
        ),
      AppTab.training => TabPage(
          title: AppTab.training.style.label,
          icon: AppTab.training.style.activeIcon,
          color: AppTab.training.style.toneOf(context),
          child: TrainingScreen(user: user),
        ),
      AppTab.money => FinanceHubScreen(user: user),
      AppTab.more => MoreScreen(user: user),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (_user == null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: c.accent),
            const SizedBox(height: 16),
            Text('Lade Daten …', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: NavBarInset(
        height: NavBarInset.heightFor(context),
        child: KeyedSubtree(key: ValueKey((_tab, _jump)), child: _screen()),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, kNavBarMargin),
        child: FrostedPill(
          height: kNavBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            for (final tab in AppTab.values)
              Expanded(child: _NavButton(item: tab.style, active: tab == _tab, onTap: () => _tapTab(tab))),
          ]),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final TabStyle item;
  final bool active;
  final VoidCallback onTap;
  const _NavButton({required this.item, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: 48,
            height: 30,
            decoration: BoxDecoration(color: active ? item.pill(dark: dark) : Colors.transparent, borderRadius: BorderRadius.circular(15)),
            child: Icon(active ? item.activeIcon : item.icon, size: 22, color: active ? item.onPill(dark: dark) : c.muted),
          ),
          const SizedBox(height: 3),
          // Gleich breite Plätze: lange Wörter („Training“) werden bei großer Schrift verkleinert statt umbrochen
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(item.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? c.text : c.muted,
                )),
          ),
        ]),
      ),
    );
  }
}
