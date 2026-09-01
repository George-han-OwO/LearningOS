import 'dart:async';

import '../../data/app_database.dart';
import 'hybrid_ai_service.dart';

class PendingWordEnrichmentResult {
  const PendingWordEnrichmentResult({
    required this.status,
    required this.pendingCount,
    required this.requestedCount,
    required this.enrichedCount,
    required this.message,
    required this.checkedAt,
  });

  final String status;
  final int pendingCount;
  final int requestedCount;
  final int enrichedCount;
  final String message;
  final DateTime checkedAt;

  Map<String, Object?> toMap() => {
    'status': status,
    'pending_count': pendingCount,
    'requested_count': requestedCount,
    'enriched_count': enrichedCount,
    'message': message,
    'checked_at': checkedAt.toIso8601String(),
    'retry_interval_seconds': 30,
  };
}

/// Executes one bounded enrichment batch for each user.
///
/// Per-user locks make a mobile-triggered check and the background 30-second
/// worker safe to run at the same time without duplicate provider requests.
class PendingWordEnrichmentProcessor {
  PendingWordEnrichmentProcessor(this.db, this.aiService);

  final AppDatabase db;
  final HybridAiService aiService;
  final Set<int> _busyUsers = <int>{};

  Future<PendingWordEnrichmentResult> runForUser(int userId) async {
    final initialPending = await db.pendingWordCount(userId);
    if (initialPending == 0) {
      return _result(status: 'idle', pendingCount: 0, message: '没有待 AI 补全的词条。');
    }
    if (!_busyUsers.add(userId)) {
      return _result(
        status: 'busy',
        pendingCount: initialPending,
        message: '服务器正在处理这一批词条。',
      );
    }

    try {
      if (!db.secretVaultReady) {
        return _result(
          status: 'waiting_for_server_key',
          pendingCount: initialPending,
          message: '服务器密钥保险库尚未配置，队列会每 30 秒继续检查。',
        );
      }

      final settings = await db.aiSettings();
      if (!settings.ready) {
        return _result(
          status: 'waiting_for_api_key',
          pendingCount: initialPending,
          message: 'DeepSeek API Key 尚未启用，队列会每 30 秒继续检查。',
        );
      }

      final pendingWords = await db.pendingWordsForUser(userId, limit: 20);
      final report = await aiService.enrichWords(
        settings: settings,
        words: pendingWords,
      );
      if (report.enrichedCount > 0) {
        await db.updateWordEnrichments(userId: userId, words: report.words);
      }
      final remaining = await db.pendingWordCount(userId);
      // A warning can describe a partial provider response, but if the
      // database has no pending fields left there is nothing useful to retry.
      // Treat the queue as complete before looking at the warning so the
      // worker can release its timer immediately.
      if (remaining == 0) {
        return _result(
          status: 'complete',
          pendingCount: 0,
          requestedCount: report.requestedCount,
          enrichedCount: report.enrichedCount,
          message: '待翻译、待识别词性和其他待补全字段已全部处理完成。',
        );
      }
      if (report.warning != null) {
        return _result(
          status: 'retrying',
          pendingCount: remaining,
          requestedCount: report.requestedCount,
          enrichedCount: report.enrichedCount,
          message: '本轮 AI 补全未全部成功；服务器将在 30 秒后自动重试。${report.warning}',
        );
      }
      return _result(
        status: 'enriched',
        pendingCount: remaining,
        requestedCount: report.requestedCount,
        enrichedCount: report.enrichedCount,
        message: '本轮已补全 ${report.enrichedCount} 个词条，剩余内容将在 30 秒后继续。',
      );
    } catch (error) {
      return _result(
        status: 'retrying',
        pendingCount: await db.pendingWordCount(userId),
        message: 'AI 连接暂不可用；服务器将在 30 秒后自动重试：$error',
      );
    } finally {
      _busyUsers.remove(userId);
    }
  }

  Future<List<PendingWordEnrichmentResult>> runAll() async {
    final userIds = await db.userIdsWithPendingWords();
    final results = <PendingWordEnrichmentResult>[];
    for (final userId in userIds) {
      results.add(await runForUser(userId));
    }
    return results;
  }

  PendingWordEnrichmentResult _result({
    required String status,
    required int pendingCount,
    int requestedCount = 0,
    int enrichedCount = 0,
    required String message,
  }) => PendingWordEnrichmentResult(
    status: status,
    pendingCount: pendingCount,
    requestedCount: requestedCount,
    enrichedCount: enrichedCount,
    message: message,
    checkedAt: DateTime.now(),
  );
}

/// Server-owned scheduler. It runs while there are pending fields and stops
/// when the queue is empty, then is woken by a new import. This continues to
/// work when the Android app is backgrounded or closed.
class PendingWordEnrichmentWorker {
  PendingWordEnrichmentWorker(
    this.processor, {
    this.interval = const Duration(seconds: 30),
  });

  final PendingWordEnrichmentProcessor processor;
  final Duration interval;
  Timer? _timer;
  bool _running = false;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(runNow()));
    unawaited(runNow());
  }

  /// Starts the worker only when a new import creates pending fields, and
  /// wakes an already-running worker immediately instead of waiting 30s.
  void wakeUp() {
    start();
    unawaited(runNow());
  }

  Future<void> runNow() async {
    if (_running) return;
    _running = true;
    try {
      final results = await processor.runAll();
      final enriched = results.fold<int>(
        0,
        (total, result) => total + result.enrichedCount,
      );
      // An empty result means there are no users with pending translation,
      // phonetic, part-of-speech, or example fields. Stop polling until a new
      // import wakes the worker. HTTP clients are request-scoped and are
      // closed by the AI service after each call.
      if (results.isEmpty ||
          results.every((result) => result.pendingCount == 0)) {
        stop();
      }
      if (enriched > 0) {
        print('Pending word worker enriched $enriched item(s).');
      }
    } catch (error) {
      // Keep the worker alive after transient database or provider failures.
      // No provider key or request body is included in this message.
      print('Pending word worker will retry after an error: $error');
    } finally {
      _running = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
