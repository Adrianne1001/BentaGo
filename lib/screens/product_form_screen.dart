import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/seed_products.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Product profiling. The required fields run in the order a shopkeeper
/// actually knows them: what it cost, what to add on top, and only then what to
/// charge. The selling price is worked out rather than typed, so a product
/// cannot quietly end up priced below what the store paid for it.
///
/// The price stays editable -- the pencil beside it hands control back -- and
/// then the markup follows the price instead of driving it. Whichever field was
/// touched last is the one telling the truth.
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
  late final TextEditingController _markup;
  late final TextEditingController _description;
  late final TextEditingController _unitLabel;
  late final TextEditingController _barcode;

  String? _category;
  String? _emoji;
  bool _showOptional = false;
  bool _saving = false;

  /// False while the price is worked out from cost and markup. The pencil beside
  /// the price flips it, after which the markup is derived from the price.
  bool _priceByHand = false;

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
    // Derived, never stored: a product row carries a cost and a price, and the
    // markup is whatever sits between them.
    _markup = TextEditingController(
      text: product == null ? '' : _percentText(product.markupPercent),
    );
    _description = TextEditingController(text: product?.description ?? '');
    _unitLabel = TextEditingController(text: product?.unitLabel ?? 'pc');
    _barcode = TextEditingController(text: product?.barcode ?? '');

    _category = product?.category;
    _emoji = product?.emoji;

    // A product saved before cost was required has a price but nothing to derive
    // a markup from. Start it in by-hand mode so opening the form to fix the
    // category cannot silently rewrite the price it already sells at.
    _priceByHand = product != null && !product.hasCost;

    // An existing product that already carries optional detail should show it
    // rather than hide the values behind a collapsed section.
    _showOptional = product != null &&
        ((product.description?.isNotEmpty ?? false) ||
            (product.barcode?.isNotEmpty ?? false) ||
            product.category != null);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _markup.dispose();
    _description.dispose();
    _unitLabel.dispose();
    _barcode.dispose();
    super.dispose();
  }

  // --- the cost / markup / price triangle -----------------------------------
  //
  // Two of the three are always inputs and the third is worked out. Assigning to
  // a controller does not fire its `onChanged`, so writing the derived field
  // back here cannot loop.

  int? get _costValue => Money.parse(_cost.text);
  int? get _priceValue => Money.parse(_price.text);
  double? get _markupValue => _parsePercent(_markup.text);

  void _recalculatePrice() {
    final cost = _costValue;
    final markup = _markupValue;
    // Leave the price untouched while either input is still missing -- clearing
    // a half-typed cost should not blank a price the user can see.
    if (cost == null || cost <= 0 || markup == null) return;
    _price.text = Money.plain(Product.priceFromMarkup(cost, markup));
  }

  void _recalculateMarkup() {
    final cost = _costValue;
    final price = _priceValue;
    if (cost == null || cost <= 0 || price == null) return;
    _markup.text = _percentText(Product.markupFor(cost, price));
  }

  void _onCostChanged() => setState(() {
        if (_priceByHand) {
          _recalculateMarkup();
        } else {
          _recalculatePrice();
        }
      });

  /// Typing a markup means the markup is in charge again, even if the price had
  /// been set by hand a moment ago.
  void _onMarkupChanged() => setState(() {
        _priceByHand = false;
        _recalculatePrice();
      });

  void _onPriceChanged() => setState(_recalculateMarkup);

  void _togglePriceByHand() => setState(() {
        _priceByHand = !_priceByHand;
        if (!_priceByHand) _recalculatePrice();
      });

  /// States both numbers rather than picking one. The form asks for a markup
  /// (profit over cost) while the Reports screen talks in margin (profit over
  /// price), and showing them together is what stops the two being read as the
  /// same figure.
  String _priceHelper(int profit, double? marginPercent) {
    final cost = _costValue;
    if (cost == null || cost <= 0 || _priceValue == null) {
      return _priceByHand
          ? 'Typed by hand.'
          : 'Filled in once there is a cost and a markup.';
    }
    if (profit < 0) {
      return 'Below cost — losing ${Money.format(-profit)} per piece.';
    }
    final source = _priceByHand ? 'By hand' : 'From the markup';
    final margin =
        marginPercent == null ? '' : ', ${_percentText(marginPercent)}% margin';
    return '$source · ${Money.format(profit)} profit per piece$margin.';
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
    final price = _priceValue ?? 0;
    final cost = _costValue ?? 0;
    final profit = price - cost;
    final marginPercent = price > 0 ? profit / price * 100 : null;

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
              controller: _cost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              onChanged: (_) => _onCostChanged(),
              decoration: const InputDecoration(
                labelText: 'Cost per piece',
                prefixText: '₱ ',
                hintText: '0.00',
                helperText: 'What the store paid for one.',
              ),
              validator: (value) {
                final parsed = Money.parse(value ?? '');
                if (parsed == null) return 'Enter what one piece costs.';
                if (parsed <= 0) return 'Must be more than zero.';
                return null;
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _markup,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              onChanged: (_) => _onMarkupChanged(),
              decoration: InputDecoration(
                labelText: 'Markup',
                suffixText: '%',
                hintText: '20',
                helperText: cost > 0 && _markupValue != null
                    ? 'Adds ${Money.format(profit)} on top of '
                        '${Money.format(cost)}.'
                    : 'How much to add on top of the cost.',
                helperMaxLines: 2,
              ),
              validator: (value) {
                if (_parsePercent(value ?? '') == null) {
                  return 'Enter a markup, e.g. 20.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _price,
              readOnly: !_priceByHand,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _onPriceChanged(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                labelText: 'Selling price',
                prefixText: '₱ ',
                hintText: '0.00',
                filled: !_priceByHand,
                helperText: _priceHelper(profit, marginPercent),
                helperMaxLines: 2,
                helperStyle: profit < 0
                    ? TextStyle(
                        color: context.colors.danger,
                        fontWeight: FontWeight.w600,
                      )
                    : null,
                suffixIcon: IconButton(
                  icon: Icon(
                    _priceByHand ? Icons.calculate_outlined : Icons.edit_outlined,
                    size: 20,
                  ),
                  tooltip: _priceByHand
                      ? 'Go back to the markup price'
                      : 'Set the price by hand',
                  onPressed: _togglePriceByHand,
                ),
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

/// Percentages are entered loosely -- `20`, `20%`, `20.5` -- and shown without a
/// trailing `.0`, so a round markup reads as "20" and not "20.0".
double? _parsePercent(String input) {
  final cleaned = input.replaceAll(RegExp(r'[^0-9.\-]'), '').trim();
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

String _percentText(double? value) {
  if (value == null) return '';
  final rounded = (value * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
  return rounded.toStringAsFixed(1);
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
