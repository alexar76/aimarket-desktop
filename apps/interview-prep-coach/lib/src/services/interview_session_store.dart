import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mock_interview_session.dart';

/// Local persistence for mock interview sessions (SQLite not required).
class InterviewSessionStore {
  static const _key = 'mock_interview_sessions_v1';

  Future<List<MockInterviewSession>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => MockInterviewSession.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<MockInterviewSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(sessions.map((s) => s.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  Future<void> upsert(MockInterviewSession session) async {
    final all = await loadAll();
    final idx = all.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      all[idx] = session;
    } else {
      all.insert(0, session);
    }
    await saveAll(all);
  }
}
