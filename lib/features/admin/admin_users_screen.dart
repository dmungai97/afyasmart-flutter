import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
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
              hintText: 'Search name, email or phone',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _search.text.isEmpty
                  ? '${rows.length}${_hasMore ? '+' : ''} '
                        'user${rows.length == 1 ? '' : 's'}'
                  : '${rows.length} '
                        'match${rows.length == 1 ? '' : 'es'}',
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const AdminEmpty(message: 'No users match that search.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
          : OutlinedButton(onPressed: _load, child: const Text('Load more')),
    ),
  );

  /// One compact row per user on the paper, separated by a rule, the whole
  /// row opening the editor. Each user used to be a full card with a
  /// divider and a small faint "Edit" link, so about six fitted on a phone.
  Widget _row(AdminUserRow u) => InkWell(
    onTap: () => _edit(u),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.ink.withValues(alpha: 0.08),
            child: Text(
              u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U',
              style: const TextStyle(
                fontSize: 15,
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
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  u.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                  ),
                ),
                Text(
                  'Joined ${formatWhen(u.createdAt)}'
                  '${u.phone.isEmpty ? '' : ' · ${u.phone}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Stacked, so a "super admin" and an "expired" pill no longer
          // squeeze the name between them.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
              if (u.role != 'user') ...[
                const SizedBox(height: 4),
                StatusPill(
                  label: u.role.replaceAll('_', ' '),
                  tone: StatusTone.warning,
                ),
              ],
            ],
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right,
            color: AppColors.inkMuted,
            semanticLabel: 'Edit',
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
      builder: (dialogContext) =>
          _UserEditDialog(user: user, canChangeRole: canChangeRole),
    );

    if (result == null) return;

    final newName = result['name'] as String?;
    final role = result['role'] as String?;
    final plan = result['plan'] as String;

    // Access is one choice: Free, or a paid plan that starts now. Granting a
    // plan used to keep the old expiry date, so for anyone whose plan had
    // lapsed the grant was already expired the moment it was saved.
    final planChanged = plan != _UserEditDialog.currentPlan(user);

    try {
      await ref
          .read(adminServiceProvider)
          .updateUser(
            userId: user.id,
            name: newName == null || newName.isEmpty || newName == user.name
                ? null
                : newName,
            role: canChangeRole && role != user.role ? role : null,
            isSubscribed: planChanged ? plan != 'free' : null,
            plan: planChanged ? plan : null,
            expiresAt: planChanged && plan != 'free'
                ? _UserEditDialog.endsAt(plan, DateTime.now())
                : null,
          );
      await _load(reset: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('User updated.')));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }
}

class _UserEditDialog extends StatefulWidget {
  const _UserEditDialog({required this.user, required this.canChangeRole});

  final AdminUserRow user;
  final bool canChangeRole;

  /// The plan the user has right now: a lapsed plan counts as Free.
  static String currentPlan(AdminUserRow u) =>
      u.subscribed && u.plan != 'free' ? u.plan : 'free';

  /// When a plan granted at [from] ends. Mirrors subscription_expiry() in
  /// the database: a month, 7 days, or a day.
  static DateTime endsAt(String plan, DateTime from) => switch (plan) {
    'monthly' => DateTime(
      from.year,
      from.month + 1,
      from.day,
      from.hour,
      from.minute,
    ),
    'weekly' => from.add(const Duration(days: 7)),
    _ => from.add(const Duration(days: 1)),
  };

  @override
  State<_UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<_UserEditDialog> {
  late final TextEditingController _nameController;
  late String _role;
  late String _plan;

  static const _planLabels = {
    'free': 'Free (no subscription)',
    'daily': 'Daily · Ksh 20',
    'weekly': 'Weekly · Ksh 100',
    'monthly': 'Monthly · Ksh 200',
  };

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _role = widget.user.role;
    _plan = _UserEditDialog.currentPlan(widget.user);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static String _date(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// One line under the plan saying what saving will do, so nobody has to
  /// guess whether a grant starts now or what happened to a lapsed plan.
  String _planNote() {
    final u = widget.user;
    final current = _UserEditDialog.currentPlan(u);
    if (_plan != current) {
      return _plan == 'free'
          ? 'Access ends when you save.'
          : 'Starts when you save and ends '
                '${_date(_UserEditDialog.endsAt(_plan, DateTime.now()))}.';
    }
    if (current != 'free' && u.expiresAt != null) {
      return 'Active until ${_date(u.expiresAt!)}.';
    }
    if (u.isExpired && u.plan != 'free') {
      return 'Their ${u.plan} plan ended ${_date(u.expiresAt!)}.';
    }
    return 'No active subscription.';
  }

  static String _roleName(String role) => switch (role) {
    'super_admin' => 'Super admin',
    'admin' => 'Admin',
    _ => 'User',
  };

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final contact = [u.email, if (u.phone.isNotEmpty) u.phone].join(' · ');

    // Nearly full width on a phone, capped on wide screens. The default
    // AlertDialog left about 200px for the form.
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Edit user',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                contact,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.inkMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              _label('Name'),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              _label('Role'),
              if (widget.canChangeRole)
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  style: const TextStyle(fontSize: 16, color: AppColors.ink),
                  items: [
                    for (final r in const ['user', 'admin', 'super_admin'])
                      DropdownMenuItem(value: r, child: Text(_roleName(r))),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? _role),
                )
              else
                Text(
                  '${_roleName(u.role)}. Only a super admin can change roles.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.inkMuted,
                  ),
                ),
              const SizedBox(height: 16),
              _label('Plan'),
              // One choice instead of a "Subscribed" switch plus a plan
              // dropdown that could contradict each other.
              DropdownButtonFormField<String>(
                initialValue: _plan,
                style: const TextStyle(fontSize: 16, color: AppColors.ink),
                items: [
                  for (final e in _planLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _plan = v ?? _plan),
              ),
              const SizedBox(height: 6),
              Text(
                _planNote(),
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, {
                        'name': _nameController.text.trim(),
                        'role': _role,
                        'plan': _plan,
                      }),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
