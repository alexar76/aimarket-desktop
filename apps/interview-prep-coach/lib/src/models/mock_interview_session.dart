import 'interview_question.dart';

/// A practice session — persisted locally; hub invoked for questions/scoring.
class MockInterviewSession {
  MockInterviewSession({
    required this.id,
    required this.company,
    required this.role,
    required this.startedAt,
    this.completedAt,
    this.spentUsd = 0,
    this.questions = const [],
    Map<String, String>? answers,
    Map<String, double>? scores,
    Map<String, String>? feedback,
  })  : answers = answers ?? {},
        scores = scores ?? {},
        feedback = feedback ?? {};

  final String id;
  final String company;
  final String role;
  final DateTime startedAt;
  DateTime? completedAt;
  double spentUsd;
  final List<InterviewQuestion> questions;
  final Map<String, String> answers;
  final Map<String, double> scores;
  final Map<String, String> feedback;

  int get answeredCount => answers.length;
  int get questionCount => questions.length;

  double? get averageScore {
    if (scores.isEmpty) return null;
    return scores.values.reduce((a, b) => a + b) / scores.length;
  }

  bool get isComplete =>
      completedAt != null || (questionCount > 0 && answeredCount >= questionCount);

  Map<String, dynamic> toJson() => {
        'id': id,
        'company': company,
        'role': role,
        'started_at': startedAt.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'spent_usd': spentUsd,
        'questions': questions.map((q) => q.toJson()).toList(),
        'answers': answers,
        'scores': scores.map((k, v) => MapEntry(k, v)),
        'feedback': feedback,
      };

  factory MockInterviewSession.fromJson(Map<String, dynamic> json) {
    final rawQuestions = json['questions'] as List<dynamic>? ?? [];
    return MockInterviewSession(
      id: json['id'] as String? ?? '',
      company: json['company'] as String? ?? '',
      role: json['role'] as String? ?? '',
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? '') ??
          DateTime.now(),
      completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
      spentUsd: (json['spent_usd'] as num?)?.toDouble() ?? 0,
      questions: rawQuestions
          .map((q) => InterviewQuestion.fromJson(Map<String, dynamic>.from(q as Map)))
          .toList(),
      answers: (json['answers'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          {},
      scores: (json['scores'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {},
      feedback: (json['feedback'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          {},
    );
  }
}
