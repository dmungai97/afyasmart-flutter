import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/supabase_client.dart';

/// Port of src/services/mpesa.service.ts.
///
/// There is one backend, and the path shapes ("/mpesa/initiate",
/// "/mpesa/status") are what the edge function already serves, so no path
/// remapping is needed.

class MpesaStatus {
  const MpesaStatus({
    required this.paid,
    required this.status,
    this.message,
    this.checkoutRequestId,
  });

  final bool paid;
  final String status;
  final String? message;
  final String? checkoutRequestId;
}

class MpesaService {
  const MpesaService();

  static const _lastCheckoutKey = 'mpesa_last_checkout_request_id';
  static String _planKey(String id) => 'mpesa_checkout_plan:$id';

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = currentAccessToken;
    final response = await http.post(
      Uri.parse('${SupabaseConfig.resolvedFunctionsBaseUrl}$path'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      // The caller's identity comes from the verified access token alone.
      body: jsonEncode(body),
    );

    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } on FormatException {
      decoded = null;
    }

    if (response.statusCode != 200) {
      throw ApiException(
        decoded?['message'] as String? ?? 'M-Pesa request failed.',
      );
    }

    return decoded ?? const {};
  }

  /// Starts an STK push. The amount is derived from the plan server-side and
  /// never sent, so a client cannot pick its own price.
  Future<String> initiate({required String phone, required String plan}) async {
    final data = await _request('/mpesa/initiate', {
      'phone': phone,
      'plan': plan,
    });

    final checkoutId = data['checkout_request_id'] as String?;
    if (checkoutId == null) {
      throw const ApiException('M-Pesa did not return a checkout id.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCheckoutKey, checkoutId);
    await prefs.setString(_planKey(checkoutId), plan);

    return checkoutId;
  }

  /// Polls for the outcome.
  ///
  /// Subscription activation always happens server-side, verified against the
  /// actual M-Pesa result. A client-side fallback here would let anyone grant
  /// themselves a subscription without paying; the column grants block it
  /// too, but it is intentionally not attempted at all. The caller refreshes
  /// its own profile when this reports paid.
  Future<MpesaStatus> poll(String checkoutRequestId) async {
    final data = await _request('/mpesa/status', {
      'checkout_request_id': checkoutRequestId,
    });

    final paid = data['paid'] as bool? ?? false;

    if (paid) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastCheckoutKey);
      await prefs.remove(_planKey(checkoutRequestId));
    }

    return MpesaStatus(
      paid: paid,
      status: data['status'] as String? ?? 'pending',
      message: data['message'] as String?,
      checkoutRequestId: checkoutRequestId,
    );
  }

  /// Resumes watching a payment the app was killed in the middle of.
  Future<MpesaStatus?> checkLatest() async {
    final prefs = await SharedPreferences.getInstance();
    final checkoutId = prefs.getString(_lastCheckoutKey);
    if (checkoutId == null) return null;
    return poll(checkoutId);
  }
}
