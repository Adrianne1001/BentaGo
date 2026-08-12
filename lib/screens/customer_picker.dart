import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Picks who is taking the credit. Adding a customer is inline rather than a
/// separate screen -- a new name usually turns up mid-sale, with someone
/// waiting at the window.
Future<Customer?> showCustomerPicker(BuildContext context) async {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _CustomerPickerSheet(),
  );
}

class _CustomerPickerSheet extends ConsumerStatefulWidget {
  const _CustomerPickerSheet();

  @override
  ConsumerState<_CustomerPickerSheet> createState() =>
      _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _creating = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createAndPick(String name) async {
    if (name.trim().isEmpty || _creating) return;
    setState(() => _creating = true);

    try {
      final repo = ref.read(customerRepositoryProvider);
      final id = await repo.insert(Customer(name: name.trim()));
      ref.refreshData();
      if (!mounted) return;
      Navigator.pop(context, Customer(id: id, name: name.trim()));
    } on Object catch (error) {
      if (mounted) {
        setState(() => _creating = false);
        showToast(context, 'Not added: $error', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customerListProvider);
    final query = _query.trim().toLowerCase();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Who is taking this on credit?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search, or type a new name',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: AsyncBlock<List<Customer>>(
                value: customers,
                loadingHeight: 200,
                builder: (all) {
                  final matches = query.isEmpty
                      ? all
                      : all
                          .where((c) => c.name.toLowerCase().contains(query))
                          .toList();

                  final exactExists =
                      all.any((c) => c.name.toLowerCase() == query);
                  final showCreate = query.isNotEmpty && !exactExists;

                  if (matches.isEmpty && !showCreate) {
                    return const EmptyState(
                      icon: Icons.people_outline,
                      title: 'No customers yet',
                      message: 'Type a name above to add someone new.',
                    );
                  }

                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (showCreate)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: context.scheme.primary
                                .withValues(alpha: 0.14),
                            child: _creating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : Icon(
                                    Icons.person_add_alt,
                                    color: context.scheme.primary,
                                  ),
                          ),
                          title: Text('Add "${_query.trim()}"'),
                          subtitle: const Text('New customer'),
                          onTap: () => _createAndPick(_query),
                        ),
                      for (final customer in matches)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: customer.owes
                                ? context.colors.warn.withValues(alpha: 0.16)
                                : context.scheme.outlineVariant
                                    .withValues(alpha: 0.4),
                            child: Text(
                              customer.initial,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: customer.owes
                                    ? context.colors.warn
                                    : context.colors.muted,
                              ),
                            ),
                          ),
                          title: Text(
                            customer.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: customer.owes
                              ? Text(
                                  'Owes '
                                  '${Money.format(customer.balanceCentavos)}',
                                  style: TextStyle(color: context.colors.warn),
                                )
                              : const Text('Nothing owed'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, customer),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
