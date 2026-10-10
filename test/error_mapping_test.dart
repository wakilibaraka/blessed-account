import 'package:blessed_account/blessed_account.dart';
import 'package:blessed_account/src/firebase_auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

SignInFailure? failureOf(Exception e) =>
    e is SignInFailedException ? e.failure : null;

void main() {
  test('Google cancel/interrupt are cancellations', () {
    expect(mapGoogleError(GoogleSignInExceptionCode.canceled),
        isA<SignInCancelledException>());
    expect(mapGoogleError(GoogleSignInExceptionCode.interrupted),
        isA<SignInCancelledException>());
  });

  test('Google configuration errors are misconfigured', () {
    expect(
        failureOf(
            mapGoogleError(GoogleSignInExceptionCode.clientConfigurationError)),
        SignInFailure.misconfigured);
    expect(
        failureOf(mapGoogleError(
            GoogleSignInExceptionCode.providerConfigurationError)),
        SignInFailure.misconfigured);
  });

  test('Firebase auth codes map to clear failures', () {
    expect(failureOf(mapFirebaseAuthError('network-request-failed')),
        SignInFailure.network);
    expect(failureOf(mapFirebaseAuthError('operation-not-allowed')),
        SignInFailure.misconfigured);
    expect(
        failureOf(
            mapFirebaseAuthError('account-exists-with-different-credential')),
        SignInFailure.accountExistsWithDifferentProvider);
    expect(failureOf(mapFirebaseAuthError('user-disabled')),
        SignInFailure.userDisabled);
    expect(failureOf(mapFirebaseAuthError('something-new')),
        SignInFailure.unknown);
  });
}
