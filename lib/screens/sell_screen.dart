import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/report_repository.dart';
import '../state/cart_controller.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'customer_picker.dart';
import 'product_form_screen.dart';

/// The screen the app opens on. Everything here is optimised for the five
/// seconds a customer spends at the window: large tiles, no confirmation
/// dialogs, and an undo instead of an "are you sure".
class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  bool _basketExpanded = false;
  bool _saving = false;

  Future<void> _checkout() async {
    final cart = ref.read(cartProvider);
    if (!cart.canCheckout || _saving) return;

    setState(() => _saving = true);
    try {
      final saleId = await ref.read(salesRepositoryProvider).recordSale(
            lines: cart.lines,
            paymentType: cart.paymentType,
            customerId: cart.customerId,
            note: cart.note,
          );

      final total = cart.totalCentavos;
      final wasUtang = cart.paymentType == PaymentType.utang;
      final customerName = cart.customerName;

      ref.read(cartProvider.notifier).clear();
      ref.refreshData();
      setState(() => _basketExpanded = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(
              wasUtang
                  ? 'Naitala: ${Money.format(total)} utang ni $customerName'
                  : 'Naitala: ${Money.format(total)}',
            ),
            action: SnackBarAction(
              label: 'Bawiin',
              onPressed: () async {
                await ref.read(salesRepositoryProvider).voidSale(saleId);
                ref.refreshData();
              },
            ),
          ),
        );
    } on Object catch (error) {
      if (mounted) showToast(context, 'Hindi naitala: $error', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickCustomer() async {
    final picked = await showCustomerPicker(context, ref);
    if (picked == null) return;
    ref.read(cartProvider.notifier).setCustomer(picked.id, picked.name);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final products = ref.watch(productListProvider);
    final search = ref.watch(productSearchProvider);
    final categories = ref.watch(productCategoriesProvider);
    final selectedCategory = ref.watch(productCategoryFilterProvider);
    final today = ref.watch(todaySummaryProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TodayStrip(summary: today),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: AppSearchField(
                hint: 'Hanapin ang paninda...',
                value: search,
                onChanged: (value) =>
                    ref.read(productSearchProvider.notifier).state = value,
              ),
            ),
            _CategoryStrip(
              categories: categories,
              selected: selectedCategory,
              onSelect: (value) => ref
                  .read(productCategoryFilterProvider.notifier)
                  .state = value,
            ),
            Expanded(
              child: AsyncBlock<List<Product>>(
                value: products,
                loadingHeight: 300,
                builder: (items) {
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: search.isEmpty
                          ? 'Wala pang paninda'
                          : 'Walang nahanap',
                      message: search.isEmpty
                          ? 'Magdagdag ng produkto para makapagbenta.'
                          : 'Subukan ang ibang salita, o magdagdag ng bago.',
                      action: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ProductFormScreen(initialName: search),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Magdagdag ng produkto'),
                      ),
                    );
                  }
                  return _ProductGrid(
                    products: items,
                    cart: cart,
                    onTap: (product) {
                      ref.read(cartProvider.notifier).add(product);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _BasketPanel(
              cart: cart,
              expanded: _basketExpanded,
              saving: _saving,
              onToggleExpanded: () =>
                  setState(() => _basketExpanded = !_basketExpanded),
              onQtyChanged: (productId, qty) =>
                  ref.read(cartProvider.notifier).setQty(productId, qty),
              onPaymentChanged: (type) {
                ref.read(cartProvider.notifier).setPaymentType(type);
                if (type == PaymentType.utang) _pickCustomer();
              },
              onPickCustomer: _pickCustomer,
              onClear: () {
                ref.read(cartProvider.notifier).clear();
                setState(() => _basketExpanded = false);
              },
              onCheckout: _checkout,
            ),
    );
  }
}

class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.summary});

  final AsyncValue<PeriodSummary> summary;

  @override
  Widget build(BuildContext context) {
    final value = summary.valueOrNull;
    final revenue = value?.revenueCentavos ?? 0;
    final count = value?.saleCount ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BENTA NGAYON',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: context.colors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Money.format(revenue),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: PillTag(
              text: count == 1 ? '1 benta' : '$count na benta',
              color: context.scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final AsyncValue<List<String>> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final items = categories.valueOrNull ?? const <String>[];
    if (items.isEmpty) return const SizedBox(height: 4);

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ChoiceChip(
              label: const Text('Lahat'),
              selected: selected == null,
              onSelected: (_) => onSelect(null),
            ),
          ),
          for (final category in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: ChoiceChip(
                label: Text(category),
                selected: selected == category,
                onSelected: (_) => onSelect(selected == category ? null : category),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
    required this.products,
    required this.cart,
    required this.onTap,
  });

  final List<Product> products;
  final CartState cart;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 132,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.86,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return _ProductTile(
          product: product,
          inCart: cart.qtyOf(product.id),
          onTap: () => onTap(product),
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.inCart,
    required this.onTap,
  });

  final Product product;
  final int inCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = inCart > 0;
    final outOfStock = product.isOutOfStock;

    return Material(
      color: selected
          ? context.scheme.primary.withValues(alpha: 0.10)
          : context.scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? context.scheme.primary
                  : context.scheme.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductAvatar(product: product, size: 42),
                  const Spacer(),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        Money.formatShort(product.priceCentavos),
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: context.scheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      if (product.trackStock)
                        Text(
                          outOfStock ? 'ubos' : '${product.stock}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: outOfStock
                                ? context.colors.warn
                                : product.isLowStock
                                    ? context.colors.warn
                                    : context.colors.muted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.scheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$inCart',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: context.scheme.onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BasketPanel extends StatelessWidget {
  const _BasketPanel({
    required this.cart,
    required this.expanded,
    required this.saving,
    required this.onToggleExpanded,
    required this.onQtyChanged,
    required this.onPaymentChanged,
    required this.onPickCustomer,
    required this.onClear,
    required this.onCheckout,
  });

  final CartState cart;
  final bool expanded;
  final bool saving;
  final VoidCallback onToggleExpanded;
  final void Function(int productId, int qty) onQtyChanged;
  final ValueChanged<PaymentType> onPaymentChanged;
  final VoidCallback onPickCustomer;
  final VoidCallback onClear;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final needsCustomer =
        cart.paymentType == PaymentType.utang && cart.customerId == null;

    return Material(
      color: context.scheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    Icon(
                      expanded ? Icons.expand_more : Icons.expand_less,
                      color: context.colors.muted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${cart.itemCount} piraso',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.colors.muted,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: onClear,
                      child: const Text('Linisin'),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: cart.lines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final line = cart.lines[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${Money.formatShort(line.product.priceCentavos)} '
                                  'kada ${line.product.unitLabel}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: context.colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          QtyStepper(
                            qty: line.qty,
                            compact: true,
                            onChanged: (qty) =>
                                onQtyChanged(line.product.id!, qty),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 72,
                            child: Text(
                              Money.format(line.lineTotalCentavos),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  for (final type in PaymentType.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _PaymentChoice(
                          type: type,
                          selected: cart.paymentType == type,
                          onTap: () => onPaymentChanged(type),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (cart.paymentType == PaymentType.utang)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                child: OutlinedButton.icon(
                  onPressed: onPickCustomer,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                    foregroundColor:
                        needsCustomer ? context.colors.warn : null,
                    side: BorderSide(
                      color: needsCustomer
                          ? context.colors.warn
                          : context.scheme.outlineVariant,
                    ),
                  ),
                  icon: Icon(
                    needsCustomer ? Icons.person_add_alt : Icons.person,
                    size: 19,
                  ),
                  label: Text(
                    cart.customerName ?? 'Piliin kung sino ang umutang',
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'TOTAL',
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                            color: context.colors.muted,
                          ),
                        ),
                        Text(
                          Money.format(cart.totalCentavos),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          cart.canCheckout && !saving ? onCheckout : null,
                      child: saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Tapos'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentChoice extends StatelessWidget {
  const _PaymentChoice({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final PaymentType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = paymentColor(context, type);

    return Material(
      color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? color
                  : context.scheme.outlineVariant.withValues(alpha: 0.7),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            type.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? color : context.colors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
