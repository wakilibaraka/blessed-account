import 'sign_in_result.dart';

/// The signed-in user, independent of the Firebase SDK types.
class AccountUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  /// Sign-in providers linked to the account, e.g. `google.com`, `apple.com`.
  final List<String> providerIds;

  const AccountUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.providerIds = const [],
  });
}

/// The user dismissed a sign-in or re-authentication prompt.
class SignInCancelledException implements Exception {
  const SignInCancelledException();
  @override
  String toString() => 'Sign-in was cancelled.';
}

/// A sign-in or re-authentication failed for [failure] (raw [code]).
class SignInFailedException implements Exception {
  final SignInFailure failure;
  final String? code;
  const SignInFailedException(this.failure, [this.code]);
  @override
  String toString() => 'Sign-in failed: ${failure.name} (${code ?? '-'})';
}

/// Everything [AccountService] needs from the auth providers. The real
/// implementation is [FirebaseAuthGateway]; tests use a fake.
///
/// Sign-in and re-authentication methods throw [SignInCancelledException]
/// or [SignInFailedException]; nothing else escapes them.
abstract interface class AuthGateway {
  Stream<AccountUser?> authStateChanges();
  AccountUser? get currentUser;

  /// Whether Sign in with Apple can run on this device.
  bool get isAppleSignInAvailable;

  Future<void> signInWithGoogle();
  Future<void> signInWithApple();

  /// Re-prompts with the provider the current user signed in with. Needed
  /// before sensitive operations such as deleting the account.
  Future<void> reauthenticate();

  /// Signs out of Firebase and the provider's own session.
  Future<void> signOut();

  /// Deletes the Firebase Auth user. Call [reauthenticate] first.
  Future<void> deleteCurrentUser();
}
