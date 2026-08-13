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
        title: const Text('Sales records'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'voided':
                  _update((q) => q.copyWith(includeVoided: !q.includeVoided));
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
                child: const Text('Include cancelled'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'recent',
                child: Text('Newest first'),
              ),
              const PopupMenuItem<String>(
                value: 'oldest',
                child: Text('Oldest first'),
              ),
              const PopupMenuItem<String>(
                value: 'amount',
                child: Text('Largest first'),
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
              hint: 'Search product, name, or number',
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
                    title: 'No matching sales',
                    message: 'Change the filter or the period above.',
                  );
                }
                return Column(
                  children: [
                    _TableFooter(rows: rows),
                    const Divider(height: 1),
                    Expanded(child: _SalesTable(rows: rows, onTap: _openSale)),
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
              label: Text(period == null ? 'All time' : period.label),
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
            for (final kind in browsablePeriodKinds)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: ChoiceChip(
                  label: Text(kind.label),
                  selected: period.kind == kind,
                  onSelected: (_) => onUpdate(
                    (q) => q.copyWith(period: period.withKind(kind)),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              child: IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                tooltip: 'Previous',
                onPressed: () =>
                    onUpdate((q) => q.copyWith(period: period.shift(-1))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              child: IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                tooltip: 'Next',
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
          Expanded(child: _MiniStat(label: 'Count', value: '${live.length}')),
          Expanded(
            child: _MiniStat(label: 'Total', value: Money.formatShort(total)),
          ),
          Expanded(
            child: _MiniStat(
              label: 'Profit',
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
            DataColumn(label: Text('DATE')),
            DataColumn(label: Text('TIME')),
            DataColumn(label: Text('QTY'), numeric: true),
            DataColumn(label: Text('PAID')),
            DataColumn(label: Text('CUSTOMER')),
            DataColumn(label: Text('TOTAL'), numeric: true),
            DataColumn(label: Text('PROFIT'), numeric: true),
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

/// Opens the quantity editor for one line and applies whatever comes back.
///
/// Taking the last remaining line off a sale cancels the sale instead of
/// leaving a record worth nothing, so that case asks a different question.
Future<void> _editLine(
  BuildContext context,
  WidgetRef ref,
  Sale sale,
  SaleItem item,
) async {
  final result = await showDialog<int>(
    context: context,
    builder: (_) => SaleLineEditorDialog(sale: sale, item: item),
  );
  if (result == null || result == item.qty || !context.mounted) return;

  if (result == 0) {
    final ok = await confirmDestructive(
      context,
      title: sale.items.length == 1
          ? 'Cancel sale #${sale.id}?'
          : 'Remove ${item.productName} from sale #${sale.id}?',
      message: sale.items.length == 1
          ? 'It is the only item on this sale, so the whole sale is cancelled. '
              'The record stays, marked cancelled.'
          : 'The sale total drops by ${Money.format(item.lineTotalCentavos)}, '
              'to ${Money.format(sale.totalCentavos - item.lineTotalCentavos)}.'
              '${sale.paymentType == PaymentType.credit ? ' The customer\'s credit is reduced to match.' : ''}',
      confirmLabel: sale.items.length == 1 ? 'Cancel sale' : 'Remove item',
    );
    if (!ok) return;
  }

  try {
    await ref.read(salesRepositoryProvider).setSaleItemQty(
          saleId: sale.id!,
          itemId: item.id!,
          qty: result,
        );
    ref.refreshData();
    if (!context.mounted) return;
    // The sheet is showing a sale that no longer exists as a live record.
    if (result == 0 && sale.items.length == 1) Navigator.pop(context);
    showToast(context, 'Sale #${sale.id} updated');
  } on Object catch (error) {
    if (context.mounted) {
      showToast(context, 'Not saved: $error', isError: true);
    }
  }
}

class _SaleLineRow extends StatelessWidget {
  const _SaleLineRow({
    required this.item,
    required this.editable,
    required this.onEdit,
  });

  final SaleItem item;
  final bool editable;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    // Tall enough to hit reliably with a thumb while a customer waits, which
    // the old 6px padding was not.
    final row = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: editable ? 8 : 0),
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
                  '${Money.format(item.unitPriceCentavos)} each'
                  '${item.unitCostCentavos > 0 ? ' · cost ${Money.format(item.unitCostCentavos)}' : ''}',
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
          // Reads as a button rather than as decoration -- the muted 16px
          // pencil this replaces was easy to miss entirely.
          if (editable)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.edit_outlined,
                  size: 17,
                  color: context.scheme.primary,
                ),
              ),
            ),
        ],
      ),
    );

    if (!editable) return row;
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(10),
      child: row,
    );
  }
}

/// One row of the dialog's arithmetic: a label, the peso figure, and -- once the
/// stepper has moved -- what the figure used to be.
class _EditAmountRow extends StatelessWidget {
  const _EditAmountRow({
    required this.label,
    required this.centavos,
    this.wasCentavos,
    this.emphasise = false,
  });

