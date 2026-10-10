# Changelog

## 0.2.0

- `accountFirestoreProvider`: the Firestore instance is now a provider, so
  apps can override it in widget tests.
- `appleSignInAvailableProvider` for showing or hiding the Apple button.
- `package:blessed_account/testing.dart`: `FakeAuthGateway` for app tests.

## 0.1.0

- `AccountService`: Google sign-in (Apple on iOS/macOS), sign-out, and account
  deletion that removes both apps' cloud data (`CloudLayout`).
- `SignInResult` with typed failure reasons and user-facing messages.
- `SharedProfile` (`users/{uid}`) created on first sign-in from either app.
- Riverpod providers: `accountServiceProvider`, `accountUserProvider`,
  `sharedProfileProvider`.
