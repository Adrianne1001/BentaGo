import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/period.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Every transaction, as a table. This is the screen to open when a number on
/// the dashboard looks wrong -- filters narrow it down, and any row opens to
/// show the exact items that made up that sale.
class SalesTableScreen extends ConsumerStatefulWidget {
  const SalesTableScreen({super.key, this.initialPeriod});

  final Period? initialPeriod;

  @override
  ConsumerState<SalesTableScreen> createState() => _SalesTableScreenState();
}

class _SalesTableScreenState extends ConsumerState<SalesTableScreen> {
  @override
  void initState() {
    super.initState();
    final period = widget.initialPeriod;
    if (period != null) {
      // Applied after the first frame so the provider is not written to during
      // the build that is currently reading it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(salesQueryProvider.notifier).state =
            ref.read(salesQueryProvider).copyWith(period: period);
      });
    }
  }

  void _update(SalesQuery Function(SalesQuery current) transform) {
    final notifier = ref.read(salesQueryProvider.notifier);
    notifier.state = transform(notifier.state);
  }

  Future<void> _openSale(Sale sale) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _SaleDetailSheet(saleId: sale.id!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(salesQueryProvider);
    final sales = ref.watch(salesTableProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Talaan ng benta'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'voided':
                  _update(
                    (q) => q.copyWith(includeVoided: !q.includeVoided),
                  );
                case 'amount':
                  _update((q) => q.copyWith(orderBy: 'total_centavos DESC'));
                case 'recent':
                  _update((q) => q.copyWith(orderBy: 'sold_at DESC'));
                case 'oldest':
                  _update((q) => q.copyWith(orderBy: 'sold_at ASC'));
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String>(
                value: 'voided',
                checked: query.includeVoided,
                child: const Text('Isama ang binawi'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'recent',
                child: Text('Pinakabago sa taas'),
              ),
              const PopupMenuItem<String>(
                value: 'oldest',
                child: Text('Pinakaluma sa taas'),
              ),
              const PopupMenuItem<String>(
                value: 'amount',
                child: Text('Pinakamalaki sa taas'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AppSearchField(
              hint: 'Hanapin: paninda, pangalan, o numero',
              value: query.search,
              onChanged: (value) => _update((q) => q.copyWith(search: value)),
            ),
          ),
          _FilterRow(query: query, onUpdate: _update),
          const Divider(height: 1),
          Expanded(
            child: AsyncBlock<List<Sale>>(
              value: sales,
              loadingHeight: 300,
              builder: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Walang benta na tumutugma',
                    message: 'Baguhin ang filter o ang panahon sa taas.',
                  );
                }
                return Column(
                  children: [
                    _TableFooter(rows: rows),
                    const Divider(height: 1),
                    Expanded(
                      child: _SalesTable(rows: rows, onTap: _openSale),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.query, required this.onUpdate});

  final SalesQuery query;
  final void Function(SalesQuery Function(SalesQuery)) onUpdate;

  @override
  Widget build(BuildContext context) {
    final period = query.period;

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: ChoiceChip(
              label: Text(period == null ? 'Lahat ng panahon' : period.label),
              selected: period != null,
              avatar: const Icon(Icons.calendar_today, size: 15),
              onSelected: (_) {
                if (period != null) {
                  onUpdate((q) => q.copyWith(clearPeriod: true));
                  return;
                }
                onUpdate(
                  (q) => q.copyWith(
                    period: Period.of(PeriodKind.month, DateTime.now()),
                  ),
                );
              },
            ),
          ),
          if (period != null) ...[
            for (final kind in PeriodKind.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: ChoiceChip(
                  label: Text(kind.label),
                  selected: period.kind == kind,
                  onSelected: (_) =>
                      onUpdate((q) => q.copyWith(period: period.withKind(kind))),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              child: IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                tooltip: 'Nauna',
                onPressed: () =>
                    onUpdate((q) => q.copyWith(period: period.shift(-1))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              child: IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                tooltip: 'Susunod',
                onPressed: period.containsToday
                    ? null
                    : () =>
                        onUpdate((q) => q.copyWith(period: period.shift(1))),
              ),
            ),
          ],
          const SizedBox(width: 4),
          for (final type in PaymentType.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: FilterChip(
                label: Text(type.label),
                selected: query.paymentType == type,
                onSelected: (selected) => onUpdate(
                  (q) => selected
                      ? q.copyWith(paymentType: type)
                      : q.copyWith(clearPaymentType: true),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TableFooter extends StatelessWidget {
  const _TableFooter({required this.rows});

  final List<Sale> rows;

  @override
  Widget build(BuildContext context) {
    final live = rows.where((s) => !s.voided);
    final total = live.fold<int>(0, (sum, s) => sum + s.totalCentavos);
    final profit = live.fold<int>(0, (sum, s) => sum + s.profitCentavos);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: _MiniStat(
              label: 'Bilang',
              value: '${live.length}',
            ),
          ),
          Expanded(
            child: _MiniStat(
              label: 'Kabuuan',
              value: Money.formatShort(total),
            ),
          ),
          Expanded(
            child: _MiniStat(
              label: 'Kita',
              value: Money.formatShort(profit),
              color: context.colors.good,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
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
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _SalesTable extends StatelessWidget {
  const _SalesTable({required this.rows, required this.onTap});

  final List<Sale> rows;
  final ValueChanged<Sale> onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: context.colors.muted,
          ),
          dataTextStyle: const TextStyle(
            fontSize: 13.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          columnSpacing: 20,
          horizontalMargin: 16,
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('PETSA')),
            DataColumn(label: Text('ORAS')),
            DataColumn(label: Text('PC'), numeric: true),
            DataColumn(label: Text('BAYAD')),
            DataColumn(label: Text('CUSTOMER')),
            DataColumn(label: Text('TOTAL'), numeric: true),
            DataColumn(label: Text('KITA'), numeric: true),
          ],
          rows: [
            for (final sale in rows)
              DataRow(
                onSelectChanged: (_) => onTap(sale),
                cells: [
                  DataCell(
                    Text(
                      '${sale.id}',
                      style: TextStyle(color: context.colors.muted),
                    ),
                  ),
                  DataCell(Text(Dates.shortDay(sale.soldAt))),
                  DataCell(
                    Text(
                      Dates.time(sale.soldAt),
                      style: TextStyle(color: context.colors.muted),
                    ),
                  ),
                  DataCell(Text('${sale.itemCount}')),
                  DataCell(
                    PillTag(
                      text: sale.paymentType.label,
                      color: paymentColor(context, sale.paymentType),
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 130),
                      child: Text(
                        sale.customerName ?? '--',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: sale.customerName == null
                              ? context.colors.muted
                              : null,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      Money.plain(sale.totalCentavos),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration:
                            sale.voided ? TextDecoration.lineThrough : null,
                        color: sale.voided ? context.colors.muted : null,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      Money.plain(sale.profitCentavos),
                      style: TextStyle(
                        color: sale.voided
                            ? context.colors.muted
                            : context.colors.good,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SaleDetailSheet extends ConsumerWidget {
  const _SaleDetailSheet({required this.saleId});

  final int saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sale = ref.watch(saleDetailProvider(saleId));

    return AsyncBlock<Sale?>(
      value: sale,
      loadingHeight: 220,
      builder: (data) {
        if (data == null) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Text('Wala na ang bentang ito.'),
          );
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Benta #${data.id}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${Dates.readableDay(data.soldAt)} · '
                            '${Dates.time(data.soldAt)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PillTag(
                      text: data.paymentType.label,
                      color: paymentColor(context, data.paymentType),
                    ),
                  ],
                ),
                if (data.voided)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: PillTag(
                      text: 'Binawi ang bentang ito',
                      color: context.colors.danger,
                      icon: Icons.undo,
                    ),
                  ),
                if (data.customerName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 17,
                          color: context.colors.muted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          data.customerName!,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),

                for (final item in data.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${item.qty}×',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: context.colors.muted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${Money.format(item.unitPriceCentavos)} kada isa'
                                '${item.unitCostCentavos > 0 ? ' · puhunan ${Money.format(item.unitCostCentavos)}' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.colors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          Money.format(item.lineTotalCentavos),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),

                const Divider(height: 26),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'TOTAL',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      Money.format(data.totalCentavos),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tinatayang kita',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: context.colors.muted,
                        ),
                      ),
                    ),
                    Text(
                      Money.format(data.profitCentavos),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.colors.good,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),

                if (!data.voided) ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      foregroundColor: context.colors.danger,
                      side: BorderSide(
                        color: context.colors.danger.withValues(alpha: 0.5),
                      ),
                    ),
                    icon: const Icon(Icons.undo, size: 19),
                    label: const Text('Bawiin ang bentang ito'),
                    onPressed: () async {
                      final ok = await confirmDestructive(
                        context,
                        title: 'Bawiin ang benta #${data.id}?',
                        message:
                            'Ibabalik ang stock, at kung utang ito, aalisin '
                            'sa listahan ng customer. Mananatili ang tala '
                            'bilang binawi.',
                        confirmLabel: 'Bawiin',
                      );
                      if (!ok) return;

                      await ref
                          .read(salesRepositoryProvider)
                          .voidSale(data.id!);
                      ref.refreshData();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
