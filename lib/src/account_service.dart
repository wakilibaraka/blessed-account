import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_gateway.dart';
import 'cloud_layout.dart';
import 'shared_profile.dart';
import 'sign_in_result.dart';

/// Sign-in, sign-out and account deletion shared by both apps.
class AccountService {
  final AuthGateway _gateway;
  final FirebaseFirestore _db;
  final SharedProfileRepository profiles;

  AccountService(this._gateway, this._db)
      : profiles = SharedProfileRepository(_db);

  Stream<AccountUser?> authStateChanges() => _gateway.authStateChanges();
  AccountUser? get currentUser => _gateway.currentUser;
  bool get isAppleSignInAvailable => _gateway.isAppleSignInAvailable;

  Future<SignInResult> signInWithGoogle() => _signIn(_gateway.signInWithGoogle);

  Future<SignInResult> signInWithApple() => _signIn(_gateway.signInWithApple);

  Future<void> signOut() => _gateway.signOut();

  /// Permanently deletes the account and **both apps'** cloud data, then
  /// runs [clearLocalData] so the calling app can wipe what it keeps on
  /// the device.
  ///
  /// Re-authenticates first. Throws [SignInCancelledException] if the user
  /// dismisses that prompt (nothing is deleted) and [SignInFailedException]
  /// if it fails.
  Future<void> deleteAccount({Future<void> Function()? clearLocalData}) async {
    final user = _gateway.currentUser;
    if (user == null) return;
    await _gateway.reauthenticate();
    await deleteCloudData(user.uid);
    await _gateway.deleteCurrentUser();
    await clearLocalData?.call();
    await _gateway.signOut();
  }

  /// Deletes every document in every [CloudLayout.allUserCollections]
  /// subcollection of `users/{uid}`, then the profile document itself.
  /// Documents in those subcollections must not have subcollections of their
  /// own: the client SDK can't delete recursively.
  Future<void> deleteCloudData(String uid, {int pageSize = 300}) async {
    final userDoc = _db.collection(CloudLayout.users).doc(uid);
    for (final name in CloudLayout.allUserCollections) {
      final collection = userDoc.collection(name);
      while (true) {
        final page = await collection.limit(pageSize).get();
        if (page.docs.isEmpty) break;
        final batch = _db.batch();
        for (final doc in page.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }
    await userDoc.delete();
  }

  Future<SignInResult> _signIn(Future<void> Function() signIn) async {
    try {
      await signIn();
    } on SignInCancelledException {
      return const SignInResult.cancelled();
    } on SignInFailedException catch (e) {
      return SignInResult.failed(e.failure, e.code);
    }
    final user = _gateway.currentUser;
    if (user != null) {
      try {
        await profiles.ensureExists(user);
      } catch (_) {
        // Signed in regardless; the profile is retried on the next sign-in.
      }
    }
    return const SignInResult.success();
  }
}
