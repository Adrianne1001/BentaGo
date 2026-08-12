import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/period.dart';
import '../core/theme.dart';
import '../data/report_repository.dart';
import '../state/providers.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'reports_screen.dart';
import 'sales_table_screen.dart';
import 'settings_screen.dart';

/// The closing-time screen: what came in today, what is owed, how the week is
/// going. Summary before detail, and every number is one tap from the records
/// behind it.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todaySummaryProvider);
    final week = ref.watch(thisWeekSummaryProvider);
    final month = ref.watch(thisMonthSummaryProvider);
    final recent = ref.watch(recentDaysProvider(7));
    final outstanding = ref.watch(totalOutstandingProvider);
    final debtors = ref.watch(debtorCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_rows_outlined),
            tooltip: 'Sales records',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SalesTableScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refreshData(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Text(
              Dates.readableDay(DateTime.now()),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colors.muted,
              ),
            ),
            const SizedBox(height: 14),

            AsyncBlock<PeriodSummary>(
              value: today,
              loadingHeight: 190,
              builder: (summary) => _TodayBlock(summary: summary),
            ),
            const SizedBox(height: 10),

            // Seven-day trend. Today is painted in the accent so the eye lands
            // on it without needing a legend.
            SectionCard(
              title: 'Last 7 days',
              subtitle: 'Sales per day. Green is estimated profit.',
              action: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReportsScreen(),
                  ),
                ),
                child: const Text('Full report'),
              ),
              child: AsyncBlock<List<DailyPoint>>(
                value: recent,
                loadingHeight: 180,
                builder: (points) {
                  final todayKey = Dates.dayKey(DateTime.now());
                  return Column(
                    children: [
                      BarChartView(
                        height: 176,
                        bars: [
                          for (final point in points)
                            ChartBar(
                              label: Dates.weekday(point.day),
                              value: point.revenueCentavos,
                              secondaryValue: point.profitCentavos > 0
                                  ? point.profitCentavos
                                  : null,
                              emphasized: point.dayKey == todayKey,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _WeekFooter(points: points),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: AsyncBlock<PeriodSummary>(
                    value: week,
                    loadingHeight: 96,
                    builder: (summary) => StatTile(
                      label: 'This week',
                      value: Money.formatShort(summary.revenueCentavos),
                      caption: '${summary.saleCount} sales · '
                          '${Money.formatShort(summary.grossProfitCentavos)} profit',
                      icon: Icons.calendar_view_week,
                      onTap: () => _openReports(context, ref, PeriodKind.week),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AsyncBlock<PeriodSummary>(
                    value: month,
                    loadingHeight: 96,
                    builder: (summary) => StatTile(
                      label: 'This month',
                      value: Money.formatShort(summary.revenueCentavos),
                      caption: '${summary.saleCount} sales · '
                          '${Money.formatShort(summary.grossProfitCentavos)} profit',
                      icon: Icons.calendar_month,
                      onTap: () => _openReports(context, ref, PeriodKind.month),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            AsyncBlock<PeriodSummary>(
              value: today,
              loadingHeight: 120,
              builder: (summary) {
                if (summary.saleCount == 0) return const SizedBox.shrink();
                return Column(
                  children: [
                    SectionCard(
                      title: 'How people paid today',
                      child: ProportionBar(
                        slices: [
                          ProportionSlice(
                            label: 'Cash',
                            value: summary.cashSalesCentavos,
                            color: context.colors.cashTint,
                          ),
                          ProportionSlice(
                            label: 'Credit',
                            value: summary.creditSalesCentavos,
                            color: context.colors.creditTint,
                          ),
                          ProportionSlice(
                            label: 'GCash',
                            value: summary.gcashSalesCentavos,
                            color: context.colors.gcashTint,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              },
            ),

            _TopProductsCard(
              period: Period.of(PeriodKind.week, DateTime.now()),
            ),
            const SizedBox(height: 10),

            AsyncBlock<int>(
              value: outstanding,
              loadingHeight: 92,
              builder: (total) {
                final count = debtors.valueOrNull ?? 0;
                if (total == 0) {
                  return const StatTile(
                    label: 'Credit outstanding',
                    value: 'None',
                    caption: 'Nobody owes anything right now.',
                    tone: StatTone.good,
                    icon: Icons.check_circle_outline,
                  );
                }
                return StatTile(
                  label: 'Credit outstanding',
                  value: Money.format(total),
                  caption: count == 1
                      ? '1 person owes money'
                      : '$count people owe money',
                  tone: StatTone.warn,
                  icon: Icons.receipt_long,
                );
              },
            ),
            const SizedBox(height: 10),

            const _BackupStatusCard(),
          ],
        ),
      ),
    );
  }

  void _openReports(BuildContext context, WidgetRef ref, PeriodKind kind) {
    ref.read(selectedPeriodProvider.notifier).state =
        Period.of(kind, DateTime.now());
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
    );
  }
}

class _TodayBlock extends StatelessWidget {
  const _TodayBlock({required this.summary});

  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StatTile(
          large: true,
          label: "Today's sales",
          value: Money.format(summary.revenueCentavos),
          caption: summary.saleCount == 0
              ? 'No sales recorded today yet.'
              : '${summary.saleCount} sales · ${summary.itemCount} items',
          icon: Icons.trending_up,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: "Today's profit",
                value: Money.formatShort(summary.grossProfitCentavos),
                caption: summary.profitIsEstimate
                    ? 'Estimated — some products have no cost set.'
                    : summary.marginPercent == null
                        ? null
                        : '${summary.marginPercent!.round()}% margin',
                tone: StatTone.good,
                icon: Icons.savings_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Cash received',
                value: Money.formatShort(summary.cashCollectedCentavos),
                caption: summary.creditPaymentsCentavos > 0
                    ? 'Includes ${Money.formatShort(summary.creditPaymentsCentavos)} '
                        'paid on credit'
                    : 'Credit sales not included.',
                icon: Icons.payments_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WeekFooter extends StatelessWidget {
  const _WeekFooter({required this.points});

  final List<DailyPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    final total = points.fold<int>(0, (s, p) => s + p.revenueCentavos);
    final active = points.where((p) => p.saleCount > 0).length;
    final average = active == 0 ? 0 : (total / active).round();

    var best = points.first;
    for (final point in points) {
      if (point.revenueCentavos > best.revenueCentavos) best = point;
    }

    return Row(
      children: [
        Expanded(
          child: _FooterStat(
            label: 'Total',
            value: Money.formatShort(total),
          ),
        ),
        Expanded(
          child: _FooterStat(
            label: 'Per day',
            value: Money.formatShort(average),
          ),
        ),
        Expanded(
          child: _FooterStat(
            label: 'Best day',
            value:
                best.revenueCentavos == 0 ? '--' : Dates.weekday(best.day),
          ),
        ),
      ],
    );
  }
}

class _FooterStat extends StatelessWidget {
  const _FooterStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9.5,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
            color: context.colors.muted,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _TopProductsCard extends ConsumerWidget {
  const _TopProductsCard({required this.period});

  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(topProductsProvider(period));

    return SectionCard(
      title: 'Best sellers this week',
      subtitle: 'By value sold',
      child: AsyncBlock<List<ProductStat>>(
        value: stats,
        loadingHeight: 140,
        builder: (items) => RankedBarList(
          emptyMessage: 'No sales this week yet.',
          rows: [
            for (final stat in items.take(5))
              RankedBarRow(
                label: stat.name,
                value: stat.revenueCentavos,
                trailing: '${stat.qty} pc',
              ),
          ],
        ),
      ),
    );
  }
}

class _BackupStatusCard extends ConsumerWidget {
  const _BackupStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastBackupProvider);

    return AsyncBlock<DateTime?>(
      value: last,
      loadingHeight: 88,
      builder: (when) {
        final days =
            when == null ? null : DateTime.now().difference(when).inDays;
        // Amber past a week: on-device backups only help if they are recent.
        final stale = days == null || days > 7;

        return StatTile(
          label: 'Last backup',
          value: when == null ? 'None yet' : Dates.relativeDay(when),
          caption: when == null
              ? 'Make a backup in Settings.'
              : '${Dates.readableDay(when)} · automatic every month',
          tone: stale ? StatTone.warn : StatTone.neutral,
          icon: Icons.backup_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        );
      },
    );
  }
}
