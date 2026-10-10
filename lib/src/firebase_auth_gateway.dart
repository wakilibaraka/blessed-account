import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'auth_gateway.dart';
import 'sign_in_result.dart';

/// [AuthGateway] backed by Firebase Auth, google_sign_in 7 and
/// sign_in_with_apple.
class FirebaseAuthGateway implements AuthGateway {
  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  FirebaseAuthGateway({FirebaseAuth? auth, GoogleSignIn? google})
      : _auth = auth ?? FirebaseAuth.instance,
        _google = google ?? GoogleSignIn.instance;

  /// Call once at startup, after `Firebase.initializeApp`. Pass
  /// [serverClientId] (the OAuth *web* client id) only if Android can't read
  /// it from google-services.json.
  Future<void> initialize({String? serverClientId}) =>
      _google.initialize(serverClientId: serverClientId);

  @override
  Stream<AccountUser?> authStateChanges() =>
      _auth.authStateChanges().map(_toAccountUser);

  @override
  AccountUser? get currentUser => _toAccountUser(_auth.currentUser);

  @override
  bool get isAppleSignInAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Future<void> signInWithGoogle() =>
      _guard(() async => _auth.signInWithCredential(await _googleCredential()));

  @override
  Future<void> signInWithApple() {
    if (!isAppleSignInAvailable) {
      throw const SignInFailedException(SignInFailure.unsupportedPlatform);
    }
    return _guard(
        () async => _auth.signInWithCredential(await _appleCredential()));
  }

  @override
  Future<void> reauthenticate() => _guard(() async {
        final user = _auth.currentUser;
        if (user == null) {
          throw const SignInFailedException(
              SignInFailure.unknown, 'no-current-user');
        }
        final isApple =
            user.providerData.any((p) => p.providerId == 'apple.com');
        await user.reauthenticateWithCredential(
            isApple ? await _appleCredential() : await _googleCredential());
      });

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _google.signOut();
    } catch (_) {
      // Not signed in with Google on this device; nothing to clear.
    }
  }

  @override
  Future<void> deleteCurrentUser() async {
    await _auth.currentUser?.delete();
  }

  Future<AuthCredential> _googleCredential() async {
    final account = await _google.authenticate();
    return GoogleAuthProvider.credential(
        idToken: account.authentication.idToken);
  }

  Future<AuthCredential> _appleCredential() async {
    final apple = await SignInWithApple.getAppleIDCredential(scopes: [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ]);
    return OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      accessToken: apple.authorizationCode,
    );
  }

  /// Runs [action], translating provider errors into the gateway's
  /// [SignInCancelledException] / [SignInFailedException].
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on GoogleSignInException catch (e) {
      throw mapGoogleError(e.code);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const SignInCancelledException();
      }
      throw SignInFailedException(
          SignInFailure.unknown, 'apple-${e.code.name}');
    } on FirebaseAuthException catch (e) {
      throw mapFirebaseAuthError(e.code);
    }
  }

  static AccountUser? _toAccountUser(User? user) => user == null
      ? null
      : AccountUser(
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
          photoUrl: user.photoURL,
          providerIds: [for (final p in user.providerData) p.providerId],
        );
}

/// Maps a google_sign_in failure to a gateway exception.
@visibleForTesting
Exception mapGoogleError(GoogleSignInExceptionCode code) => switch (code) {
      GoogleSignInExceptionCode.canceled ||
      GoogleSignInExceptionCode.interrupted =>
        const SignInCancelledException(),
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        SignInFailedException(
            SignInFailure.misconfigured, 'google-${code.name}'),
      _ => SignInFailedException(SignInFailure.unknown, 'google-${code.name}'),
    };

/// Maps a FirebaseAuthException code to a gateway exception.
@visibleForTesting
Exception mapFirebaseAuthError(String code) => switch (code) {
      'network-request-failed' ||
      'too-many-requests' =>
        SignInFailedException(SignInFailure.network, code),
      'operation-not-allowed' ||
      'invalid-api-key' ||
      'app-not-authorized' ||
      'invalid-credential' =>
        SignInFailedException(SignInFailure.misconfigured, code),
      'account-exists-with-different-credential' => SignInFailedException(
          SignInFailure.accountExistsWithDifferentProvider, code),
      'user-disabled' =>
        SignInFailedException(SignInFailure.userDisabled, code),
      _ => SignInFailedException(SignInFailure.unknown, code),
    };
