import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// One person's page in the listahan: what they owe now, and every charge and
/// payment behind that number. The ledger is append-only, so a mistake is
/// corrected by a reversing entry rather than by editing history.
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final int customerId;

  Future<void> _recordPayment(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) async {
    final amount = await showAmountDialog(
      context,
      title: 'Bayad ni ${customer.name}',
      message: 'Utang ngayon: ${Money.format(customer.balanceCentavos)}',
      confirmLabel: 'Itala ang bayad',
      initialCentavos: customer.balanceCentavos > 0
          ? customer.balanceCentavos
          : null,
    );
    if (amount == null) return;

    await ref.read(customerRepositoryProvider).recordPayment(
          customerId: customerId,
          amountCentavos: amount,
        );
    ref.refreshData();
    if (context.mounted) {
      showToast(context, 'Naitala ang bayad na ${Money.format(amount)}');
    }
  }

  Future<void> _recordCharge(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) async {
    final amount = await showAmountDialog(
      context,
      title: 'Dagdag na utang',
      message: 'Para sa utang na hindi galing sa benta sa app -- '
          'halimbawa, lumang balanse mula sa notebook.',
      confirmLabel: 'Idagdag',
    );
    if (amount == null) return;

    await ref.read(customerRepositoryProvider).recordCharge(
          customerId: customerId,
          amountCentavos: amount,
          note: 'Manu-manong dagdag',
        );
    ref.refreshData();
    if (context.mounted) showToast(context, 'Naidagdag sa utang');
  }

  Future<void> _deleteEntry(
    BuildContext context,
    WidgetRef ref,
    LedgerEntry entry,
  ) async {
    final ok = await confirmDestructive(
      context,
      title: 'Burahin ang talang ito?',
      message: entry.isPayment
          ? 'Babalik ang ${Money.format(-entry.amountCentavos)} sa utang.'
          : 'Mababawas ang ${Money.format(entry.amountCentavos)} sa utang.',
      confirmLabel: 'Burahin',
    );
    if (!ok) return;

    await ref.read(customerRepositoryProvider).deleteEntry(entry.id!);
    ref.refreshData();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerProvider(customerId));
    final ledger = ref.watch(customerLedgerProvider(customerId));

    return Scaffold(
      appBar: AppBar(
        title: Text(customer.valueOrNull?.name ?? 'Customer'),
      ),
      body: AsyncBlock<Customer?>(
        value: customer,
        loadingHeight: 300,
        builder: (person) {
          if (person == null) {
            return const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Wala na ang customer',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              StatTile(
                large: true,
                label: 'Utang ngayon',
                value: Money.format(person.balanceCentavos),
                caption: person.balanceCentavos <= 0
                    ? 'Wala nang utang. Bayad na lahat.'
                    : person.lastActivity == null
                        ? null
                        : 'Huling galaw: '
                            '${Dates.relativeDay(person.lastActivity!)}',
                tone: person.owes ? StatTone.warn : StatTone.good,
                icon: Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: person.balanceCentavos <= 0
                          ? null
                          : () => _recordPayment(context, ref, person),
                      icon: const Icon(Icons.payments_outlined, size: 20),
                      label: const Text('Bayad'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _recordCharge(context, ref, person),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Dagdag utang'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Text(
                'KASAYSAYAN',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                  color: context.colors.muted,
                ),
              ),
              const SizedBox(height: 4),

              AsyncBlock<List<LedgerEntry>>(
                value: ledger,
                loadingHeight: 160,
                builder: (entries) {
                  if (entries.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          'Wala pang naitala.',
                          style: TextStyle(color: context.colors.muted),
                        ),
                      ),
                    );
                  }

                  // Walk the entries newest-first, showing the balance as it
                  // stood after each one -- the same way a paper ledger reads.
                  var running = person.balanceCentavos;
                  final rows = <Widget>[];

                  for (final entry in entries) {
                    rows.add(
                      _LedgerRow(
                        entry: entry,
                        balanceAfter: running,
                        onLongPress: () => _deleteEntry(context, ref, entry),
                      ),
                    );
                    running -= entry.amountCentavos;
                  }

                  return Column(children: rows);
                },
              ),

              const SizedBox(height: 16),
              Text(
                'Pindutin nang matagal ang isang tala para burahin ito.',
                style: TextStyle(fontSize: 12, color: context.colors.muted),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.entry,
    required this.balanceAfter,
    required this.onLongPress,
  });

  final LedgerEntry entry;
  final int balanceAfter;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isPayment = entry.isPayment;
    final color = isPayment ? context.colors.good : context.colors.warn;

    return InkWell(
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isPayment ? Icons.south_west : Icons.north_east,
                size: 17,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPayment ? 'Bayad' : (entry.note ?? 'Utang'),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${Dates.relativeDay(entry.enteredAt)} · '
                    '${Dates.time(entry.enteredAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isPayment ? '−' : '+'}'
                  '${Money.format(entry.amountCentavos.abs())}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'balanse ${Money.formatShort(balanceAfter)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.colors.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
