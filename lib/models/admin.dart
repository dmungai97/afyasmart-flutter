/// Admin console models, ported from the types in admin/services/admin.service.ts.
library;

const _planAmounts = {'daily': 20.0, 'weekly': 100.0, 'monthly': 200.0};

/// A payment's effective value.
///
/// Falls back to the plan's list price when the stored amount is missing or
/// zero — some legacy rows were written without it, and treating those as
/// Ksh 0 would understate revenue on the dashboard.
double paymentAmount(Map<String, dynamic> row) {
  final direct = (row['amount'] as num?)?.toDouble();
  if (direct != null && direct > 0) return direct;
  return _planAmounts[row['plan']] ?? 0;
}

DateTime? parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

bool isActiveSubscription(Map<String, dynamic> row) {
  if (row['is_subscribed'] != true) return false;
  final expires = parseDate(row['subscription_expires_at']);
  return expires == null || expires.isAfter(DateTime.now());
}

class AdminMetrics {
  const AdminMetrics({
    this.totalUsers = 0,
    this.activeUsers = 0,
    this.subscriptions = 0,
    this.doctors = 0,
    this.pharmacies = 0,
    this.drugs = 0,
    this.totalRevenue = 0,
    this.pendingPayouts = 0,
    this.pendingPayoutsValue = 0,
    this.daily = 0,
    this.weekly = 0,
    this.monthly = 0,
  });

  final int totalUsers;
  final int activeUsers;
  final int subscriptions;
  final int doctors;
  final int pharmacies;
  final int drugs;
  final double totalRevenue;
  final int pendingPayouts;
  final double pendingPayoutsValue;
  final int daily;
  final int weekly;
  final int monthly;

  int get totalFacilities => doctors + pharmacies;

  double get conversionRate => totalUsers == 0
      ? 0
      : double.parse(((activeUsers / totalUsers) * 100).toStringAsFixed(1));
}

class AdminTransaction {
  const AdminTransaction({
    required this.id,
    required this.name,
    required this.type,
    required this.amount,
    required this.status,
    required this.at,
  });

  final String id;
  final String name;
  final String type;
  final double amount;
  final String status;
  final DateTime? at;
}

class AdminRecentUser {
  const AdminRecentUser({
    required this.id,
    required this.name,
    required this.email,
    required this.plan,
    required this.subscribed,
  });

  final String id;
  final String name;
  final String email;
  final String plan;
  final bool subscribed;
}

class AdminDashboard {
  const AdminDashboard({
    this.metrics = const AdminMetrics(),
    this.recentUsers = const [],
    this.recentTransactions = const [],
    this.weeklyRevenue = const [0, 0, 0, 0, 0, 0, 0],
    this.weeklySubscribers = const [0, 0, 0, 0, 0, 0, 0],
  });

  final AdminMetrics metrics;
  final List<AdminRecentUser> recentUsers;
  final List<AdminTransaction> recentTransactions;

  /// Monday-first, seven entries.
  final List<double> weeklyRevenue;
  final List<int> weeklySubscribers;
}

