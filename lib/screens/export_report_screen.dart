import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/period.dart';
import '../core/theme.dart';
import '../data/export_service.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Choosing a report is two decisions -- how far it reaches and what file to
/// make -- so the screen is two questions and a button.
///
/// The range is picked the same way the Reports screen is browsed: choose the
/// size of the window, then step it with the arrows. That covers day, month,
/// quarter and year without a date picker, and the live count underneath means
/// an empty range is obvious before anything is written rather than after the
/// file has been opened.
class ExportReportScreen extends ConsumerWidget {
  const ExportReportScreen({super.key});

  static const List<PeriodKind> _kinds = [
    PeriodKind.day,
    PeriodKind.month,
    PeriodKind.quarter,
    PeriodKind.year,
    PeriodKind.custom,
  ];

  Future<void> _pickCustomRange(BuildContext context, WidgetRef ref) async {
    final period = ref.read(exportPeriodProvider);
    final firstSale = ref.read(firstSaleDateProvider).valueOrNull;
    final now = DateTime.now();

    final picked = await showDateRangePicker(
      context: context,
      firstDate: Dates.startOfDay(
        firstSale ?? DateTime(now.year - 3),
      ),
      lastDate: Dates.endOfDay(now),
      initialDateRange: DateTimeRange(
        start: Dates.startOfDay(period.start),
        end: Dates.startOfDay(period.end.isAfter(now) ? now : period.end),
      ),
      helpText: 'Pick the first and last day',
      saveText: 'Use these dates',
    );
    if (picked == null) return;
    ref.read(exportPeriodProvider.notifier).state =
        Period.range(picked.start, picked.end);
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final period = ref.read(exportPeriodProvider);
    final format = ref.read(exportFormatProvider);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final file =
          await ref.read(exportServiceProvider).export(period, format);
      if (context.mounted) Navigator.pop(context); // the spinner

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'BentaGo — sales report ${period.label}',
        text: 'BentaGo sales report for ${period.label}.',
      );
      if (context.mounted) {
        showToast(context, 'Saved as ${file.uri.pathSegments.last}');
      }
    } on Object catch (error) {
      if (context.mounted) {
        Navigator.pop(context); // the spinner
        showToast(context, 'Export failed: $error', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(exportPeriodProvider);
    final format = ref.watch(exportFormatProvider);
    final preview = ref.watch(exportPreviewProvider(period));
    final isCustom = period.kind == PeriodKind.custom;

    return Scaffold(
      appBar: AppBar(title: const Text('Export report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const _Heading(text: 'WHAT TO COVER'),
          const SizedBox(height: 8),

          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final kind in _kinds)
                ChoiceChip(
                  label: Text(
                    kind == PeriodKind.custom ? 'Start–end' : kind.label,
                  ),
                  selected: period.kind == kind,
                  onSelected: (_) {
                    if (kind == PeriodKind.custom) {
                      _pickCustomRange(context, ref);
                      return;
                    }
                    ref.read(exportPeriodProvider.notifier).state =
                        period.withKind(kind);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),

          SectionCard(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Earlier',
                      onPressed: () =>
                          ref.read(exportPeriodProvider.notifier).state =
                              period.shift(-1),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            period.label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${Dates.readableDay(period.start)} → '
                            '${Dates.readableDay(period.end)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: context.colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Later',
                      // Nothing has happened in the future yet.
                      onPressed: period.containsToday
                          ? null
                          : () => ref
                              .read(exportPeriodProvider.notifier)
                              .state = period.shift(1),
                    ),
                  ],
                ),
                if (isCustom)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton.icon(
                      onPressed: () => _pickCustomRange(context, ref),
                      icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                      label: const Text('Change dates'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          _PreviewCard(preview: preview),
          const SizedBox(height: 18),

          const _Heading(text: 'FILE TYPE'),
          const SizedBox(height: 8),
          for (final option in ExportFormat.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FormatCard(
                format: option,
                selected: format == option,
                onTap: () =>
                    ref.read(exportFormatProvider.notifier).state = option,
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            // Writing an empty report is allowed -- a month with no sales is a
            // real answer -- but the preview above has already said so.
            onPressed: preview.isLoading ? null : () => _export(context, ref),
            icon: const Icon(Icons.ios_share, size: 19),
            label: Text('Export ${format.label}'),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w700,
        color: context.colors.muted,
      ),
    );
  }
}

/// The same numbers that will head the file, shown before it is written.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final AsyncValue<ReportData> preview;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: AsyncBlock<ReportData>(
        value: preview,
        loadingHeight: 74,
        builder: (data) {
          if (data.isEmpty) {
            return Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 19,
                  color: context.colors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No sales in this range. The report will come out empty.',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.muted,
                    ),
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Figure(
                      label: 'GROSS SALES',
                      value: Money.formatShort(data.grossCentavos),
                    ),
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'PROFIT',
                      value: Money.formatShort(data.profitCentavos),
                      color: context.colors.good,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${data.lines.length} lines · ${data.qty} items · '
                '${data.saleCount} '
                '${data.saleCount == 1 ? 'transaction' : 'transactions'}',
                style: TextStyle(fontSize: 12.5, color: context.colors.muted),
              ),
              if (data.profitIsEstimate)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Some items have no cost price on file, so profit is an '
                    'estimate.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: context.colors.warn,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w700,
            color: context.colors.muted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.format,
    required this.selected,
    required this.onTap,
  });

  final ExportFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? context.scheme.primary.withValues(alpha: 0.10)
          : context.scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? context.scheme.primary
                  : context.scheme.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                format == ExportFormat.excel
                    ? Icons.table_chart_outlined
                    : Icons.picture_as_pdf_outlined,
                color: selected ? context.scheme.primary : context.colors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      format.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      format.description,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: context.colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: context.scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
