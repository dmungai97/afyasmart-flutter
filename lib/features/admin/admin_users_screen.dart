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
            decoration: InputDecoration(
              hintText: 'Search users by name, email, or phone...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _search.clear()),
                    )
                  : null,
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const AdminEmpty(message: 'No users match that search.')
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
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.ink.withValues(alpha: 0.08),
                child: Text(
                  u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.rule),
          const SizedBox(height: 6),
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
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
    final canChangeRole = viewer?.role == UserRole.superAdmin;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => _UserEditDialog(
        user: user,
        canChangeRole: canChangeRole,
      ),
    );

    if (result == null) return;

    final newName = result['name'] as String?;
    final role = result['role'] as String?;
    final subscribed = result['subscribed'] as bool?;
    final plan = result['plan'] as String?;

    try {
      await ref
          .read(adminServiceProvider)
          .updateUser(
            userId: user.id,
            name: newName == null || newName.isEmpty ? null : newName,
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

class _UserEditDialog extends StatefulWidget {
  const _UserEditDialog({required this.user, required this.canChangeRole});

  final AdminUserRow user;
  final bool canChangeRole;

  @override
  State<_UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<_UserEditDialog> {
  late final TextEditingController _nameController;
  late String _role;
  late bool _subscribed;
  late String _plan;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _role = widget.user.role;
    _subscribed = widget.user.subscribed;
    _plan = widget.user.plan;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text(
        widget.user.name,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 14),
            if (widget.canChangeRole)
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.security, size: 18),
                ),
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('User')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(
                    value: 'super_admin',
                    child: Text('Super admin'),
                  ),
                ],
                onChanged: (v) => setState(() => _role = v ?? _role),
              )
            else
              Text(
                'Role: ${widget.user.role} — only a super admin can change this.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                ),
              ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _subscribed,
              activeThumbColor: AppColors.ink,
              title: const Text(
                'Subscribed',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              onChanged: (v) => setState(() => _subscribed = v),
            ),
            DropdownButtonFormField<String>(
              value: _plan,
              decoration: const InputDecoration(
                labelText: 'Plan',
                prefixIcon: Icon(Icons.card_membership, size: 18),
              ),
              items: const [
                DropdownMenuItem(value: 'free', child: Text('Free')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              ],
              onChanged: (v) => setState(() => _plan = v ?? _plan),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              'name': _nameController.text.trim(),
              'role': _role,
              'subscribed': _subscribed,
              'plan': _plan,
            });
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ink,
            foregroundColor: AppColors.paper,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
