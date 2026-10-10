# Changelog

## 0.1.0

- `AccountService`: Google sign-in (Apple on iOS/macOS), sign-out, and account
  deletion that removes both apps' cloud data (`CloudLayout`).
- `SignInResult` with typed failure reasons and user-facing messages.
- `SharedProfile` (`users/{uid}`) created on first sign-in from either app.
- Riverpod providers: `accountServiceProvider`, `accountUserProvider`,
  `sharedProfileProvider`.
