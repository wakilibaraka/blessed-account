import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_gateway.dart';
import 'cloud_layout.dart';

/// The profile both apps show for an account, stored in `users/{uid}`.
class SharedProfile {
  final String uid;
  final String displayName;

  /// An emoji (e.g. '🕊️') or an https image URL. Null = show initials.
  final String? avatar;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SharedProfile({
    required this.uid,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.avatar,
  });

  factory SharedProfile.fromFirestore(String uid, Map<String, dynamic> data) =>
      SharedProfile(
        uid: uid,
        displayName: data['displayName'] as String? ?? '',
        avatar: data['avatar'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int? ?? 0),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] as int? ?? 0),
      );

  Map<String, dynamic> toFirestore() => {
        'displayName': displayName,
        'avatar': avatar,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };
}

/// Reads and writes [SharedProfile] documents.
class SharedProfileRepository {
  final FirebaseFirestore _db;
  final DateTime Function() _now;

  SharedProfileRepository(this._db, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection(CloudLayout.users).doc(uid);

  /// Live profile for [uid]; null until the document exists.
  Stream<SharedProfile?> watch(String uid) => _doc(uid).snapshots().map(
      (s) => s.exists ? SharedProfile.fromFirestore(uid, s.data()!) : null);

  /// Creates the profile on first sign-in (from the provider's display name);
  /// leaves an existing profile untouched, whichever app created it.
  Future<SharedProfile> ensureExists(AccountUser user) async {
    final snap = await _doc(user.uid).get();
    if (snap.exists) {
      return SharedProfile.fromFirestore(user.uid, snap.data()!);
    }
    final now = _now();
    final profile = SharedProfile(
      uid: user.uid,
      displayName: (user.displayName?.trim().isNotEmpty ?? false)
          ? user.displayName!.trim()
          : 'Friend',
      createdAt: now,
      updatedAt: now,
    );
    await _doc(user.uid).set(profile.toFirestore());
    return profile;
  }

  /// Updates the given fields. Pass `clearAvatar: true` to remove the avatar.
  Future<void> update(String uid,
      {String? displayName, String? avatar, bool clearAvatar = false}) {
    return _doc(uid).update({
      if (displayName != null) 'displayName': displayName.trim(),
      if (avatar != null || clearAvatar) 'avatar': clearAvatar ? null : avatar,
      'updatedAt': _now().millisecondsSinceEpoch,
    });
  }
}
