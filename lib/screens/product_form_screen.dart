import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/seed_products.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Product profiling, kept deliberately shallow: a name and a price is a
/// complete product. Everything else sits under "Iba pang detalye", collapsed,
/// so adding an item mid-rush is two fields and a save.
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
  late final TextEditingController _reorderLevel;
  late final TextEditingController _openingStock;
  late final TextEditingController _barcode;

  String? _category;
  String? _emoji;
  bool _trackStock = true;
  bool _showOptional = false;
  bool _saving = false;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;

    _name = TextEditingController(text: product?.name ?? widget.initialName ?? '');
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
    _reorderLevel = TextEditingController(
      text: product == null
          ? '5'
          : (product.reorderLevel == 0 ? '' : '${product.reorderLevel}'),
    );
    _openingStock = TextEditingController();
    _barcode = TextEditingController(text: product?.barcode ?? '');

    _category = product?.category;
    _emoji = product?.emoji;
    _trackStock = product?.trackStock ?? true;

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
    _reorderLevel.dispose();
    _openingStock.dispose();
    _barcode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true || _saving) return;
    setState(() => _saving = true);

    final price = Money.parse(_price.text) ?? 0;
    final cost = Money.parse(_cost.text) ?? 0;

    final draft = Product(
      id: widget.product?.id,
      name: _name.text.trim(),
      priceCentavos: price,
      costCentavos: cost,
      description: _description.text,
      category: _category,
      emoji: _emoji,
      barcode: _barcode.text,
      unitLabel: _unitLabel.text.trim().isEmpty ? 'pc' : _unitLabel.text.trim(),
      stock: widget.product?.stock ?? 0,
      reorderLevel: int.tryParse(_reorderLevel.text.trim()) ?? 0,
      trackStock: _trackStock,
      createdAt: widget.product?.createdAt,
    );

    try {
      final repo = ref.read(productRepositoryProvider);
      if (_isEditing) {
        await repo.update(draft);
      } else {
        await repo.insert(
          draft,
          openingStock: int.tryParse(_openingStock.text.trim()) ?? 0,
        );
      }
      ref.refreshData();

      if (!mounted) return;
      Navigator.pop(context);
      showToast(
        context,
        _isEditing
            ? 'Na-update ang ${draft.name}'
            : 'Naidagdag ang ${draft.name}',
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, 'Hindi na-save: $error', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = Money.parse(_price.text) ?? 0;
    final cost = Money.parse(_cost.text) ?? 0;
    final margin = price - cost;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'I-edit ang paninda' : 'Bagong paninda'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            Text(
              'KAILANGAN',
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
                labelText: 'Pangalan ng paninda',
                hintText: 'Hal. Lucky Me Pancit Canton',
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Kailangan ang pangalan.';
                }
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
                labelText: 'Presyo ng benta',
                prefixText: '₱ ',
                hintText: '0.00',
              ),
              validator: (value) {
                final parsed = Money.parse(value ?? '');
                if (parsed == null) return 'Kailangan ang presyo.';
                if (parsed <= 0) return 'Dapat mas mataas sa zero.';
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
                      'IBA PANG DETALYE',
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.9,
                        fontWeight: FontWeight.w700,
                        color: context.colors.muted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'opsyonal',
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
                  labelText: 'Puhunan kada piraso',
                  prefixText: '₱ ',
                  helperText: cost > 0 && price > 0
                      ? 'Kita: ${Money.format(margin)} '
                          '(${(margin / price * 100).round()}%)'
                      : 'Kung blangko, ang buong presyo ay ituturing na kita.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Kategorya',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.colors.muted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in productCategories)
                    ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (selected) => setState(
                        () => _category = selected ? category : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                'Larawan (emoji)',
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
                  labelText: 'Paalala',
                  hintText: 'Hal. sa itaas na shelf, tabi ng kape',
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _unitLabel,
                decoration: const InputDecoration(
                  labelText: 'Tawag sa yunit',
                  helperText: 'Isahan lang ang benta. Hal. pc, sachet, bote.',
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _barcode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Barcode',
                  helperText: 'Para sa paghahanap. Hindi kailangan.',
                ),
              ),
              const SizedBox(height: 20),

              SwitchListTile(
                value: _trackStock,
                contentPadding: EdgeInsets.zero,
                title: const Text('Bilangin ang stock'),
                subtitle: const Text(
                  'Patayin para sa paninda na walang tiyak na bilang, '
                  'gaya ng yelo o tingi mula sa sako.',
                ),
                onChanged: (value) => setState(() => _trackStock = value),
              ),

              if (_trackStock) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _reorderLevel,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sabihan kapag ganito na lang ang natitira',
                    helperText: 'Iwanang blangko para hindi paalalahanan.',
                  ),
                ),
                if (!_isEditing) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _openingStock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Ilan ang meron ngayon?',
                      helperText: 'Maitatala ito bilang unang delivery.',
                    ),
                  ),
                ],
              ],
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
                : Text(_isEditing ? 'I-save ang pagbabago' : 'Idagdag'),
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
