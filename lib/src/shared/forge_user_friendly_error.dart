import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../features/auth/domain/auth_failure.dart';

/// Short, non-technical copy for SnackBars, banners, and inline error text.
String forgeUserFriendlyMessage(Object error, {int maxLength = 320}) {
  if (error is AuthFailure) {
    return _truncate(error.message, maxLength);
  }
  if (error is FirebaseException) {
    return _truncate(_firebaseExceptionMessage(error), maxLength);
  }
  if (error is FirebaseAuthException) {
    return _truncate(_firebaseAuthExceptionMessage(error), maxLength);
  }
  if (error is FirebaseFunctionsException) {
    return _truncate(_firebaseFunctionsExceptionMessage(error), maxLength);
  }
  if (error is PlatformException) {
    return _truncate(_platformExceptionMessage(error), maxLength);
  }
  if (error is GoogleSignInException) {
    return _truncate(_googleSignInExceptionMessage(error), maxLength);
  }
  if (error is TimeoutException) {
    return _truncate(
      'That took too long. Check your connection and try again.',
      maxLength,
    );
  }
  if (error is FormatException) {
    final detail = error.message.trim();
    if (detail.isEmpty) {
      return _truncate("That data couldn't be read. Try again.", maxLength);
    }
    return _truncate("That data couldn't be read: $detail", maxLength);
  }

  var text = error.toString().trim();
  if (text.isEmpty) {
    return 'Something went wrong. Please try again.';
  }
  text = _stripDartStack(text);
  text = _heuristicPlainEnglish(text);
  text = _stripExceptionPrefix(text);
  return _truncate(text, maxLength);
}

/// Whether a remote/GitHub Actions style failure likely means a workflow file is missing.
bool forgeErrorLooksLikeMissingGithubWorkflow(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('404') ||
      text.contains('not found') ||
      text.contains('workflow');
}

String _firebaseExceptionMessage(FirebaseException e) {
  switch (e.code) {
    case 'permission-denied':
      return "You don't have permission for that. Check the account you're signed in with.";
    case 'unavailable':
      return 'The service is busy. Wait a moment and try again.';
    case 'not-found':
      return "We couldn't find that. It may have been removed or you may not have access.";
    case 'already-exists':
      return 'That already exists. Try a different name or open the existing item.';
    case 'failed-precondition':
      final msg = e.message?.trim();
      if (msg != null && msg.isNotEmpty) return msg;
      return "That couldn't run right now. Refresh and try again.";
    case 'resource-exhausted':
      return "You've hit a temporary limit. Try again in a little while.";
    case 'unauthenticated':
      return 'Your session expired. Sign in again, then retry.';
    case 'deadline-exceeded':
      return 'The request timed out. Check your connection and try again.';
    case 'cancelled':
      return 'That was cancelled.';
    default:
      final msg = e.message?.trim();
      if (msg != null && msg.isNotEmpty && !_looksLikeDeveloperNoise(msg)) {
        return msg;
      }
      return 'Something went wrong on the server. Try again in a moment.';
  }
}

String _firebaseAuthExceptionMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'invalid-email':
      return 'That email address does not look valid.';
    case 'wrong-password':
    case 'invalid-credential':
      return 'Email or password is incorrect.';
    case 'user-disabled':
      return 'This account has been disabled. Contact support if you need help.';
    case 'user-not-found':
      return 'No account exists for that email.';
    case 'email-already-in-use':
      return 'That email is already registered. Try signing in instead.';
    case 'weak-password':
      return 'Choose a stronger password (at least 8 characters).';
    case 'too-many-requests':
      return 'Too many attempts. Wait a bit and try again.';
    case 'network-request-failed':
      return "We couldn't reach the sign-in service. Check your connection.";
    case 'operation-not-allowed':
      return 'That sign-in method is not enabled for this app.';
    case 'requires-recent-login':
      return 'For security, sign in again before doing that.';
    default:
      final msg = e.message?.trim();
      if (msg != null && msg.isNotEmpty) return msg;
      return 'Sign-in failed. Try again.';
  }
}

String _firebaseFunctionsExceptionMessage(FirebaseFunctionsException e) {
  switch (e.code) {
    case 'unauthenticated':
      return 'You need to be signed in to do that.';
    case 'permission-denied':
      return "You don't have permission to run that action.";
    case 'not-found':
      return "That feature or resource wasn't found. It may not be set up yet.";
    case 'failed-precondition':
    case 'invalid-argument':
      final msg = e.message?.trim();
      if (msg != null && msg.isNotEmpty) return msg;
      return "That request wasn't valid. Check your input and try again.";
    case 'resource-exhausted':
    case 'aborted':
      return 'The service is busy or rate-limited. Try again shortly.';
    case 'unavailable':
    case 'deadline-exceeded':
      return 'The cloud service timed out or was unavailable. Try again.';
    case 'internal':
      return 'Something went wrong on the server. Try again in a moment.';
    default:
      final msg = e.message?.trim();
      if (msg != null && msg.isNotEmpty && !_looksLikeDeveloperNoise(msg)) {
        return msg;
      }
      return 'Could not complete that request. Try again.';
  }
}

String _googleSignInExceptionMessage(GoogleSignInException e) {
  if (e.code == GoogleSignInExceptionCode.canceled ||
      e.code == GoogleSignInExceptionCode.interrupted ||
      e.code == GoogleSignInExceptionCode.uiUnavailable) {
    return 'Google sign-in was cancelled.';
  }
  final detail = e.description?.trim();
  if (detail != null && detail.isNotEmpty) return detail;
  return 'Google sign-in failed. Try again.';
}

String _platformExceptionMessage(PlatformException e) {
  final code = e.code.toLowerCase();
  if (code.contains('network') ||
      code.contains('connection') ||
      code.contains('ioexception')) {
    return "We couldn't reach the network. Check your connection and try again.";
  }
  if (code.contains('permission') || code.contains('denied')) {
    return "Permission was denied. Enable it in Settings if you want to use this feature.";
  }
  final msg = e.message?.trim();
  if (msg != null && msg.isNotEmpty) return msg;
  return 'Something went wrong. Try again.';
}

String _stripDartStack(String text) {
  final stackIndex = text.indexOf('\n#0');
  if (stackIndex > 0) {
    return text.substring(0, stackIndex).trim();
  }
  return text;
}

String _stripExceptionPrefix(String text) {
  const prefixes = [
    'Exception: ',
    'Error: ',
    '_Exception: ',
  ];
  for (final p in prefixes) {
    if (text.startsWith(p)) {
      return text.substring(p.length).trim();
    }
  }
  return text;
}

String _heuristicPlainEnglish(String text) {
  if (text.contains('Remote provider error (404)')) {
    return 'That workflow was not found in this repository. Install run-app.yml first, then try again.';
  }
  final lower = text.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('network is unreachable')) {
    return "We couldn't reach the server. Check your internet connection and try again.";
  }
  if (lower.contains('handshakeexception') ||
      lower.contains('certificate')) {
    return 'A secure connection could not be made. Check your network or try again later.';
  }
  return text;
}

bool _looksLikeDeveloperNoise(String message) {
  final lower = message.toLowerCase();
  return lower.contains('firebaseerror') ||
      lower.contains('firebase_functions') ||
      lower.startsWith('platformexception') ||
      lower.startsWith('type ') && lower.contains('is not a subtype');
}

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}…';
}
