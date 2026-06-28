import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/screenshot_demo.dart';
import '../demo/screenshot_seed.dart';
import '../models/interview_question.dart';
import '../models/mock_interview_session.dart';
import '../services/mock_interview_service.dart';
import '../state/app_state.dart';

/// Live mock interview — hub scoring with local fallback.
class MockInterviewScreen extends StatefulWidget {
  const MockInterviewScreen({super.key, this.captureSession});

  /// Screenshot pipeline only (`SCREENSHOT_DEMO`).
  final MockInterviewSession? captureSession;

  @override
  State<MockInterviewScreen> createState() => _MockInterviewScreenState();
}

class _MockInterviewScreenState extends State<MockInterviewScreen> {
  MockInterviewSession? _session;
  int _index = 0;
  bool _loading = true;
  bool _scoring = false;
  String? _error;
  final _answerController = TextEditingController();
  String? _lastFeedback;
  double? _lastScore;

  @override
  void initState() {
    super.initState();
    if (widget.captureSession != null) {
      _session = widget.captureSession;
      _index = 1;
      _lastFeedback = _session!.feedback.values.firstOrNull;
      _lastScore = _session!.scores.values.firstOrNull;
      _answerController.text = _session!.answers.values.firstOrNull ?? '';
      _loading = false;
      return;
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final app = context.read<AppState>();
    final company = app.targetCompany?.trim();
    final role = app.targetRole?.trim();
    if (company == null || company.isEmpty || role == null || role.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Set target company and role in onboarding first.';
      });
      return;
    }
    try {
      final service = context.read<MockInterviewService>();
      final session = await service.startSession(company: company, role: role);
      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not start session: $e';
      });
    }
  }

  InterviewQuestion? get _question {
    final s = _session;
    if (s == null || s.questions.isEmpty) return null;
    if (_index >= s.questions.length) return null;
    return s.questions[_index];
  }

  Future<void> _submitAnswer() async {
    final q = _question;
    final session = _session;
    if (q == null || session == null) return;
    final answer = _answerController.text.trim();
    if (answer.isEmpty) return;

    setState(() => _scoring = true);
    final service = context.read<MockInterviewService>();
    final result = await service.scoreAnswer(
      session: session,
      question: q,
      answer: answer,
    );
    if (!mounted) return;
    setState(() {
      _scoring = false;
      _lastScore = result.score;
      _lastFeedback = result.feedback;
    });
  }

  Future<void> _nextQuestion() async {
    final session = _session;
    if (session == null) return;
    if (_index + 1 >= session.questions.length) {
      await context.read<MockInterviewService>().completeSession(session);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _index++;
      _answerController.clear();
      _lastFeedback = session.feedback[session.questions[_index].id];
      _lastScore = session.scores[session.questions[_index].id];
    });
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _session;
    final question = _question;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mock Interview'),
        actions: [
          if (session != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${session.company} · ${session.role}',
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : session == null || question == null
                  ? const Center(child: Text('No questions available.'))
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        LinearProgressIndicator(
                          value: (_index + 1) / session.questions.length,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Question ${_index + 1} of ${session.questions.length}',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Chip(label: Text(question.category)),
                        const SizedBox(height: 12),
                        Text(
                          question.question,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _answerController,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Your answer',
                            hintText: 'Use STAR: Situation, Task, Action, Result…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: _scoring ? null : _submitAnswer,
                              child: Text(_scoring ? 'Scoring…' : 'Get feedback'),
                            ),
                            const SizedBox(width: 12),
                            if (_lastScore != null)
                              Text(
                                'Score ${(100 * _lastScore!).round()}%',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                        if (_lastFeedback != null) ...[
                          const SizedBox(height: 16),
                          Card(
                            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Feedback', style: theme.textTheme.titleMedium),
                                  const SizedBox(height: 8),
                                  Text(_lastFeedback!),
                                  if (question.keyPoints.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      'Key points: ${question.keyPoints.join(' · ')}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: _lastScore == null ? null : _nextQuestion,
                            child: Text(
                              _index + 1 >= session.questions.length
                                  ? 'Finish session'
                                  : 'Next question',
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

/// Opens mock interview — capture seed only when [screenshotDemo].
Future<bool?> openMockInterview(BuildContext context) {
  final capture = screenshotDemo ? ScreenshotSeed.mockInterviewCaptureSession() : null;
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => MockInterviewScreen(captureSession: capture),
    ),
  );
}
