/// Where each app keeps per-user data in the shared Firebase project.
///
/// Both apps (The Blessed Bible and Blessed Arcade) sign in to the same
/// Firebase project, so one account owns data from both. Every per-user
/// collection is listed here, in one place, so deleting the account from
/// either app removes everything, including data the other app wrote.
/// When an app adds a collection under `users/{uid}`, add it here first.
class CloudLayout {
  const CloudLayout._();

  /// Root collection; `users/{uid}` holds the [SharedProfile] fields.
  static const String users = 'users';

  /// The Blessed Bible's per-user subcollections.
  static const List<String> bibleCollections = [
    'plans',
    'sync_data', // legacy, pre-Phase 5B sync
    'bookmarks',
    'folders',
    'highlights',
    'notes',
    'custom_plans',
    'plan_progress',
    'reading_days',
    'meta',
  ];

  /// Blessed Arcade's per-user subcollections.
  static const List<String> arcadeCollections = [
    'arcade',
  ];

  /// Every subcollection under `users/{uid}`, from both apps.
  static const List<String> allUserCollections = [
    ...bibleCollections,
    ...arcadeCollections,
  ];
}
