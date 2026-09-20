import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/admin.dart';
import '../../models/app_user.dart';
import '../../state/auth_controller.dart';
import '../../state/providers.dart';
import 'widgets/admin_widgets.dart';

/// Port of admin/screens/AdminUsersScreen.tsx.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _search = TextEditingController();

  final _users = <AdminUserRow>[];
  int? _cursor;
  bool _hasMore = true;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      if (reset) _error = null;
    });

    try {
      final page = await ref
          .read(adminServiceProvider)
          .users(cursor: reset ? null : _cursor);

      if (!mounted) return;
      setState(() {
        if (reset) _users.clear();
        _users.addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _error = null;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Client-side filter over the loaded pages. The RN screen did the same —
  /// it is a convenience over what is on screen, not a server search.
  List<AdminUserRow> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users
        .where(
          (u) =>
              u.name.toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q) ||
              u.phone.contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _users.isEmpty) {
      return AdminError(error: _error!, onRetry: () => _load(reset: true));
    }
    if (_loading && _users.isEmpty) return const AdminLoading();

    final rows = _filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Filter loaded users by name, email or phone',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const AdminEmpty(message: 'No users match that filter.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: rows.length + (_hasMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == rows.length) return _loadMore();
                    return _row(rows[i]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _loadMore() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: _loading
          ? const CircularProgressIndicator(color: AppColors.ruleStrong)
          : OutlinedButton(
              onPressed: _load,
              child: const Text('Load more'),
            ),
    ),
  );

  Widget _row(AdminUserRow u) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      u.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (u.role != 'user') ...[
                StatusPill(
                  label: u.role.replaceAll('_', ' '),
                  tone: StatusTone.warning,
                ),
                const SizedBox(width: 6),
              ],
              StatusPill(
                label: u.subscribed
                    ? u.plan
                    : u.isExpired
                    ? 'expired'
                    : 'free',
                tone: u.subscribed
                    ? StatusTone.success
                    : u.isExpired
                    ? StatusTone.danger
                    : StatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Joined ${formatWhen(u.createdAt)}'
                  '${u.phone.isEmpty ? '' : ' · ${u.phone}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkFaint,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _edit(u),
                child: const Text('Edit'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _edit(AdminUserRow user) async {
    final viewer = ref.read(currentUserProvider);
    // Only a super_admin may change a role; admin_update_user enforces this
    // too, but hiding the control avoids offering an action that will fail.
    final canChangeRole = viewer?.role == UserRole.superAdmin;

    final nameController = TextEditingController(text: user.name);
    var role = user.role;
    var subscribed = user.subscribed;
    var plan = user.plan;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(user.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 14),
                if (canChangeRole)
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('User')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(
                        value: 'super_admin',
                        child: Text('Super admin'),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => role = v ?? role),
                  )
                else
                  Text(
                    'Role: ${user.role} — only a super admin can change this.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: subscribed,
                  title: const Text('Subscribed'),
                  onChanged: (v) => setDialogState(() => subscribed = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: plan,
                  decoration: const InputDecoration(labelText: 'Plan'),
                  items: const [
                    DropdownMenuItem(value: 'free', child: Text('Free')),
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  ],
                  onChanged: (v) => setDialogState(() => plan = v ?? plan),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    // Read before disposing — the update below used the controller after it
    // had been torn down.
    final newName = nameController.text.trim();
    nameController.dispose();
    if (saved != true) return;

    try {
      await ref
          .read(adminServiceProvider)
          .updateUser(
            userId: user.id,
            name: newName.isEmpty ? null : newName,
            role: canChangeRole && role != user.role ? role : null,
            isSubscribed: subscribed == user.subscribed ? null : subscribed,
            plan: plan == user.plan ? null : plan,
          );
      await _load(reset: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User updated.')));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
