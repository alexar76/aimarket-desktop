import 'package:aicom_desktop_core/aicom_desktop_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/screenshot_demo.dart';
import '../demo/screenshot_seed.dart';
import '../models/mock_interview_session.dart';
import '../services/marketplace_service.dart';
import '../services/mock_interview_service.dart';
import '../state/app_state.dart';
import '../widgets/marketplace_status_bar.dart';
import 'mock_interview_screen.dart';

/// Main shell screen with bottom navigation and scaffold.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _selectedIndex = 0;
  List<MockInterviewSession> _sessions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadSessions());
  }

  Future<void> _reloadSessions() async {
    if (screenshotDemo) return;
    final sessions = await context.read<MockInterviewService>().loadHistory();
    if (!mounted) return;
    setState(() => _sessions = sessions);
  }

  Future<void> _openMockInterview() async {
    final refreshed = await openMockInterview(context);
    if (refreshed == true) await _reloadSessions();
  }

  @override
  Widget build(BuildContext context) {
    final marketplace = context.read<MarketplaceService>();
    final balance = marketplace.channelBalance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Interview Prep Coach'),
        actions: [
          const MarketplaceStatusBar(),
          const AicomSettingsButton(),
        ],
      ),
      body: Column(
        children: [
          _EconomicsStrip(balance: balance ?? 0.0),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.school_outlined),
            selectedIcon: const Icon(Icons.school),
            label: context.t('navPrep'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.trending_up_outlined),
            selectedIcon: const Icon(Icons.trending_up),
            label: context.t('navMarket'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: context.t('navHistory'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: context.t('navCommunity'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _PrepTab(
          onMockInterview: _openMockInterview,
          onGoMarket: () => setState(() => _selectedIndex = 1),
          sessions: _sessions,
        );
      case 1:
        return const _MarketTab();
      case 2:
        return _HistoryTab(sessions: _sessions);
      case 3:
        return const _CommunityTab();
      default:
        return _PrepTab(
          onMockInterview: _openMockInterview,
          onGoMarket: () => setState(() => _selectedIndex = 1),
          sessions: _sessions,
        );
    }
  }
}

class _EconomicsStrip extends StatelessWidget {
  const _EconomicsStrip({required this.balance});

  final double balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.hub, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'AI Market · hub.aicom.io · channel \$${balance.toStringAsFixed(2)} · TEE verify on',
                style: theme.textTheme.labelLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(onPressed: () {}, child: const Text('Add \$5')),
          ],
        ),
      ),
    );
  }
}

class _PrepTab extends StatelessWidget {
  const _PrepTab({
    required this.onMockInterview,
    required this.onGoMarket,
    required this.sessions,
  });

  final VoidCallback onMockInterview;
  final VoidCallback onGoMarket;
  final List<MockInterviewSession> sessions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _statsForDisplay(sessions);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          context.t('todaysPrep'),
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Company-specific banks with freshness signals from the marketplace.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _HeroStatRow(
          stats: [
            _StatChip(label: 'Readiness', value: stats.readiness, icon: Icons.speed),
            _StatChip(label: 'Streak', value: stats.streak, icon: Icons.local_fire_department),
            _StatChip(label: 'Practice avg', value: stats.practiceAvg, icon: Icons.star),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: const Icon(Icons.search),
            ),
            title: const Text('Discover Question Banks'),
            subtitle: const Text('Google SWE · Meta PM · Amazon SDE — from \$0.08/call'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onGoMarket,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: const Icon(Icons.record_voice_over),
            ),
            title: Text(context.t('mockInterview')),
            subtitle: const Text('AI simulation with TEE-verified scoring'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onMockInterview,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.tertiaryContainer,
              child: const Icon(Icons.bolt),
            ),
            title: const Text('What was asked this week'),
            subtitle: Text(
              screenshotDemo
                  ? 'Fresh signals · 14 new reports at Google'
                  : 'Pull recent interview signals from the marketplace',
            ),
            trailing: screenshotDemo
                ? Chip(label: Text('LIVE', style: TextStyle(color: theme.colorScheme.primary)))
                : null,
            onTap: onGoMarket,
          ),
        ),
      ],
    );
  }
}

class _MarketTab extends StatefulWidget {
  const _MarketTab();

  @override
  State<_MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<_MarketTab> {
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!screenshotDemo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _discover());
    }
  }

  Future<void> _discover() async {
    final app = context.read<AppState>();
    final company = app.targetCompany;
    final role = app.targetRole;
    if (company == null || role == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<MarketplaceService>().discoverInterviewQuestions(
            company: company,
            role: role,
          );
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_MarketListing> get _listings {
    if (screenshotDemo) {
      return ScreenshotSeed.marketListings
          .map(
            (l) => _MarketListing(
              title: l.title,
              seller: l.seller,
              price: l.price,
              trust: l.trust,
              fresh: l.fresh,
            ),
          )
          .toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listings = _listings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Marketplace', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Discover → Channel → Invoke → Settle. Pay per question bank with USDT micro-payments.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: InputDecoration(
            hintText: 'Intent: "Google SWE behavioral 2026"',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: FilledButton(
              onPressed: screenshotDemo ? null : _discover,
              child: const Text('Discover'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: theme.textTheme.bodySmall),
          ),
        if (listings.isEmpty && !screenshotDemo && !_loading)
          Text(
            'No listings yet. Connect wallet and run Discover against the hub.',
            style: theme.textTheme.bodyMedium,
          ),
        ...listings.map((l) => _MarketListingCard(listing: l)),
      ],
    );
  }
}

