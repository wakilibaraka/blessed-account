import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../cloud_layout.dart';
import 'sync_record.dart';

/// Reads and writes [SyncRecord]s at `users/{uid}/{collection}/{docId}`.
///
/// Each document: `{id, data, updatedAt, deleted, device, syncedAt}`, where
/// `syncedAt` is the server time of the write and drives incremental pulls.
class FirestoreSyncRepository {
  /// Firestore allows 500 writes per batch.
  static const batchSize = 400;

  final FirebaseFirestore _db;
  FirestoreSyncRepository(this._db);

  CollectionReference<Map<String, dynamic>> _col(String uid, String name) =>
      _db.collection(CloudLayout.users).doc(uid).collection(name);

  /// Firestore document ids can't contain '/' or be '.'/'..'.
  static String docId(String id) =>
      Uri.encodeComponent(id).replaceAll('.', '%2E');

  /// Records written at or after [since] (server ms), and the latest
  /// `syncedAt` seen (or [since] if none).
  Future<(List<SyncRecord>, int?)> pull(String uid, String collection,
      {int? since}) async {
    Query<Map<String, dynamic>> q = _col(uid, collection);
    if (since != null) {
      q = q.where('syncedAt',
          isGreaterThanOrEqualTo: Timestamp.fromMillisecondsSinceEpoch(since));
    }
    final snap = await q.get();
    var latest = since;
    final out = <SyncRecord>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final syncedAt = d['syncedAt'];
      // Not yet on the server (a pending local write): skip until it is.
      if (syncedAt is! Timestamp) continue;
      final ms = syncedAt.millisecondsSinceEpoch;
      if (latest == null || ms > latest) latest = ms;
      final id = d['id'];
      final updatedAt = d['updatedAt'];
      if (id is! String || updatedAt is! int) continue;
      final deleted = d['deleted'] == true;
      final data = d['data'];
      out.add(SyncRecord(
        id: id,
        data: deleted || data is! Map ? null : Map<String, Object?>.from(data),
        updatedAt: updatedAt,
        deleted: deleted || data is! Map,
        device: d['device'] as String? ?? '',
      ));
    }
    return (out, latest);
  }

  /// Queues [records] for upload. Firestore keeps queued writes on the
  /// device and sends them when online, so this doesn't wait for the
  /// server; [onError] gets the records of a batch the server rejected.
  void push(String uid, String collection, List<SyncRecord> records,
      {void Function(List<SyncRecord> failed, Object error)? onError}) {
    for (var i = 0; i < records.length; i += batchSize) {
      final chunk = records.sublist(
          i, i + batchSize > records.length ? records.length : i + batchSize);
      final batch = _db.batch();
      for (final r in chunk) {
        batch.set(_col(uid, collection).doc(docId(r.id)), {
          'id': r.id,
          'data': r.deleted ? null : r.data,
          'updatedAt': r.updatedAt,
          'deleted': r.deleted,
          'device': r.device,
          'syncedAt': FieldValue.serverTimestamp(),
        });
      }
      unawaited(batch.commit().catchError((Object e) {
        onError?.call(chunk, e);
      }));
    }
  }
}
