import 'package:flutter/material.dart';
import 'package:frontend/features/auth/screens/wrapper.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/profile/screens/profile_screen.dart';
import 'package:frontend/core/ui/theme.dart';

/// App-Bar der Unterseiten. Profil-Button erscheint nur, wenn [user] gesetzt ist.
class ModernAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final UserModel? user;
  final bool showLogout;
  final List<Widget>? customActions;
  final ValueChanged<UserModel>? onUserUpdated;

  const ModernAppBar({
    super.key,
    required this.title,
    this.user,
    this.showLogout = false,
    this.customActions,
    this.onUserUpdated,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      title: Text(title, style: theme.appBarTheme.titleTextStyle),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: AppTheme.divider(context)),
      ),
      actions: [
        if (user != null)
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Profil',
            onPressed: () async {
              final updatedUser = await Navigator.push<UserModel>(
                context,
                MaterialPageRoute(builder: (_) => ProfilePage(user: user!)),
              );
              if (updatedUser != null) onUserUpdated?.call(updatedUser);
            },
          ),
        ...?customActions,
        if (showLogout)
          IconButton(
            icon: const Icon(Icons.exit_to_app_outlined),
            tooltip: 'Abmelden',
            onPressed: () => Wrapper.signOut(context),
          ),
      ],
    );
  }
}
