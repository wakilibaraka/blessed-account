/// One synced item as stored in the cloud: `users/{uid}/{collection}/{id}`.
class SyncRecord {
  final String id;

  /// The item's fields; null for a deletion marker (tombstone).
  final Map<String, Object?>? data;

  /// When the item last changed, in ms since epoch (device clock).
  final int updatedAt;
  final bool deleted;

  /// The device that made the change; breaks `updatedAt` ties.
  final String device;

  const SyncRecord({
    required this.id,
    required this.data,
    required this.updatedAt,
    required this.deleted,
    required this.device,
  });

  /// True if this change should replace one made at [otherUpdatedAt] by
  /// [otherDevice] (last writer wins; ties broken by device id).
  bool isNewerThan(int otherUpdatedAt, String otherDevice) =>
      updatedAt > otherUpdatedAt ||
      (updatedAt == otherUpdatedAt && device.compareTo(otherDevice) > 0);
}

/// Stable 32-bit FNV-1a hash of an item's fields, used to notice changes.
/// Map keys are sorted so field order doesn't matter.
int itemHash(Object? value) {
  var h = 0x811c9dc5;
  void add(String s) {
    for (final unit in s.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0xffffffff;
    }
  }

  void walk(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      add('{');
      for (final k in keys) {
        add(k);
        add(':');
        walk(v[k]);
        add(',');
      }
      add('}');
    } else if (v is List) {
      add('[');
      for (final e in v) {
        walk(e);
        add(',');
      }
      add(']');
    } else {
      add('${v.runtimeType}|$v');
    }
  }

  walk(value);
  return h;
}
