import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'customer_detail_screen.dart';

/// The credit book -- the *listahan*. Sorted by who owes the most, because that
/// is the order it gets read in when deciding who to follow up with.
class CreditScreen extends ConsumerWidget {
  const CreditScreen({super.key});

  Future<void> _addCustomer(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New customer'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Aling Beth',
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Enter a name.' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (name == null) return;
    await ref.read(customerRepositoryProvider).insert(Customer(name: name));
    ref.refreshData();
    if (context.mounted) showToast(context, '$name added');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customerListProvider);
    final search = ref.watch(customerSearchProvider);
    final outstanding = ref.watch(totalOutstandingProvider);
    final debtors = ref.watch(debtorCountProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Credit')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: StatTile(
              large: true,
              label: 'Total owed to the store',
              value: Money.format(outstanding.valueOrNull ?? 0),
              caption: switch (debtors.valueOrNull ?? 0) {
                0 => 'Nobody owes anything right now.',
                1 => '1 person owes money',
                final count => '$count people owe money',
              },
              tone: (outstanding.valueOrNull ?? 0) > 0
                  ? StatTone.warn
                  : StatTone.good,
              icon: Icons.receipt_long,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AppSearchField(
              hint: 'Search by name...',
              value: search,
              onChanged: (value) =>
                  ref.read(customerSearchProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: AsyncBlock<List<Customer>>(
              value: customers,
              loadingHeight: 260,
              builder: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline,
                    title: search.isEmpty ? 'No customers yet' : 'No matches',
                    message: search.isEmpty
                        ? 'They get added automatically when you record a '
                            'credit sale, or add someone now.'
                        : 'Nothing matches "$search".',
                    action: FilledButton.icon(
                      onPressed: () => _addCustomer(context, ref),
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Add a customer'),
                    ),
                  );
                }

                final owing = items.where((c) => c.owes).toList();
                final clear = items.where((c) => !c.owes).toList();

                return ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    if (owing.isNotEmpty) ...[
                      _GroupHeader(
                        label: 'Owes money',
                        count: owing.length,
                        color: context.colors.warn,
                      ),
                      for (final customer in owing)
                        _CustomerRow(customer: customer),
                    ],
                    if (clear.isNotEmpty) ...[
                      _GroupHeader(
                        label: 'Paid up',
                        count: clear.length,
                        color: context.colors.good,
                      ),
                      for (final customer in clear)
                        _CustomerRow(customer: customer),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addCustomer(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Customer'),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: context.colors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final days = customer.daysSinceActivity;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: customer.owes
            ? context.colors.warn.withValues(alpha: 0.16)
            : context.scheme.outlineVariant.withValues(alpha: 0.35),
        child: Text(
          customer.initial,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: customer.owes ? context.colors.warn : context.colors.muted,
          ),
        ),
      ),
      title: Text(
        customer.name,
        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
      ),
      subtitle: customer.lastActivity == null
          ? Text(
              'Nothing recorded yet',
              style: TextStyle(fontSize: 12.5, color: context.colors.muted),
            )
          : Text(
              customer.owes && days >= 14
                  ? 'Last activity $days days ago'
                  : 'Last activity: ${Dates.relativeDay(customer.lastActivity!)}',
              style: TextStyle(
                fontSize: 12.5,
                color: customer.owes && days >= 14
                    ? context.colors.warn
                    : context.colors.muted,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            customer.owes ? Money.format(customer.balanceCentavos) : '--',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color:
                  customer.owes ? context.colors.warn : context.colors.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CustomerDetailScreen(customerId: customer.id!),
        ),
      ),
    );
  }
}
