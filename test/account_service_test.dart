import 'package:blessed_account/blessed_account.dart';
import 'package:blessed_account/testing.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FakeAuthGateway gateway;
  late AccountService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    gateway = FakeAuthGateway(
        nextUser: const AccountUser(uid: 'u1', displayName: ' Ruth '));
    service = AccountService(gateway, db);
  });

  group('sign-in', () {
    test('success creates the shared profile once', () async {
      final result = await service.signInWithGoogle();
      expect(result.isSuccess, isTrue);
      final doc = await db.collection('users').doc('u1').get();
      expect(doc.data()!['displayName'], 'Ruth');

      await db.collection('users').doc('u1').update({'displayName': 'Naomi'});
      await service.signInWithGoogle();
      final again = await db.collection('users').doc('u1').get();
      expect(again.data()!['displayName'], 'Naomi',
          reason: 'an existing profile (e.g. from the other app) is kept');
    });

    test('cancel and failure become results, not exceptions', () async {
      gateway.signInError = const SignInCancelledException();
      expect((await service.signInWithGoogle()).status, SignInStatus.cancelled);

      gateway.signInError = const SignInFailedException(
          SignInFailure.misconfigured, 'google-clientConfigurationError');
      final failed = await service.signInWithGoogle();
      expect(failed.status, SignInStatus.failed);
      expect(failed.failure, SignInFailure.misconfigured);
      expect(failed.code, 'google-clientConfigurationError');
      expect(failed.message, isNotEmpty);
    });
  });

  group('deleteAccount', () {
    Future<void> seed() async {
      final user = db.collection('users').doc('u1');
      await user.set({'displayName': 'Ruth'});
      for (var i = 0; i < 7; i++) {
        await user.collection('plans').doc('p$i').set({'id': 'p$i'});
      }
      await user.collection('notes').doc('n1').set({'text': 'x'});
      await user.collection('arcade').doc('progress').set({'xp': 120});
      await db.collection('users').doc('other').set({'displayName': 'Boaz'});
    }

    test('removes both apps\' data, the user, and local data', () async {
      await seed();
      gateway.user = const AccountUser(uid: 'u1');
      var localCleared = false;

      await service.deleteAccount(clearLocalData: () async {
        localCleared = true;
      });

      final user = db.collection('users').doc('u1');
      expect((await user.get()).exists, isFalse);
      for (final c in CloudLayout.allUserCollections) {
        expect((await user.collection(c).get()).docs, isEmpty, reason: c);
      }
      expect((await db.collection('users').doc('other').get()).exists, isTrue);
      expect(localCleared, isTrue);
      expect(gateway.calls, ['reauth', 'deleteUser', 'signOut']);
    });

    test('pages through large collections', () async {
      await seed();
      gateway.user = const AccountUser(uid: 'u1');
      await service.deleteCloudData('u1', pageSize: 2);
      expect(
          (await db.collection('users').doc('u1').collection('plans').get())
              .docs,
          isEmpty);
    });

    test('cancelled re-authentication deletes nothing', () async {
      await seed();
      gateway
        ..user = const AccountUser(uid: 'u1')
        ..reauthError = const SignInCancelledException();

      await expectLater(
          service.deleteAccount(), throwsA(isA<SignInCancelledException>()));
      expect((await db.collection('users').doc('u1').get()).exists, isTrue);
      expect(gateway.calls, ['reauth']);
    });
  });

  test('CloudLayout lists both apps\' collections without duplicates', () {
    expect(CloudLayout.allUserCollections, containsAll(['plans', 'arcade']));
    expect(CloudLayout.allUserCollections.toSet().length,
        CloudLayout.allUserCollections.length);
  });
}
