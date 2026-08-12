import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// One person's page in the credit book: what they owe now, and every charge
/// and payment behind that number. The ledger is append-only, so a mistake is
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
      title: 'Payment from ${customer.name}',
      message: 'Currently owes ${Money.format(customer.balanceCentavos)}',
      confirmLabel: 'Record payment',
      initialCentavos:
          customer.balanceCentavos > 0 ? customer.balanceCentavos : null,
    );
    if (amount == null) return;

    await ref.read(customerRepositoryProvider).recordPayment(
          customerId: customerId,
          amountCentavos: amount,
        );
    ref.refreshData();
    if (context.mounted) {
      showToast(context, 'Payment of ${Money.format(amount)} recorded');
    }
  }

  Future<void> _recordCharge(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) async {
    final amount = await showAmountDialog(
      context,
      title: 'Add to credit',
      message: 'For credit that did not come from a sale in the app — '
          'an older balance carried over from the notebook, for example.',
      confirmLabel: 'Add',
    );
    if (amount == null) return;

    await ref.read(customerRepositoryProvider).recordCharge(
          customerId: customerId,
          amountCentavos: amount,
          note: 'Added manually',
        );
    ref.refreshData();
    if (context.mounted) showToast(context, 'Added to credit');
  }

  Future<void> _deleteEntry(
    BuildContext context,
    WidgetRef ref,
    LedgerEntry entry,
  ) async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete this entry?',
      message: entry.isPayment
          ? '${Money.format(-entry.amountCentavos)} goes back onto the balance.'
          : '${Money.format(entry.amountCentavos)} comes off the balance.',
      confirmLabel: 'Delete',
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
      appBar: AppBar(title: Text(customer.valueOrNull?.name ?? 'Customer')),
      body: AsyncBlock<Customer?>(
        value: customer,
        loadingHeight: 300,
        builder: (person) {
          if (person == null) {
            return const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'This customer is gone',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              StatTile(
                large: true,
                label: 'Currently owes',
                value: Money.format(person.balanceCentavos),
                caption: person.balanceCentavos <= 0
                    ? 'Nothing owed. All paid up.'
                    : person.lastActivity == null
                        ? null
                        : 'Last activity: '
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
                      label: const Text('Payment'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _recordCharge(context, ref, person),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Add credit'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Text(
                'HISTORY',
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
                          'Nothing recorded yet.',
                          style: TextStyle(color: context.colors.muted),
                        ),
                      ),
                    );
                  }

                  // Walk the entries newest-first, showing the balance as it
                  // stood after each one -- the way a paper ledger reads.
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
                'Press and hold an entry to delete it.',
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
                    isPayment ? 'Payment' : (entry.note ?? 'Credit'),
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${Dates.relativeDay(entry.enteredAt)} · '
                    '${Dates.time(entry.enteredAt)}',
                    style:
                        TextStyle(fontSize: 12, color: context.colors.muted),
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
                  'balance ${Money.formatShort(balanceAfter)}',
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