  final String label;
  final int centavos;
  final int? wasCentavos;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasise ? 14 : 13,
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w600,
              color: emphasise ? null : context.colors.muted,
            ),
          ),
        ),
        if (wasCentavos != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              Money.format(wasCentavos!),
              style: TextStyle(
                fontSize: 12.5,
                color: context.colors.muted,
                decoration: TextDecoration.lineThrough,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        Text(
          Money.format(centavos),
          style: TextStyle(
            fontSize: emphasise ? 19 : 15,
            fontWeight: emphasise ? FontWeight.w800 : FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Quantity only. The unit price is shown but never editable -- it is what the
/// item actually sold for, and a sale that can be re-priced after the fact is a
/// sale whose history cannot be trusted.
///
/// Removal lives in the body rather than among the actions, for two reasons: it
/// is the one irreversible thing in here and should not sit shoulder to shoulder
/// with `Save`, and a flex widget cannot be used to push it away from `Save`
/// either -- `actions` are laid out in an `OverflowBar`, which is not a `Flex`,
/// so a `Spacer` there throws while the dialog is building. That is exactly the
/// bug that made this editor unreachable.
///
/// Public so it can be pumped directly in a widget test: the failure it guards
/// against is a layout-time throw, which no amount of repository testing sees.
/// Pops the new quantity, `0` to remove the line, or null when dismissed.
class SaleLineEditorDialog extends StatefulWidget {
  const SaleLineEditorDialog({
    super.key,
    required this.sale,
    required this.item,
  });

  final Sale sale;
  final SaleItem item;

  @override
  State<SaleLineEditorDialog> createState() => _SaleLineEditorDialogState();
}

class _SaleLineEditorDialogState extends State<SaleLineEditorDialog> {
  late int _qty = widget.item.qty;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final sale = widget.sale;
    final isOnlyLine = sale.items.length == 1;
    final changed = _qty != item.qty;

    final lineTotal = item.unitPriceCentavos * _qty;
    // What the whole sale becomes, computed the same way the repository will
    // re-total it: this line at its recorded unit price, the others untouched.
    final saleTotal = sale.totalCentavos - item.lineTotalCentavos + lineTotal;

    return AlertDialog(
      title: Text(item.productName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${Money.format(item.unitPriceCentavos)} each · sold at this price',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: context.colors.muted),
          ),
          const SizedBox(height: 18),
          Center(
            child: QtyStepper(
              qty: _qty,
              min: 1,
              onChanged: (value) => setState(() => _qty = value),
            ),
          ),
          const SizedBox(height: 20),
          _EditAmountRow(label: 'Line total', centavos: lineTotal),
          const SizedBox(height: 8),
          // The number that actually matters, and the reason this dialog shows
          // it: the old version only ever showed the line, so the effect on the
          // sale was invisible until after it had been saved.
          _EditAmountRow(
            label: 'Sale total',
            centavos: saleTotal,
            wasCentavos: changed ? sale.totalCentavos : null,
            emphasise: true,
          ),
          if (sale.paymentType == PaymentType.credit) ...[
            const SizedBox(height: 10),
            Text(
              'The customer\'s credit moves with the total.',
              style: TextStyle(fontSize: 12, color: context.colors.muted),
            ),
          ],
          const Divider(height: 30),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              foregroundColor: context.colors.danger,
              side: BorderSide(
                color: context.colors.danger.withValues(alpha: 0.5),
              ),
            ),
            icon: Icon(
              isOnlyLine ? Icons.undo : Icons.delete_outline,
              size: 19,
            ),
            label: Text(isOnlyLine ? 'Cancel this sale' : 'Remove this item'),
            onPressed: () => Navigator.pop(context, 0),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: changed ? () => Navigator.pop(context, _qty) : null,
          child: const Text('Save'),
        ),
      ],
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
            child: Text('This sale no longer exists.'),
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
                            'Sale #${data.id}',
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
                      text: 'This sale was cancelled',
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

                if (!data.voided)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Tap an item to change its quantity or remove it.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.muted,
                      ),
                    ),
                  ),

                for (final item in data.items)
                  _SaleLineRow(
                    item: item,
                    editable: !data.voided,
                    onEdit: () => _editLine(context, ref, data, item),
                  ),

                // The correction stamp _retotal writes. Without this the audit
                // trail existed only in the database, so a total that had been
                // corrected looked simply wrong.
                if (data.note != null && data.note!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.history,
                          size: 15,
                          color: context.colors.muted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            data.note!,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.muted,
                            ),
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
                        'Estimated profit',
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
                    label: const Text('Cancel this sale'),
                    onPressed: () async {
                      final ok = await confirmDestructive(
                        context,
                        title: 'Cancel sale #${data.id}?',
                        message: data.paymentType == PaymentType.credit
                            ? 'It will be taken off the customer\'s credit. '
                                'The record stays, marked cancelled.'
                            : 'The record stays, marked cancelled, and stops '
                                'counting towards any total.',
                        confirmLabel: 'Cancel sale',
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
