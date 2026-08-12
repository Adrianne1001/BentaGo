import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/seed_products.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Product profiling, kept deliberately shallow: a name and a price is a
/// complete product. Everything else sits under "More details", collapsed, so
/// adding an item mid-rush is two fields and a save.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.product, this.initialName});

  final Product? product;
  final String? initialName;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _description;
  late final TextEditingController _unitLabel;
  late final TextEditingController _barcode;

  String? _category;
  String? _emoji;
  bool _showOptional = false;
  bool _saving = false;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;

    _name =
        TextEditingController(text: product?.name ?? widget.initialName ?? '');
    _price = TextEditingController(
      text: product == null ? '' : Money.plain(product.priceCentavos),
    );
    _cost = TextEditingController(
      text: product != null && product.hasCost
          ? Money.plain(product.costCentavos)
          : '',
    );
    _description = TextEditingController(text: product?.description ?? '');
    _unitLabel = TextEditingController(text: product?.unitLabel ?? 'pc');
    _barcode = TextEditingController(text: product?.barcode ?? '');

    _category = product?.category;
    _emoji = product?.emoji;

    // An existing product that already carries optional detail should show it
    // rather than hide the values behind a collapsed section.
    _showOptional = product != null &&
        (product.hasCost ||
            (product.description?.isNotEmpty ?? false) ||
            (product.barcode?.isNotEmpty ?? false) ||
            product.category != null);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _description.dispose();
    _unitLabel.dispose();
    _barcode.dispose();
    super.dispose();
  }

  /// Prompts for a category name and selects it. Nothing is written until the
  /// product is saved -- a category exists only because a product carries it.
  Future<void> _addCustomCategory() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final existing = ref.read(productCategoriesProvider).valueOrNull ??
        const <String>[];

    final created = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New category'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Category name',
              hintText: 'e.g. Frozen, School supplies',
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return 'Enter a name.';
              if (text.length > 30) return 'Keep it under 30 characters.';
              final clash = existing.any(
                (c) => c.toLowerCase() == text.toLowerCase(),
              );
              if (clash) return 'That category already exists.';
              return null;
            },
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

    if (created != null && mounted) setState(() => _category = created);
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true || _saving) return;
    setState(() => _saving = true);

    final draft = Product(
      id: widget.product?.id,
      name: _name.text.trim(),
      priceCentavos: Money.parse(_price.text) ?? 0,
      costCentavos: Money.parse(_cost.text) ?? 0,
      description: _description.text,
      category: _category,
      emoji: _emoji,
      barcode: _barcode.text,
      unitLabel: _unitLabel.text.trim().isEmpty ? 'pc' : _unitLabel.text.trim(),
      createdAt: widget.product?.createdAt,
    );

    try {
      final repo = ref.read(productRepositoryProvider);
      if (_isEditing) {
        await repo.update(draft);
      } else {
        await repo.insert(draft);
      }
      ref.refreshData();

      if (!mounted) return;
      Navigator.pop(context);
      showToast(
        context,
        _isEditing ? '${draft.name} updated' : '${draft.name} added',
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, 'Not saved: $error', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = Money.parse(_price.text) ?? 0;
    final cost = Money.parse(_cost.text) ?? 0;
    final margin = price - cost;

    // Suggestions plus everything already in use, so a custom category shows up
    // as a chip for every product added after it.
    final inUse =
        ref.watch(productCategoriesProvider).valueOrNull ?? const <String>[];
    final categoryOptions = <String>{
      ...suggestedCategories,
      ...inUse,
      if (_category != null) _category!,
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit product' : 'New product'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            Text(
              'REQUIRED',
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w700,
                color: context.colors.muted,
              ),
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: _name,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Product name',
                hintText: 'e.g. Lucky Me Pancit Canton',
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) return 'Enter a name.';
                return null;
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                labelText: 'Selling price',
                prefixText: '₱ ',
                hintText: '0.00',
              ),
              validator: (value) {
                final parsed = Money.parse(value ?? '');
                if (parsed == null) return 'Enter a price.';
                if (parsed <= 0) return 'Must be more than zero.';
                return null;
              },
            ),

            const SizedBox(height: 20),
            InkWell(
              onTap: () => setState(() => _showOptional = !_showOptional),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Text(
                      'MORE DETAILS',
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.9,
                        fontWeight: FontWeight.w700,
                        color: context.colors.muted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'all optional',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: context.colors.muted,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _showOptional ? Icons.expand_less : Icons.expand_more,
                      color: context.colors.muted,
                    ),
                  ],
                ),
              ),
            ),

            if (_showOptional) ...[
              const SizedBox(height: 6),
              TextFormField(
                controller: _cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Cost per piece',
                  prefixText: '₱ ',
                  helperText: cost > 0 && price > 0
                      ? 'Profit: ${Money.format(margin)} '
                          '(${(margin / price * 100).round()}%)'
                      : 'Leave blank and the whole price counts as profit.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 18),

              Row(
                children: [
                  Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.colors.muted,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addCustomCategory,
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('New'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 34),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in categoryOptions)
                    ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (selected) => setState(
                        () => _category = selected ? category : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              Text(
                'Picture (emoji)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.colors.muted,
                ),
              ),
              const SizedBox(height: 8),
              _EmojiPicker(
                selected: _emoji,
                onSelected: (value) => setState(
                  () => _emoji = _emoji == value ? null : value,
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _description,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'e.g. top shelf, beside the coffee',
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _unitLabel,
                decoration: const InputDecoration(
                  labelText: 'Unit name',
                  helperText: 'Sold one at a time. e.g. pc, sachet, bottle.',
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _barcode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Barcode',
                  helperText: 'For searching. Not required.',
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(_isEditing ? 'Save changes' : 'Add product'),
          ),
        ),
      ),
    );
  }
}

class _EmojiPicker extends StatelessWidget {
  const _EmojiPicker({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final emoji in productEmoji)
          InkWell(
            onTap: () => onSelected(emoji),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected == emoji
                    ? context.scheme.primary.withValues(alpha: 0.14)
                    : null,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected == emoji
                      ? context.scheme.primary
                      : context.scheme.outlineVariant.withValues(alpha: 0.6),
                  width: selected == emoji ? 2 : 1,
                ),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
      ],
    );
  }
}
