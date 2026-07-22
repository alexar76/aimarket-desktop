import '../models/interview_question.dart';
import '../models/mock_interview_session.dart';
import 'interview_session_store.dart';
import 'marketplace_service.dart';

/// Production mock-interview flow: hub discover/invoke + local persistence.
class MockInterviewService {
  MockInterviewService({
    required MarketplaceService marketplace,
    InterviewSessionStore? store,
  })  : _marketplace = marketplace,
        _store = store ?? InterviewSessionStore();

  final MarketplaceService _marketplace;
  final InterviewSessionStore _store;

  Future<List<MockInterviewSession>> loadHistory() => _store.loadAll();

  Future<MockInterviewSession> startSession({
    required String company,
    required String role,
  }) async {
    final session = MockInterviewSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      company: company,
      role: role,
      startedAt: DateTime.now(),
      questions: await _loadQuestions(company: company, role: role),
    );
    await _store.upsert(session);
    return session;
  }

  Future<List<InterviewQuestion>> _loadQuestions({
    required String company,
    required String role,
  }) async {
    try {
      final plan = await _marketplace.discoverInterviewQuestions(
        company: company,
        role: role,
        budget: 3.0,
      );
      if (plan.isEmpty) return _offlineQuestions(company: company, role: role);

      final cap = plan.first.capability;
      final result = await _marketplace.getInterviewQuestions(
        capabilityId: cap.id,
        productId: cap.productId,
        input: {
          'target_role': role,
          'company': company,
          'count': 5,
          'difficulty': 'medium',
        },
      );

      final parsed = _parseQuestions(result.output, company: company, role: role);
      if (parsed.isNotEmpty) return parsed.take(5).toList();
    } catch (_) {
      // Hub offline — fall back to offline bank (still real UX, not screenshot seed).
    }
    return _offlineQuestions(company: company, role: role);
  }

  List<InterviewQuestion> _parseQuestions(
    Map<String, dynamic>? output, {
    required String company,
    required String role,
  }) {
    if (output == null) return [];
    final raw = output['questions'] ?? output['items'];
    if (raw is! List) return [];
    return raw
        .map((item) {
          if (item is String) {
            return InterviewQuestion(
              id: item.hashCode.toString(),
              question: item,
              category: 'behavioral',
              difficulty: 'medium',
              company: company,
              role: role,
              keyPoints: const ['Situation', 'Task', 'Action', 'Result'],
              reportedAt: DateTime.now(),
            );
          }
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            map.putIfAbsent('company', () => company);
            map.putIfAbsent('role', () => role);
            return InterviewQuestion.fromJson(map);
          }
          return null;
        })
        .whereType<InterviewQuestion>()
        .toList();
  }

  List<InterviewQuestion> _offlineQuestions({
    required String company,
    required String role,
  }) {
    final now = DateTime.now();
    return [
      InterviewQuestion(
        id: 'offline-1',
        question: 'Tell me about a time you had to make a decision with incomplete data.',
        category: 'behavioral',
        difficulty: 'medium',
        company: company,
        role: role,
        keyPoints: const ['Situation', 'Task', 'Action', 'Result', 'Metrics'],
        source: 'offline_bank',
        reportedAt: now,
      ),
      InterviewQuestion(
        id: 'offline-2',
        question: 'Describe a situation where you disagreed with your manager.',
        category: 'behavioral',
        difficulty: 'medium',
        company: company,
        role: role,
        keyPoints: const ['Respectful disagreement', 'Data-driven argument', 'Outcome'],
        source: 'offline_bank',
        reportedAt: now,
      ),
      InterviewQuestion(
        id: 'offline-3',
        question: 'Walk me through a technical project you are proud of.',
        category: 'technical',
        difficulty: 'medium',
        company: company,
        role: role,
        keyPoints: const ['Scope', 'Trade-offs', 'Impact', 'Ownership'],
        source: 'offline_bank',
        reportedAt: now,
      ),
    ];
  }

  Future<({double score, String feedback, double spentUsd})> scoreAnswer({
    required MockInterviewSession session,
    required InterviewQuestion question,
    required String answer,
  }) async {
    var spent = session.spentUsd;
  var score = _localStarScore(answer, question.keyPoints);
    var feedback = _localFeedback(score, question.keyPoints);

    try {
      final plan = await _marketplace.discoverInterviewQuestions(
        company: session.company,
        role: session.role,
        focusArea: 'mock interview scoring',
        budget: 1.0,
      );
      if (plan.isNotEmpty) {
        final cap = plan.first.capability;
        final result = await _marketplace.getInterviewQuestions(
          capabilityId: cap.id,
          productId: cap.productId,
          input: {
            'mode': 'score_answer',
            'question': question.question,
            'answer': answer,
            'key_points': question.keyPoints,
          },
        );
        spent += cap.pricePerCallUsd;
        final out = result.output;
        if (out != null) {
          score = (out['score'] as num?)?.toDouble() ??
              ((out['score_pct'] as num?)?.toDouble() ?? score * 100) / 100;
          feedback = out['feedback'] as String? ??
              out['summary'] as String? ??
              feedback;
        }
      }
    } catch (_) {
      // Keep local scoring when hub is unavailable.
    }

    session.answers[question.id] = answer;
    session.scores[question.id] = score.clamp(0.0, 1.0);
    session.feedback[question.id] = feedback;
    session.spentUsd = spent;
    await _store.upsert(session);
    return (score: session.scores[question.id]!, feedback: feedback, spentUsd: spent);
  }

  Future<void> completeSession(MockInterviewSession session) async {
    session.completedAt = DateTime.now();
    await _store.upsert(session);
  }

  double _localStarScore(String answer, List<String> keyPoints) {
    if (answer.trim().length < 40) return 0.35;
    final lower = answer.toLowerCase();
    var hits = 0;
    for (final point in keyPoints) {
      if (lower.contains(point.toLowerCase().split(' ').first)) hits++;
    }
    final starWords = ['situation', 'task', 'action', 'result'];
    for (final w in starWords) {
      if (lower.contains(w)) hits++;
    }
    return (0.45 + hits * 0.08).clamp(0.0, 0.95);
  }

  String _localFeedback(double score, List<String> keyPoints) {
    if (score >= 0.8) {
      return 'Strong answer. You covered most key points: ${keyPoints.join(', ')}.';
    }
    if (score >= 0.6) {
      return 'Good start. Expand the Result with a metric and mention: ${keyPoints.take(3).join(', ')}.';
    }
    return 'Use STAR (Situation, Task, Action, Result) and address: ${keyPoints.join(', ')}.';
  }
}
