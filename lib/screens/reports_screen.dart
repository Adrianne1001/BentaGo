import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/period.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/report_repository.dart';
import '../state/providers.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'sales_table_screen.dart';

/// Ulat: one period at a time, day / week / month, driven by a single [Period]
/// so all three views share the same queries and the same layout.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _addExpense(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_ExpenseDraft>(
      context: context,
      builder: (context) => const _ExpenseDialog(),
    );
    if (result == null) return;

    await ref.read(salesRepositoryProvider).addExpense(
          amountCentavos: result.amountCentavos,
          category: result.category,
          note: result.note,
        );
    ref.refreshData();
    if (context.mounted) showToast(context, 'Naitala ang gastos');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(selectedPeriodProvider);
    final summary = ref.watch(periodSummaryProvider(period));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ulat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_rows_outlined),
            tooltip: 'Talaan ng benta',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SalesTableScreen(initialPeriod: period),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _PeriodSelector(
            period: period,
            onKindChanged: (kind) => ref
                .read(selectedPeriodProvider.notifier)
                .state = period.withKind(kind),
            onShift: (steps) => ref
                .read(selectedPeriodProvider.notifier)
                .state = period.shift(steps),
          ),
          const SizedBox(height: 14),

          AsyncBlock<PeriodSummary>(
            value: summary,
            loadingHeight: 220,
            builder: (data) => _SummaryGrid(summary: data),
          ),
          const SizedBox(height: 10),

          _TrendCard(period: period),
          const SizedBox(height: 10),

          AsyncBlock<PeriodSummary>(
            value: summary,
            loadingHeight: 110,
            builder: (data) {
              if (data.saleCount == 0) return const SizedBox.shrink();
              return Column(
                children: [
                  SectionCard(
                    title: 'Paraan ng bayad',
                    subtitle: 'Ayon sa halaga ng benta sa panahong ito',
                    child: ProportionBar(
                      slices: [
                        ProportionSlice(
                          label: 'Cash',
                          value: data.cashSalesCentavos,
                          color: context.colors.cashTint,
                        ),
                        ProportionSlice(
                          label: 'Utang',
                          value: data.utangSalesCentavos,
                          color: context.colors.utangTint,
                        ),
                        ProportionSlice(
                          label: 'GCash',
                          value: data.gcashSalesCentavos,
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

          _TopProductsCard(period: period),
          const SizedBox(height: 10),

          _CategoryCard(period: period),
          const SizedBox(height: 10),

          _ExpensesCard(
            period: period,
            onAdd: () => _addExpense(context, ref),
          ),
          const SizedBox(height: 10),

          if (period.kind == PeriodKind.month) const _YearTrendCard(),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.period,
    required this.onKindChanged,
    required this.onShift,
  });

  final Period period;
  final ValueChanged<PeriodKind> onKindChanged;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SegmentedButton<PeriodKind>(
          segments: [
            for (final kind in PeriodKind.values)
              ButtonSegment<PeriodKind>(
                value: kind,
                label: Text(kind.label),
              ),
          ],
          selected: {period.kind},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onKindChanged(selection.first),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Nauna',
              onPressed: () => onShift(-1),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    period.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    period.subLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.muted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Susunod',
              // Nothing has happened in the future yet.
              onPressed: period.containsToday ? null : () => onShift(1),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) {
      return SectionCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.insert_chart_outlined,
                  size: 34,
                  color: context.colors.muted,
                ),
                const SizedBox(height: 10),
                Text(
                  'Walang naitalang benta sa panahong ito.',
                  style: TextStyle(color: context.colors.muted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        StatTile(
          large: true,
          label: 'Kabuuang benta',
          value: Money.format(summary.revenueCentavos),
          caption: '${summary.saleCount} benta · ${summary.itemCount} piraso · '
              'katamtaman ${Money.formatShort(summary.averageSaleCentavos)}',
          icon: Icons.trending_up,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Kita bago gastos',
                value: Money.formatShort(summary.grossProfitCentavos),
                caption: summary.profitIsEstimate
                    ? 'Tinatayang kita lang -- may paninda na walang puhunan.'
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
                label: 'Gastos',
                value: Money.formatShort(summary.expensesCentavos),
                caption: summary.expensesCentavos == 0
                    ? 'Wala pang naitalang gastos.'
                    : null,
                tone: StatTone.warn,
                icon: Icons.receipt_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Natirang kita',
                value: Money.formatShort(summary.netProfitCentavos),
                caption: 'Kita bawas gastos',
                tone: summary.netProfitCentavos >= 0
                    ? StatTone.good
                    : StatTone.danger,
                icon: Icons.account_balance_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                label: 'Cash na natanggap',
                value: Money.formatShort(summary.cashCollectedCentavos),
                caption: summary.utangSalesCentavos > 0
                    ? '${Money.formatShort(summary.utangSalesCentavos)} ang '
                        'napunta sa utang'
                    : 'Lahat ay bayad agad.',
                icon: Icons.payments_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// For a single day the useful shape is hours, not one lone bar. For a week or
/// month it is days.
class _TrendCard extends ConsumerWidget {
  const _TrendCard({required this.period});

  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (period.kind == PeriodKind.day) {
      final hourly = ref.watch(hourlyStatsProvider(period));
      return SectionCard(
        title: 'Kada oras',
        subtitle: 'Kailan dumadagsa ang tao',
        child: AsyncBlock<List<HourBucket>>(
          value: hourly,
          loadingHeight: 180,
          builder: (buckets) {
            // Trim to trading hours so the chart is not mostly empty night.
            final active = buckets.where((b) => b.revenueCentavos > 0).toList();
            final from = active.isEmpty
                ? 6
                : (active.first.hour - 1).clamp(0, 23);
            final to = active.isEmpty
                ? 21
                : (active.last.hour + 1).clamp(0, 23);
            final window =
                buckets.where((b) => b.hour >= from && b.hour <= to).toList();

            return BarChartView(
              height: 172,
              maxLabelEvery: window.length > 10 ? 3 : 2,
              bars: [
                for (final bucket in window)
                  ChartBar(
                    label: bucket.label,
                    value: bucket.revenueCentavos,
                  ),
              ],
            );
          },
        ),
      );
    }

    final series = ref.watch(dailySeriesProvider(period));
    return SectionCard(
      title: 'Kada araw',
      subtitle: 'Ang berde ay tinatayang kita',
      child: AsyncBlock<List<DailyPoint>>(
        value: series,
        loadingHeight: 180,
        builder: (points) {
          final todayKey = Dates.dayKey(DateTime.now());
          return BarChartView(
            height: 176,
            maxLabelEvery: points.length > 14 ? 4 : 1,
            bars: [
              for (final point in points)
                ChartBar(
                  label: period.kind == PeriodKind.week
                      ? Dates.weekday(point.day)
                      : '${point.day.day}',
                  value: point.revenueCentavos,
                  secondaryValue:
                      point.profitCentavos > 0 ? point.profitCentavos : null,
                  emphasized: point.dayKey == todayKey,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _YearTrendCard extends ConsumerWidget {
  const _YearTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final months = ref.watch(monthlySeriesProvider(12));

    return SectionCard(
      title: 'Huling 12 buwan',
      subtitle: 'Buwanang benta',
      child: AsyncBlock<List<DailyPoint>>(
        value: months,
        loadingHeight: 180,
        builder: (points) {
          final thisMonth = Dates.monthKey(DateTime.now());
          return BarChartView(
            height: 176,
            maxLabelEvery: 2,
            bars: [
              for (final point in points)
                ChartBar(
                  label: Dates.monthShort(point.day),
                  value: point.revenueCentavos,
                  secondaryValue:
                      point.profitCentavos > 0 ? point.profitCentavos : null,
                  emphasized: Dates.monthKey(point.day) == thisMonth,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TopProductsCard extends ConsumerStatefulWidget {
  const _TopProductsCard({required this.period});

  final Period period;

  @override
  ConsumerState<_TopProductsCard> createState() => _TopProductsCardState();
}

class _TopProductsCardState extends ConsumerState<_TopProductsCard> {
  bool _showWorst = false;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(topProductsProvider(widget.period));

    return SectionCard(
      title: _showWorst ? 'Mabagal maubos' : 'Mabili',
      subtitle: 'Ayon sa halaga ng nabenta',
      action: TextButton(
        onPressed: () => setState(() => _showWorst = !_showWorst),
        child: Text(_showWorst ? 'Mabili' : 'Mabagal'),
      ),
      child: AsyncBlock<List<ProductStat>>(
        value: stats,
        loadingHeight: 170,
        builder: (items) {
          // The "slow movers" view reverses the same top-N list rather than
          // querying the tail, so a product with no sales at all does not
          // crowd out the ones that are merely slow.
          final rows = _showWorst ? items.reversed.toList() : items;
          return RankedBarList(
            emptyMessage: 'Wala pang benta sa panahong ito.',
            rows: [
              for (final stat in rows.take(8))
                RankedBarRow(
                  label: stat.name,
                  value: stat.revenueCentavos,
                  trailing: '${stat.qty} pc',
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  const _CategoryCard({required this.period});

  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(categoryStatsProvider(period));

    return SectionCard(
      title: 'Ayon sa kategorya',
      child: AsyncBlock<List<CategoryStat>>(
        value: stats,
        loadingHeight: 140,
        builder: (items) => RankedBarList(
          emptyMessage: 'Wala pang datos.',
          rows: [
            for (final stat in items)
              RankedBarRow(
                label: stat.category,
                value: stat.revenueCentavos,
                trailing: '${stat.qty} pc',
                color: context.colors.accent,
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpensesCard extends ConsumerWidget {
  const _ExpensesCard({required this.period, required this.onAdd});

  final Period period;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breakdown = ref.watch(expenseBreakdownProvider(period));

    return SectionCard(
      title: 'Gastos',
      subtitle: 'Kuryente, renta, pamasahe at iba pa',
      action: TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Magdagdag'),
      ),
      child: AsyncBlock<List<Expense>>(
        value: breakdown,
        loadingHeight: 110,
        builder: (items) => RankedBarList(
          emptyMessage: 'Wala pang naitalang gastos sa panahong ito.',
          rows: [
            for (final expense in items)
              RankedBarRow(
                label: expense.category,
                value: expense.amountCentavos,
                color: context.colors.warn,
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseDraft {
  const _ExpenseDraft({
    required this.amountCentavos,
    required this.category,
    this.note,
  });

  final int amountCentavos;
  final String category;
  final String? note;
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog();

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _category = expenseCategories.first;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bagong gastos'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                decoration: const InputDecoration(
                  prefixText: '₱ ',
                  hintText: '0.00',
                  labelText: 'Halaga',
                ),
                validator: (raw) {
                  final parsed = Money.parse(raw ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Maglagay ng halaga.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Para saan?',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.colors.muted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in expenseCategories)
                    ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Paalala',
                  hintText: 'Opsyonal',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kanselahin'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.pop(
              context,
              _ExpenseDraft(
                amountCentavos: Money.parse(_amount.text)!,
                category: _category,
                note: _note.text.trim().isEmpty ? null : _note.text.trim(),
              ),
            );
          },
          child: const Text('Itala'),
        ),
      ],
    );
  }
}