class AdminUserRow {
  const AdminUserRow({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.plan,
    required this.subscribed,
    required this.hasSubscribed,
    required this.expiresAt,
    required this.onboardingCompleted,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String plan;
  final bool subscribed;
  final bool hasSubscribed;
  final DateTime? expiresAt;
  final bool onboardingCompleted;
  final DateTime? createdAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory AdminUserRow.fromRow(Map<String, dynamic> row) => AdminUserRow(
    id: row['id'] as String,
    name: (row['name'] as String?)?.trim().isNotEmpty == true
        ? row['name'] as String
        : 'AfyaSmart User',
    email: row['email'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    role: row['role'] as String? ?? 'user',
    plan: row['subscription_plan'] as String? ?? 'free',
    subscribed: isActiveSubscription(row),
    hasSubscribed: row['has_subscribed'] as bool? ?? false,
    expiresAt: parseDate(row['subscription_expires_at']),
    onboardingCompleted: row['onboarding_completed'] as bool? ?? false,
    createdAt: parseDate(row['created_at']),
  );
}

enum FacilityKind { doctor, pharmacy }

class AdminFacility {
  const AdminFacility({
    required this.id,
    required this.kind,
    required this.name,
    required this.location,
    required this.phone,
    required this.email,
    this.specialization,
    this.hospital,
    this.rating,
    this.available,
    this.experienceYears,
    this.address,
    this.openingHours,
    this.open24hrs,
    this.open,
  });

  final int id;
  final FacilityKind kind;
  final String name;
  final String location;
  final String phone;
  final String email;

  // Doctor only.
  final String? specialization;
  final String? hospital;
  final double? rating;
  final bool? available;
  final int? experienceYears;

  // Pharmacy only.
  final String? address;
  final String? openingHours;
  final bool? open24hrs;
  final bool? open;

  factory AdminFacility.doctor(Map<String, dynamic> row) => AdminFacility(
    id: (row['id'] as num).toInt(),
    kind: FacilityKind.doctor,
    name: row['name'] as String? ?? 'Unknown Doctor',
    location: row['location'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    email: row['email'] as String? ?? '',
    specialization: row['specialization'] as String? ?? '',
    hospital: row['hospital'] as String? ?? '',
    rating: (row['rating'] as num?)?.toDouble() ?? 0,
    available: row['available'] as bool? ?? false,
    experienceYears: (row['experience_years'] as num?)?.toInt() ?? 0,
  );

  factory AdminFacility.pharmacy(Map<String, dynamic> row) => AdminFacility(
    id: (row['id'] as num).toInt(),
    kind: FacilityKind.pharmacy,
    name: row['name'] as String? ?? 'Unknown Pharmacy',
    location: row['location'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    email: row['email'] as String? ?? '',
    address: row['address'] as String? ?? '',
    openingHours: row['opening_hours'] as String? ?? '',
    open24hrs: row['open_24hrs'] as bool? ?? false,
    open: row['open'] as bool? ?? false,
  );
}

class AdminPayment {
  const AdminPayment({
    required this.id,
    required this.phone,
    required this.userId,
    required this.plan,
    required this.amount,
    required this.status,
    required this.paid,
    required this.createdAt,
    required this.paidAt,
  });

  final String id;
  final String phone;
  final String userId;
  final String plan;
  final double amount;
  final String status;
  final bool paid;
  final DateTime? createdAt;
  final DateTime? paidAt;

  factory AdminPayment.fromRow(Map<String, dynamic> row) => AdminPayment(
    id: row['id'] as String,
    phone: row['phone'] as String? ?? row['user_id'] as String? ?? 'Unknown',
    userId: row['user_id'] as String? ?? '',
    plan: row['plan'] as String? ?? 'unknown',
    amount: paymentAmount(row),
    status: row['status'] as String? ?? 'unknown',
    paid: row['paid'] as bool? ?? false,
    createdAt: parseDate(row['created_at']),
    paidAt: parseDate(row['paid_at']),
  );
}

class AdminPayout {
  const AdminPayout({
    required this.id,
    required this.affiliateId,
    required this.phone,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String affiliateId;
  final String phone;
  final double amount;
  final String status;
  final DateTime? createdAt;

  factory AdminPayout.fromRow(Map<String, dynamic> row) => AdminPayout(
    id: row['id'] as String,
    affiliateId: row['affiliate_id'] as String? ?? '',
    phone: row['phone'] as String? ?? '',
    amount: (row['amount'] as num?)?.toDouble() ?? 0,
    status: row['status'] as String? ?? 'pending',
    createdAt: parseDate(row['created_at']),
  );
}

/// A page of rows plus the offset to resume from.
///
/// Firestore paginated with a DocumentSnapshot cursor; Postgres uses a row
/// offset via .range(), so the cursor is just an int.
class AdminPage<T> {
  const AdminPage({required this.items, required this.cursor, required this.hasMore});

  final List<T> items;
  final int? cursor;
  final bool hasMore;
}
