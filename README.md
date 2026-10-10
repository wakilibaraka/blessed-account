# blessed_account

Shared sign-in and account management for **The Blessed Bible** and **Blessed Arcade**. Both apps sign in to the same Firebase project, so one Google (or Apple) account is the same account in both.

## Use it

Pin a release in the app's `pubspec.yaml`, as a tag or a commit SHA (upgrade deliberately by bumping it):

```yaml
dependencies:
  blessed_account:
    git:
      url: https://github.com/wakilibaraka/blessed-account
      ref: v0.1.0 # or a commit SHA, e.g. 1f7b8460fe9c038f5bf08d21be2637cc11cfb8af
```

At startup, after `Firebase.initializeApp`:

```dart
final gateway = FirebaseAuthGateway();
await gateway.initialize();
runApp(ProviderScope(
  overrides: [authGatewayProvider.overrideWithValue(gateway)],
  child: const App(),
));
```

Then:

```dart
final account = ref.read(accountServiceProvider);
final result = await account.signInWithGoogle();
if (!result.isSuccess && result.status == SignInStatus.failed) {
  showError(result.message); // log result.code for support
}

ref.watch(accountUserProvider);   // AccountUser? (null = signed out)
ref.watch(sharedProfileProvider); // SharedProfile? (name + avatar)

await account.deleteAccount(clearLocalData: myApp.clearLocalData);
```

Show "Sign in with Apple" only when `ref.watch(appleSignInAvailableProvider)` is true.

In widget tests, override the gateway and Firestore:

```dart
import 'package:blessed_account/testing.dart';

ProviderScope(overrides: [
  authGatewayProvider.overrideWithValue(FakeAuthGateway()),
  accountFirestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
], child: ...);
```

## Cloud layout

`users/{uid}` holds the shared profile. Each app's data lives in subcollections listed in `CloudLayout`. **Add a collection there before an app writes to it**, so account deletion from either app removes it. Documents in those subcollections must not have subcollections of their own (the client SDK can't delete recursively).

Firestore rules for all of this live with the Firebase project in the Bible app repo (`firestore.rules`, emulator tests in `firestore-tests/`).

## Develop

Flutter version is pinned in `.fvmrc`.

```bash
flutter pub get
dart format lib test && flutter analyze && flutter test
```

Release: update `version` in `pubspec.yaml` and `CHANGELOG.md`, merge to `main`, create tag `vX.Y.Z` (GitHub → Releases → Draft a new release), then bump the `ref:` in each app.
