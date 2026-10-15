import 'dart:async';

import 'package:http/http.dart' as http;

const offlineMessage =
    'No internet connection. Check your connection and try again.';

/// Text that marks a failure as the network's rather than the backend's.
///
/// Matched against the message as well as checked by type, because the
/// services rewrap Supabase errors as [ApiException] with the original
/// message — an offline sign-in arrives as "ClientException with
/// SocketException: Failed host lookup ...", not as a ClientException.
/// dart:io's SocketException is matched by name for the same reason, and so
/// this file stays importable on web.
const _networkMarkers = [
  'SocketException',
  'ClientException',
  'Failed host lookup',
  'Connection refused',
  'Connection reset',
  'Connection closed',
  'Network is unreachable',
  'HandshakeException',
  'XMLHttpRequest error',
  'Failed to fetch',
];

bool isNetworkError(Object error) {
  if (error is http.ClientException || error is TimeoutException) return true;
  final text = error.toString();
  return _networkMarkers.any(text.contains);
}

/// A message fit to show the user: [offlineMessage] for network failures,
/// otherwise the error's own text.
String errorMessage(Object error) =>
    isNetworkError(error) ? offlineMessage : error.toString();
