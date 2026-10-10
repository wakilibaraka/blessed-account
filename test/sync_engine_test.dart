import 'package:blessed_account/blessed_account.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory app collection.
class MemCollection implements SyncCollection {
  @override
  final String name;
  Map<String, Map<String, Object?>> items;
  int writes = 0;
  MemCollection(this.name, [Map<String, Map<String, Object?>>? items])
      : items = items ?? {};

  @override
  Map<String, Map<String, Object?>> read() =>
      {for (final e in items.entries) e.key: Map.of(e.value)};

  @override
  Future<void> write(Map<String, Map<String, Object?>> next) async {
    writes++;
    items = next;
  }
}

class MemStore implements SyncStore {
  final values = <String, String>{};
  @override
  String? read(String key) => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// One device: its own store, clock and collections, sharing [db].
class Device {
  final MemStore store = MemStore();
  int clock;
  late final SyncEngine engine;
  final notes = MemCollection('notes');
  Device(FakeFirebaseFirestore db, String id, {this.clock = 1000}) {
    engine = SyncEngine(FirestoreSyncRepository(db), store,
        deviceId: id, now: () => clock);
  }
  /// Syncs, then lets the background upload finish (on a phone it is
  /// queued by Firestore and sent when online).
  Future<SyncReport> sync() async {
    final report = await engine.sync('u1', [notes]);
    await pumpEventQueue();
    return report;
  }
  Future<void> edit(void Function(Map<String, Map<String, Object?>>) f) async {
    f(notes.items);
    clock += 10;
    await engine.recordLocalChanges('u1', notes);
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late Device a;
  late Device b;

  setUp(() {
    db = FakeFirebaseFirestore();
    a = Device(db, 'A');
    b = Device(db, 'B');
  });

  test('items reach a second device, and re-sync is a no-op', () async {
    a.notes.items = {
      'n1': {'text': 'hello'},
      'n2': {'text': 'world'},
    };
    expect((await a.sync()).pushed, 2);
    await b.sync();
    expect(b.notes.items, a.notes.items);

    final again = await b.sync();
    expect(again.pushed, 0);
    expect(again.pulled, 0);
    expect((await a.sync()).pushed, 0);
  });

  test('deletions propagate and do not come back', () async {
    a.notes.items = {
      'n1': {'text': 'x'},
      'n2': {'text': 'y'},
    };
    await a.sync();
    await b.sync();

    await b.edit((m) => m.remove('n1'));
    await b.sync();
    await a.sync();
    expect(a.notes.items.keys, ['n2']);

    // A syncing again must not resurrect n1 on B.
    await a.sync();
    await b.sync();
    expect(b.notes.items.keys, ['n2']);
  });

  test('the later edit wins on both devices', () async {
    a.notes.items = {
      'n1': {'text': 'v0'},
    };
    await a.sync();
    await b.sync();

    await a.edit((m) => m['n1'] = {'text': 'from A'});
    b.clock = a.clock + 100;
    await b.edit((m) => m['n1'] = {'text': 'from B (later)'});

    await a.sync();
    await b.sync();
    await a.sync();
    expect(a.notes.items['n1'], {'text': 'from B (later)'});
    expect(b.notes.items['n1'], {'text': 'from B (later)'});
  });

  test('a fresh device never overwrites the account with its defaults',
      () async {
    a.notes.items = {
      'folder_study': {'name': 'Study'},
    };
    await a.sync();
    await a.edit((m) => m['folder_study'] = {'name': 'Romans study'});
    await a.sync();

    // B was installed later (newer clock) with the default name.
    b.clock = a.clock + 1000000;
    b.notes.items = {
      'folder_study': {'name': 'Study'},
      'local_only': {'name': 'Mine'},
    };
    await b.sync();
    expect(b.notes.items['folder_study'], {'name': 'Romans study'});

    await a.sync();
    expect(a.notes.items['folder_study'], {'name': 'Romans study'});
    expect(a.notes.items['local_only'], {'name': 'Mine'},
        reason: 'items only on the new device are merged into the account');
  });

  test('ids with slashes and dots are stored safely', () async {
    a.notes.items = {
      'a/b.c': {'v': 1},
    };
    await a.sync();
    await b.sync();
    expect(b.notes.items.keys, ['a/b.c']);
  });

  test('accounts keep separate ledgers', () async {
    a.notes.items = {
      'n1': {'v': 1},
    };
    await a.sync();
    final report = await a.engine.sync('u2', [a.notes]);
    await pumpEventQueue();
    expect(report.pushed, 1, reason: 'a new account gets the local items');
  });

  group('SyncLedger', () {
    test('clamps far-future remote times', () {
      final ledger = SyncLedger();
      ledger.applyRemote({}, [
        const SyncRecord(
            id: 'x',
            data: {'v': 1},
            updatedAt: 1 << 50,
            deleted: false,
            device: 'Z'),
      ], now: 1000);
      expect(ledger.entries['x']!.updatedAt,
          1000 + const Duration(days: 1).inMilliseconds);
    });

    test('prunes old uploaded tombstones only', () {
      final ledger = SyncLedger(entries: {
        'old': const LedgerEntry(
            updatedAt: 0, deleted: true, device: 'A', hash: 0, dirty: false),
        'oldPending': const LedgerEntry(
            updatedAt: 0, deleted: true, device: 'A', hash: 0, dirty: true),
        'live': const LedgerEntry(
            updatedAt: 0, deleted: false, device: 'A', hash: 1, dirty: false),
      });
      ledger.prune(now: const Duration(days: 91).inMilliseconds);
      expect(ledger.entries.keys, unorderedEquals(['oldPending', 'live']));
    });

    test('hash ignores key order and sees value changes', () {
      expect(itemHash({'a': 1, 'b': 2}), itemHash({'b': 2, 'a': 1}));
      expect(itemHash({'a': 1}), isNot(itemHash({'a': '1'})));
      expect(itemHash({'a': null}), isNot(itemHash(<String, Object?>{})));
    });

    test('round-trips through JSON', () {
      final ledger = SyncLedger(pulledThrough: 5)
        ..observe({
          'x': {'v': 1}
        }, now: 10, device: 'A');
      final copy = SyncLedger.fromJson(ledger.toJson());
      expect(copy.pulledThrough, 5);
      expect(copy.entries['x']!.dirty, isTrue);
    });
  });
}
