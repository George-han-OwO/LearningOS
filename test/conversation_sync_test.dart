import 'package:ai_study_os/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conversation sync state round-trips the 15 minute policy', () {
    final syncedAt = DateTime.utc(2026, 8, 27, 8, 15);
    final state = ConversationSyncState(
      enabled: true,
      intervalMinutes: 15,
      status: ConversationSyncStatus.synced,
      lastAttemptAt: syncedAt,
      lastSyncedAt: syncedAt,
      lastSyncedConversationId: 'chat-previous',
      lastSyncedTitle: 'Previous chat',
      scheduleConfigured: true,
    );

    final restored = ConversationSyncState.fromMap(state.toMap());
    expect(restored.enabled, isTrue);
    expect(restored.intervalMinutes, 15);
    expect(restored.status, ConversationSyncStatus.synced);
    expect(restored.lastSyncedConversationId, 'chat-previous');
    expect(restored.lastSyncedAt, syncedAt);
  });

  test('high-frequency mode is off by default and legacy implicit-on is safe', () {
    expect(ConversationSyncState.defaultState.enabled, isFalse);

    final legacy = ConversationSyncState.fromMap({
      'enabled': true,
      'interval_minutes': 15,
      'status': 'waiting',
    });
    expect(legacy.enabled, isFalse);
    expect(legacy.scheduleConfigured, isFalse);
  });

  test('nightly run marker round-trips with an explicit high-frequency choice', () {
    final nightlyAt = DateTime(2026, 8, 27, 23);
    final state = ConversationSyncState(
      enabled: false,
      intervalMinutes: 15,
      status: ConversationSyncStatus.waiting,
      lastNightlyRunAt: nightlyAt,
      scheduleConfigured: true,
    );

    final restored = ConversationSyncState.fromMap(state.toMap());
    expect(restored.enabled, isFalse);
    expect(restored.scheduleConfigured, isTrue);
    expect(restored.lastNightlyRunAt, nightlyAt);
  });

  test('incomplete snapshots remain distinguishable from completed ones', () {
    final snapshot = ChatGptConversationSnapshot.fromMap({
      'external_id': 'chat-newest',
      'title': 'Still generating',
      'transcript': 'User: hello',
      'updated_at': '2026-08-27T08:20:00.000Z',
      'is_complete': false,
    });

    expect(snapshot.externalId, 'chat-newest');
    expect(snapshot.isComplete, isFalse);
  });
}
