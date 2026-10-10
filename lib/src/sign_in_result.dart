/// Outcome of a sign-in attempt.
enum SignInStatus { success, cancelled, failed }

/// Why a sign-in failed, so the UI can show something useful.
enum SignInFailure {
  /// No connection, or the request timed out.
  network,

  /// The app or Firebase project isn't set up for this provider (missing
  /// SHA fingerprint, provider disabled in the console, bad client id).
  misconfigured,

  /// The email already belongs to an account that uses another provider.
  accountExistsWithDifferentProvider,

  /// The account was disabled in Firebase.
  userDisabled,

  /// This provider isn't available on this platform (e.g. Apple on Android).
  unsupportedPlatform,

  /// Anything else; see [SignInResult.code].
  unknown,
}

class SignInResult {
  final SignInStatus status;
  final SignInFailure? failure;

  /// The underlying provider or Firebase error code, for logs and support.
  final String? code;

  const SignInResult._(this.status, this.failure, this.code);

  const SignInResult.success() : this._(SignInStatus.success, null, null);
  const SignInResult.cancelled() : this._(SignInStatus.cancelled, null, null);
  const SignInResult.failed(SignInFailure failure, [String? code])
      : this._(SignInStatus.failed, failure, code);

  bool get isSuccess => status == SignInStatus.success;

  /// A short, user-facing explanation for a failed sign-in.
  String get message => switch (failure) {
        null => '',
        SignInFailure.network =>
          'No internet connection. Check your connection and try again.',
        SignInFailure.misconfigured =>
          'Sign-in isn\'t set up correctly for this version of the app.',
        SignInFailure.accountExistsWithDifferentProvider =>
          'This email is already used with a different sign-in method.',
        SignInFailure.userDisabled => 'This account has been disabled.',
        SignInFailure.unsupportedPlatform =>
          'This sign-in method isn\'t available on this device.',
        SignInFailure.unknown => 'Sign-in failed. Please try again.',
      };
}
