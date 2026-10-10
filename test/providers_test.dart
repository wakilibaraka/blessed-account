import 'package:blessed_account/blessed_account.dart';
import 'package:blessed_account/testing.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('providers work with overridden gateway and Firestore', () async {
    final gateway = FakeAuthGateway();
    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(gateway),
      accountFirestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
    ]);
    addTearDown(container.dispose);

    // Riverpod 3 pauses providers nobody listens to.
    container.listen(accountUserProvider, (_, __) {});
    container.listen(sharedProfileProvider, (_, __) {});

    expect(container.read(appleSignInAvailableProvider), isFalse);
    expect(await container.read(accountUserProvider.future), isNull);

    final result =
        await container.read(accountServiceProvider).signInWithGoogle();
    expect(result.isSuccess, isTrue);
    await pumpEventQueue();
    expect(container.read(accountUserProvider).value?.uid, 'u1');
    final profile = await container.read(sharedProfileProvider.future);
    expect(profile?.displayName, 'Test User');
  });
}
