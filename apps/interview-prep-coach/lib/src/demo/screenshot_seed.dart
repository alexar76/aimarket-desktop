import '../models/interview_question.dart';
import '../models/mock_interview_session.dart';

/// Static UI seed for screenshot and video capture pipelines only.
abstract final class ScreenshotSeed {
  static const readiness = '78%';
  static const streak = '5d';
  static const practiceAvg = '4.2';

  static const marketListings = [
  _Listing(title: 'Google SWE Interview Bank Q2', seller: 'Interview Labs', price: 0.10, trust: 0.94, fresh: '2h ago'),
    _Listing(title: 'Meta Behavioral Patterns 2026', seller: 'Prep Collective', price: 0.08, trust: 0.91, fresh: '6h ago'),
    _Listing(title: 'System Design — Fintech', seller: 'ArchPrep', price: 0.15, trust: 0.88, fresh: '1d ago'),
    _Listing(title: 'Amazon Leadership Principles', seller: 'CareerForge', price: 0.12, trust: 0.90, fresh: '3h ago'),
  ];

  static const historySessions = [
    _History(company: 'Google', role: 'SWE L4', score: 4.5, spent: 0.40, date: 'May 19'),
    _History(company: 'Stripe', role: 'Backend', score: 4.0, spent: 0.25, date: 'May 17'),
    _History(company: 'Meta', role: 'PM', score: 3.8, spent: 0.32, date: 'May 14'),
  ];

  static const contributors = [
    _Contributor(name: 'alex_prep', contributions: 42, earned: 18.40),
    _Contributor(name: 'career_ninja', contributions: 37, earned: 15.20),
    _Contributor(name: 'offer_hunter', contributions: 29, earned: 11.80),
  ];

  static MockInterviewSession mockInterviewCaptureSession() {
    return MockInterviewSession(
      id: 'capture-demo',
      company: 'Google',
      role: 'Software Engineer',
      startedAt: DateTime.now().subtract(const Duration(minutes: 12)),
      completedAt: null,
      spentUsd: 0.18,
      questions: [
        InterviewQuestion(
          id: 'q1',
          question: 'Tell me about a time you had to make a decision with incomplete data.',
          category: 'behavioral',
          difficulty: 'medium',
          company: 'Google',
          role: 'Software Engineer',
          keyPoints: const ['Situation', 'Task', 'Action', 'Result', 'Metrics'],
          reportedAt: DateTime.now(),
        ),
        InterviewQuestion(
          id: 'q2',
          question: 'Describe a situation where you disagreed with your manager.',
          category: 'behavioral',
          difficulty: 'medium',
          company: 'Google',
          role: 'Software Engineer',
          keyPoints: const ['Respectful disagreement', 'Data-driven argument', 'Outcome'],
          reportedAt: DateTime.now(),
        ),
      ],
      answers: const {
        'q1':
            'At my previous role we had partial telemetry during an outage. I gathered what we knew, outlined risks, and proposed a staged rollback...',
      },
      scores: const {'q1': 0.82},
      feedback: const {
        'q1':
            'Strong STAR structure. Add a clearer metric in the Result section (latency recovered, users impacted).',
      },
    );
  }
}

class _Listing {
  const _Listing({
    required this.title,
    required this.seller,
    required this.price,
    required this.trust,
    required this.fresh,
  });

  final String title;
  final String seller;
  final double price;
  final double trust;
  final String fresh;
}

class _History {
  const _History({
    required this.company,
    required this.role,
    required this.score,
    required this.spent,
    required this.date,
  });

  final String company;
  final String role;
  final double score;
  final double spent;
  final String date;
}

class _Contributor {
  const _Contributor({
    required this.name,
    required this.contributions,
    required this.earned,
  });

  final String name;
  final int contributions;
  final double earned;
}
