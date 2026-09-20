/// Port of the AuthUser type and subscription.model.ts predicates.
///
/// These rules exist in three places now — here, in the edge functions
/// (_shared/subscription.ts) and in SQL (has_active_subscription). That is
/// deliberate: SQL gates row access, the edge functions shape responses, and
/// this drives the UI. They must agree, so if the rule changes, change all
/// three.
library;

enum UserRole { user, admin, superAdmin }

UserRole _roleFrom(Object? value) => switch (value) {
  'admin' => UserRole.admin,
  'super_admin' => UserRole.superAdmin,
  _ => UserRole.user,
};

const freeChatLimit = 5;

/// The plans that count as paid. Used by hasEverSubscribed below.
const _paidPlans = {'daily', 'weekly', 'monthly'};

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.chatCount,
    this.phone,
    this.role = UserRole.user,
    this.isSubscribedFlag = false,
    this.hasSubscribedFlag = false,
    this.onboardingCompleted = false,
    this.subscriptionPlan = 'free',
    this.subscriptionExpiresAt,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final UserRole role;
  final int chatCount;
  final bool onboardingCompleted;
  final String subscriptionPlan;
  final DateTime? subscriptionExpiresAt;

  /// The raw stored flags. Prefer [isSubscribed] / [hasEverSubscribed], which
  /// apply the expiry rules — a stored is_subscribed of true means nothing on
  /// its own once the expiry has passed.
  final bool isSubscribedFlag;
  final bool hasSubscribedFlag;

  factory AppUser.fromRow(Map<String, dynamic> row) {
    final expiresRaw = row['subscription_expires_at'] as String?;
    return AppUser(
      id: row['id'] as String,
      // Postgres returns timestamptz as an ISO string, so the Firestore
      // Timestamp.toDate() handling the RN version needed is gone.
      subscriptionExpiresAt: expiresRaw == null
          ? null
          : DateTime.tryParse(expiresRaw),
      name: (row['name'] as String?)?.trim().isNotEmpty == true
          ? row['name'] as String
          : 'AfyaSmart User',
      email: row['email'] as String? ?? '',
      phone: row['phone'] as String?,
      role: _roleFrom(row['role']),
      isSubscribedFlag: row['is_subscribed'] as bool? ?? false,
      hasSubscribedFlag: row['has_subscribed'] as bool? ?? false,
      onboardingCompleted: row['onboarding_completed'] as bool? ?? false,
      subscriptionPlan: row['subscription_plan'] as String? ?? 'free',
      chatCount: (row['chat_count'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isAdmin => role == UserRole.admin || role == UserRole.superAdmin;

  /// A null expiry with the flag set means "subscribed, no end date".
  bool get isSubscribed {
    if (!isSubscribedFlag) return false;
    final expires = subscriptionExpiresAt;
    if (expires == null) return true;
    return expires.isAfter(DateTime.now());
  }

  /// Whether this account has ever paid — which is what disqualifies it from
  /// the free chat allowance, even after a subscription lapses.
  bool get hasEverSubscribed =>
      hasSubscribedFlag ||
      isSubscribedFlag ||
      subscriptionExpiresAt != null ||
      _paidPlans.contains(subscriptionPlan);

  bool get canUseFreeChats => !isSubscribed && !hasEverSubscribed;

  String get effectivePlan {
    if (!isSubscribed) return 'free';
    return _paidPlans.contains(subscriptionPlan) ? subscriptionPlan : 'monthly';
  }

  int get remainingFreeChats {
    if (isSubscribed) return freeChatLimit;
    if (!canUseFreeChats) return 0;
    final remaining = freeChatLimit - chatCount;
    return remaining < 0 ? 0 : remaining;
  }

  bool get chatLimitReached => !isSubscribed && remainingFreeChats <= 0;

  AppUser copyWith({bool? onboardingCompleted}) => AppUser(
    id: id,
    name: name,
    email: email,
    phone: phone,
    role: role,
    chatCount: chatCount,
    isSubscribedFlag: isSubscribedFlag,
    hasSubscribedFlag: hasSubscribedFlag,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    subscriptionPlan: subscriptionPlan,
    subscriptionExpiresAt: subscriptionExpiresAt,
  );
}
