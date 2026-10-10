import 'dart:convert';

import 'firestore_sync_repository.dart';
import 'sync_ledger.dart';

/// Where the engine keeps its ledgers (e.g. SharedPreferences).
abstract interface class SyncStore {
  String? read(String key);
  Future<void> write(String key, String value);
}

/// One kind of synced data in an app (bookmarks, highlights, arcade
/// progress...). Items are id → JSON-safe fields.
abstract interface class SyncCollection {
  /// Firestore subcollection name; must be listed in `CloudLayout`.
  String get name;

  Map<String, Map<String, Object?>> read();

  /// Replaces the app's items with [items] (remote changes applied).
  Future<void> write(Map<String, Map<String, Object?>> items);
}

class SyncReport {
  final int pulled;
  final int pushed;
  const SyncReport({this.pulled = 0, this.pushed = 0});
  SyncReport operator +(SyncReport o) =>
      SyncReport(pulled: pulled + o.pulled, pushed: pushed + o.pushed);
}

/// Two-way sync of [SyncCollection]s with the signed-in account:
/// per-item last-writer-wins with tombstones (see `SyncLedger`).
class SyncEngine {
  final FirestoreSyncRepository _repo;
  final SyncStore _store;
  final String deviceId;
  final int Function() _now;

  SyncEngine(this._repo, this._store,
      {required this.deviceId, int Function()? now})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  static String ledgerKey(String uid, String collection) =>
      'sync_ledger.$uid.$collection';

  SyncLedger _load(String uid, String collection) {
    final raw = _store.read(ledgerKey(uid, collection));
    if (raw == null) return SyncLedger();
    try {
      return SyncLedger.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return SyncLedger();
    }
  }

  Future<void> _save(String uid, String collection, SyncLedger ledger) =>
      _store.write(ledgerKey(uid, collection), jsonEncode(ledger.toJson()));

  /// Timestamps local changes now, so they win over older edits from other
  /// devices. Call whenever the collection changes while signed in.
  Future<bool> recordLocalChanges(String uid, SyncCollection c) async {
    final ledger = _load(uid, c.name);
    if (ledger.isFresh) return false; // First sync decides (see [sync]).
    final changed = ledger.observe(c.read(), now: _now(), device: deviceId);
    if (changed) await _save(uid, c.name, ledger);
    return changed;
  }

  /// Pulls remote changes, applies the newer ones locally, and uploads
  /// local changes.
  ///
  /// On the first sync of a collection for an account, items already on
  /// the device count as older than anything in the account: they are
  /// uploaded if the account lacks them, but never overwrite the
  /// account's version (so a fresh install's defaults can't undo edits
  /// made elsewhere).
  Future<SyncReport> sync(String uid, List<SyncCollection> collections) async {
    var report = const SyncReport();
    for (final c in collections) {
      report += await _syncOne(uid, c);
    }
    return report;
  }

  Future<SyncReport> _syncOne(String uid, SyncCollection c) async {
    final ledger = _load(uid, c.name);
    final current = c.read();
    ledger.observe(current, now: ledger.isFresh ? 1 : _now(), device: deviceId);

    final (remote, latest) =
        await _repo.pull(uid, c.name, since: ledger.pulledThrough);
    final (next, changed) = ledger.applyRemote(current, remote, now: _now());
    if (changed) await c.write(next);
    ledger.pulledThrough = latest ?? ledger.pulledThrough ?? 0;

    final pending = ledger.pending(next);
    if (pending.isNotEmpty) {
      _repo.push(uid, c.name, pending, onError: (failed, _) async {
        final l = _load(uid, c.name)..markPending(failed);
        await _save(uid, c.name, l);
      });
      ledger.markUploaded(pending);
    }
    ledger.prune(now: _now());
    await _save(uid, c.name, ledger);
    return SyncReport(
        pulled: changed ? remote.length : 0, pushed: pending.length);
  }
}
