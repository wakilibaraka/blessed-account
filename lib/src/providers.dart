import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_service.dart';
import 'auth_gateway.dart';
import 'firebase_auth_gateway.dart';
import 'shared_profile.dart';

/// The auth gateway. Override in tests with a fake.
final authGatewayProvider =
    Provider<AuthGateway>((ref) => FirebaseAuthGateway());

final accountServiceProvider = Provider<AccountService>((ref) =>
    AccountService(ref.watch(authGatewayProvider), FirebaseFirestore.instance));

/// The signed-in user, or null when signed out.
final accountUserProvider = StreamProvider<AccountUser?>(
    (ref) => ref.watch(accountServiceProvider).authStateChanges());

/// The signed-in user's shared profile (null when signed out or not yet
/// created).
final sharedProfileProvider = StreamProvider<SharedProfile?>((ref) {
  final user = ref.watch(accountUserProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(accountServiceProvider).profiles.watch(user.uid);
});
