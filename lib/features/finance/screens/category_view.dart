import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/screens/add_update_category.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';

class CategoryView extends StatefulWidget {
  const CategoryView({super.key, required this.user});
  final UserModel user;

  @override
  State<CategoryView> createState() => _CategoryViewState();
}

class _CategoryViewState extends State<CategoryView> {
  AppColors get c => AppColors.of(context);

  late final CategoryRepository _repo = context.read<CategoryRepository>();
  late UserModel _user;

  late Future<List<Category>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _refreshCategories();
  }

  Future<void> _refreshCategories() async {
    setState(() {
      _categoriesFuture = _repo.getAllCategories(_user.uid);
    });
    try {
      await _categoriesFuture;
    } catch (_) {
      // Der FutureBuilder zeigt den Fehler mit „Erneut versuchen“ an
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Category>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        return Scaffold(
          appBar: ModernAppBar(
            title: 'Kategorien',
            user: _user,
            showLogout: true,
            onUserUpdated: (u) => setState(() => _user = u),
          ),
          body: snapshot.hasError
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Laden fehlgeschlagen',
                  message: errorText(snapshot.error!),
                  action: OutlinedButton(onPressed: _refreshCategories, child: const Text('Erneut versuchen')),
                )
              : !snapshot.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : snapshot.data!.isEmpty
                      ? _buildEmptyState(theme)
                      : RefreshIndicator(
                          color: c.accentText,
                          onRefresh: _refreshCategories,
                          child: _buildCategoryList(snapshot.data!, theme),
                        ),
          floatingActionButton: AppFab(label: 'Kategorie', heroTag: 'category-fab', onPressed: () => _open()),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return const EmptyState(
      icon: Icons.category_outlined,
      title: 'Noch keine Kategorien',
      message: 'Kategorien ordnen deine Buchungen, z. B. Lebensmittel oder Gehalt.',
    );
  }

  Widget _buildCategoryList(List<Category> categories, ThemeData theme) {
    final income = categories.where((c) => c.transactionType.isIncome).toList();
    final expense = categories.where((c) => c.transactionType.isExpense).toList();
    return ListView(
      padding: pagePadding(context),
      children: [
        if (income.isNotEmpty) ...[
          _buildSectionHeader('Einnahmen', c.positive, theme),
          const SizedBox(height: 8),
          ...income.map((cat) => _buildCategoryCard(cat, c.positive, theme)),
          const SizedBox(height: 24),
        ],
        if (expense.isNotEmpty) ...[
          _buildSectionHeader('Ausgaben', c.negative, theme),
          const SizedBox(height: 8),
          ...expense.map((cat) => _buildCategoryCard(cat, c.negative, theme)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color, ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 4, height: 20,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 12),
        Text(title, style: theme.textTheme.titleMedium),
      ],
    );
  }

  Widget _buildCategoryCard(Category category, Color color, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwipeTile(
          id: 'category-${category.id}',
          onEdit: () => _open(category),
          onDelete: () => _delete(category),
        child: InkWell(
          onTap: () => _open(category),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.cardDecoration(context),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    IconData(category.categoryCodePoint, fontFamily: category.categoryFontFamily),
                    color: color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category.categoryName, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          category.transactionType.label,
                          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: theme.iconTheme.color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open([Category? category]) async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => AddUpdateCategory(userid: _user.uid, category: category)),
    );
    if (!mounted) return;
    if (result == kDeletedResult && category != null) return _delete(category);
    _refreshCategories();
  }

  Future<void> _delete(Category category) => deleteWithUndo(
        context,
        label: category.categoryName,
        delete: () => _repo.deleteCategory(category.id!),
        restore: () => _repo.restoreCategory(category.id!),
        onChanged: _refreshCategories,
      );
}
