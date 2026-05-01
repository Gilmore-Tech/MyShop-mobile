import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SharedPreferences`-backed [ChatOutbox]. Stores the entire outbox under
/// a single key as a JSON list — the queue is small (failed sends only)
/// so this is cheaper than per-item keys and survives an app kill.
///
/// Concurrency: every mutation re-reads the canonical list from disk
/// before writing, so two near-simultaneous calls (e.g. send + retry)
/// don't lose each other's writes. SharedPreferences itself is single-
/// instance per process so the read-modify-write window is small.
class SharedPreferencesChatOutbox implements ChatOutbox {
  SharedPreferencesChatOutbox(this._prefs);

  final SharedPreferences _prefs;

  static const _storageKey = 'chat_outbox_v1';

  Future<List<ChatOutboxItem>> _readAll() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ChatOutboxItem.fromJson)
          .toList(growable: false);
    } catch (_) {
      // Corrupt blob — drop it. The user loses unsent messages, but
      // that's preferable to a permanent crash on every app start.
      await _prefs.remove(_storageKey);
      return const [];
    }
  }

  Future<void> _writeAll(List<ChatOutboxItem> items) async {
    if (items.isEmpty) {
      await _prefs.remove(_storageKey);
      return;
    }
    await _prefs.setString(
      _storageKey,
      jsonEncode(items.map((i) => i.toJson()).toList()),
    );
  }

  @override
  Future<List<ChatOutboxItem>> readForChannel(String channelKey) async {
    final all = await _readAll();
    final hits = all.where((i) => i.channelKey == channelKey).toList();
    hits.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return hits;
  }

  @override
  Future<void> upsert(ChatOutboxItem item) async {
    final all = await _readAll();
    final next = [
      for (final existing in all)
        if (existing.tempId != item.tempId) existing,
      item,
    ];
    await _writeAll(next);
  }

  @override
  Future<void> remove(String tempId) async {
    final all = await _readAll();
    final next = [
      for (final existing in all)
        if (existing.tempId != tempId) existing,
    ];
    if (next.length == all.length) return;
    await _writeAll(next);
  }

  @override
  Future<void> clearChannel(String channelKey) async {
    final all = await _readAll();
    final next = [
      for (final existing in all)
        if (existing.channelKey != channelKey) existing,
    ];
    if (next.length == all.length) return;
    await _writeAll(next);
  }
}
