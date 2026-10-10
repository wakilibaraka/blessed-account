/// Test doubles for apps that use `blessed_account`.
///
/// ```dart
/// ProviderScope(overrides: [
///   authGatewayProvider.overrideWithValue(FakeAuthGateway()),
///   accountFirestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
/// ], child: ...)
/// ```
library;

import 'dart:async';

import 'src/auth_gateway.dart';

/// An in-memory [AuthGateway]. Sign-in signs in as [nextUser]; set
/// [signInError] or [reauthError] to make those calls throw. Every call is
/// recorded in [calls].
class FakeAuthGateway implements AuthGateway {
  AccountUser? _user;
  AccountUser nextUser;
  Exception? signInError;
  Exception? reauthError;
  @override
  bool isAppleSignInAvailable;
  final calls = <String>[];
  final _changes = StreamController<AccountUser?>.broadcast();

  FakeAuthGateway({
    AccountUser? user,
    this.nextUser = const AccountUser(uid: 'u1', displayName: 'Test User'),
    this.isAppleSignInAvailable = false,
  }) : _user = user;

  set user(AccountUser? value) {
    _user = value;
    _changes.add(value);
  }

  @override
  AccountUser? get currentUser => _user;

  @override
  Stream<AccountUser?> authStateChanges() {
    // Subscribe to changes immediately so none are missed between the
    // current value and later updates.
    // ignore: close_sinks (test double: lives as long as the gateway)
    final out = StreamController<AccountUser?>()..add(_user);
    final sub = _changes.stream.listen(out.add);
    out.onCancel = sub.cancel;
    return out.stream;
  }

  Future<void> _signIn(String name) async {
    calls.add(name);
    if (signInError != null) throw signInError!;
    user = nextUser;
  }

  @override
  Future<void> signInWithGoogle() => _signIn('google');
  @override
  Future<void> signInWithApple() => _signIn('apple');

  @override
  Future<void> reauthenticate() async {
    calls.add('reauth');
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    user = null;
  }

  @override
  Future<void> deleteCurrentUser() async => calls.add('deleteUser');
}
