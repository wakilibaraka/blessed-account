import 'sync_record.dart';

/// What this device knows about one item: when it last changed, by whom,
/// and whether that change still needs uploading.
class LedgerEntry {
  final int updatedAt;
  final bool deleted;
  final String device;
  final int hash;
  final bool dirty;

  const LedgerEntry({
    required this.updatedAt,
    required this.deleted,
    required this.device,
    required this.hash,
    required this.dirty,
  });

  LedgerEntry copyWith({bool? dirty}) => LedgerEntry(
        updatedAt: updatedAt,
        deleted: deleted,
        device: device,
        hash: hash,
        dirty: dirty ?? this.dirty,
      );

  Map<String, Object?> toJson() =>
      {'u': updatedAt, 'x': deleted, 'd': device, 'h': hash, 'p': dirty};

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        updatedAt: j['u'] as int,
        deleted: j['x'] as bool,
        device: j['d'] as String,
        hash: j['h'] as int,
        dirty: j['p'] as bool,
      );
}

/// Per-account, per-collection change record kept beside the app's own
/// storage. The app's data format stays unchanged: the ledger works out
/// what changed by comparing snapshots ([observe]).
class SyncLedger {
  /// Tombstones older than this are forgotten once uploaded.
  static const tombstoneTtl = Duration(days: 90);

  final Map<String, LedgerEntry> entries;

  /// Server time (ms) up to which remote changes have been pulled; null
  /// before the first sync of this collection for this account.
  int? pulledThrough;

  SyncLedger({Map<String, LedgerEntry>? entries, this.pulledThrough})
      : entries = entries ?? {};

  bool get isFresh => pulledThrough == null && entries.isEmpty;

  /// Records local adds, edits and deletes in [current] (id → fields) as
  /// changes made at [now] by [device]. Returns true if anything changed.
  bool observe(Map<String, Map<String, Object?>> current,
      {required int now, required String device}) {
    var changed = false;
    current.forEach((id, data) {
      final h = itemHash(data);
      final e = entries[id];
      if (e == null || e.deleted || e.hash != h) {
        entries[id] = LedgerEntry(
            updatedAt: now,
            deleted: false,
            device: device,
            hash: h,
            dirty: true);
        changed = true;
      }
    });
    for (final id in entries.keys.toList()) {
      final e = entries[id]!;
      if (!e.deleted && !current.containsKey(id)) {
        entries[id] = LedgerEntry(
            updatedAt: now,
            deleted: true,
            device: device,
            hash: 0,
            dirty: true);
        changed = true;
      }
    }
    return changed;
  }

  /// Applies [remote] changes that are newer than what this device has.
  /// Returns the new local item map (a copy of [current] with remote
  /// changes applied) and whether it differs from [current].
  ///
  /// `updatedAt` values more than a day ahead of [now] are clamped, so one
  /// device with a wrong clock can't win every conflict forever.
  (Map<String, Map<String, Object?>>, bool) applyRemote(
      Map<String, Map<String, Object?>> current, Iterable<SyncRecord> remote,
      {required int now}) {
    final next = Map<String, Map<String, Object?>>.from(current);
    var changed = false;
    final maxTime = now + const Duration(days: 1).inMilliseconds;
    for (final r in remote) {
      final updatedAt = r.updatedAt > maxTime ? maxTime : r.updatedAt;
      final rec = SyncRecord(
          id: r.id,
          data: r.data,
          updatedAt: updatedAt,
          deleted: r.deleted,
          device: r.device);
      final e = entries[r.id];
      if (e != null && !rec.isNewerThan(e.updatedAt, e.device)) continue;
      if (rec.deleted || rec.data == null) {
        if (next.remove(r.id) != null) changed = true;
        entries[r.id] = LedgerEntry(
            updatedAt: updatedAt,
            deleted: true,
            device: r.device,
            hash: 0,
            dirty: false);
      } else {
        final h = itemHash(rec.data);
        if (!next.containsKey(r.id) || itemHash(next[r.id]) != h) {
          changed = true;
        }
        next[r.id] = rec.data!;
        entries[r.id] = LedgerEntry(
            updatedAt: updatedAt,
            deleted: false,
            device: r.device,
            hash: h,
            dirty: false);
      }
    }
    return (next, changed);
  }

  /// Local changes not yet uploaded, as records built from [current].
  List<SyncRecord> pending(Map<String, Map<String, Object?>> current) => [
        for (final MapEntry(key: id, value: e) in entries.entries)
          if (e.dirty)
            SyncRecord(
                id: id,
                data: e.deleted ? null : current[id],
                updatedAt: e.updatedAt,
                deleted: e.deleted || !current.containsKey(id),
                device: e.device),
      ];

  void markUploaded(Iterable<SyncRecord> records) {
    for (final r in records) {
      final e = entries[r.id];
      if (e != null && e.updatedAt == r.updatedAt && e.device == r.device) {
        entries[r.id] = e.copyWith(dirty: false);
      }
    }
  }

  void markPending(Iterable<SyncRecord> records) {
    for (final r in records) {
      final e = entries[r.id];
      if (e != null && e.updatedAt == r.updatedAt && e.device == r.device) {
        entries[r.id] = e.copyWith(dirty: true);
      }
    }
  }

  /// Forgets uploaded tombstones older than [tombstoneTtl].
  void prune({required int now}) {
    final cutoff = now - tombstoneTtl.inMilliseconds;
    entries
        .removeWhere((_, e) => e.deleted && !e.dirty && e.updatedAt < cutoff);
  }

  Map<String, Object?> toJson() => {
        'pulledThrough': pulledThrough,
        'entries': entries.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory SyncLedger.fromJson(Map<String, dynamic> j) => SyncLedger(
        pulledThrough: j['pulledThrough'] as int?,
        entries: (j['entries'] as Map<String, dynamic>? ?? {}).map((k, v) =>
            MapEntry(k, LedgerEntry.fromJson(v as Map<String, dynamic>))),
      );
}