class _MarketListing {
  final String title;
  final String seller;
  final double price;
  final double trust;
  final String fresh;

  const _MarketListing({
    required this.title,
    required this.seller,
    required this.price,
    required this.trust,
    required this.fresh,
  });
}

class _MarketListingCard extends StatelessWidget {
  const _MarketListingCard({required this.listing});

  final _MarketListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(listing.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text('\$${listing.price.toStringAsFixed(2)}/call', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 6),
            Text('${listing.seller} · trust ${(listing.trust * 100).toStringAsFixed(0)}% · updated ${listing.fresh}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(onPressed: () {}, child: const Text('Preview')),
                const SizedBox(width: 8),
                FilledButton(onPressed: () {}, child: const Text('Open channel & invoke')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.sessions});

  final List<MockInterviewSession> sessions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = screenshotDemo
        ? ScreenshotSeed.historySessions
            .map(
              (s) => _SessionRow(
                company: s.company,
                role: s.role,
                score: s.score,
                spent: s.spent,
                date: s.date,
              ),
            )
            .toList()
        : sessions
            .where((s) => s.isComplete)
            .map(
              (s) => _SessionRow(
                company: s.company,
                role: s.role,
                score: (s.averageScore ?? 0) * 5,
                spent: s.spentUsd,
                date: _formatDate(s.completedAt ?? s.startedAt),
              ),
            )
            .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Session History', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Bill of Materials and TEE receipts for every invoke.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          Text(
            'Complete a mock interview to see session history here.',
            style: theme.textTheme.bodyMedium,
          ),
        ...rows.map((s) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Text(s.company[0])),
                title: Text('${s.company} · ${s.role}'),
                subtitle: Text('${s.date} · spent \$${s.spent.toStringAsFixed(2)} · score ${s.score}/5'),
                trailing: const Icon(Icons.receipt_long),
                onTap: () {},
              ),
            )),
      ],
    );
  }
}

class _SessionRow {
  final String company;
  final String role;
  final double score;
  final double spent;
  final String date;

  const _SessionRow({
    required this.company,
    required this.role,
    required this.score,
    required this.spent,
    required this.date,
  });
}

class _CommunityTab extends StatelessWidget {
  const _CommunityTab();

  @override
  Widget build(BuildContext context) {
    if (!screenshotDemo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Publish anonymized trajectories after a mock interview session.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final contributors = ScreenshotSeed.contributors;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Community Signals', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Sell anonymized trajectories — PII stripped on-device before upload.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Card(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.volunteer_activism, color: theme.colorScheme.primary, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Share your last mock', style: theme.textTheme.titleMedium),
                      Text('Earn ~\$0.50 per verified trajectory', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                FilledButton(onPressed: () {}, child: const Text('Publish')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Top contributors this week', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...contributors.asMap().entries.map((e) {
          final c = e.value;
          return ListTile(
            leading: CircleAvatar(child: Text('${e.key + 1}')),
            title: Text(c.name),
            subtitle: Text('${c.contributions} trajectories'),
            trailing: Text('+\$${c.earned.toStringAsFixed(2)}', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
          );
        }),
      ],
    );
  }
}

class _HeroStatRow extends StatelessWidget {
  const _HeroStatRow({required this.stats});

  final List<_StatChip> stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: stats
          .map((s) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Icon(s.icon, size: 20),
                          const SizedBox(height: 4),
                          Text(s.value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(s.label, style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _StatChip {
  final String label;
  final String value;
  final IconData icon;

  const _StatChip({required this.label, required this.value, required this.icon});
}

class _PrepStats {
  const _PrepStats(this.readiness, this.streak, this.practiceAvg);
  final String readiness;
  final String streak;
  final String practiceAvg;
}

_PrepStats _statsForDisplay(List<MockInterviewSession> sessions) {
  if (screenshotDemo) {
    return const _PrepStats(
      ScreenshotSeed.readiness,
      ScreenshotSeed.streak,
      ScreenshotSeed.practiceAvg,
    );
  }
  if (sessions.isEmpty) {
    return const _PrepStats('—', '—', '—');
  }
  final completed = sessions.where((s) => s.averageScore != null).toList();
  final avg = completed.isEmpty
      ? null
      : completed.map((s) => s.averageScore!).reduce((a, b) => a + b) /
          completed.length;
  return _PrepStats(
    completed.isEmpty ? '—' : '${((avg ?? 0) * 100).round()}%',
    '${sessions.length}d',
    avg == null ? '—' : (avg * 5).toStringAsFixed(1),
  );
}

String _formatDate(DateTime dt) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[dt.month - 1]} ${dt.day}';
}
