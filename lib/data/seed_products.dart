/// A fresh install opens with a stocked price list instead of an empty screen.
/// These are the goods that turn over in almost every sari-sari store, priced
/// at rough 2026 street rates -- edit or delete any of them in Products.
///
/// Product names stay in Filipino because that is what is printed on the
/// packet and what a customer asks for. Only the categories are in English, to
/// match the rest of the interface.
class SeedProduct {
  const SeedProduct(
    this.name,
    this.priceCentavos,
    this.costCentavos,
    this.category,
    this.emoji,
  );

  final String name;
  final int priceCentavos;
  final int costCentavos;
  final String category;
  final String emoji;
}

const List<SeedProduct> seedProducts = [
  // Noodles and canned goods
  SeedProduct('Lucky Me Pancit Canton', 1700, 1400, 'Food', '🍜'),
  SeedProduct('Lucky Me Beef Noodles', 1300, 1050, 'Food', '🍜'),
  SeedProduct('Argentina Corned Beef', 3500, 3000, 'Food', '🥫'),
  SeedProduct('555 Sardinas', 2500, 2150, 'Food', '🐟'),
  SeedProduct('Ligo Sardines', 2300, 1950, 'Food', '🐟'),

  // Coffee, milk, sugar
  SeedProduct('Kopiko Blanca', 1000, 800, 'Coffee', '☕'),
  SeedProduct('Nescafe 3-in-1', 1200, 950, 'Coffee', '☕'),
  SeedProduct('Great Taste White', 1000, 800, 'Coffee', '☕'),
  SeedProduct('Bear Brand sachet', 1600, 1350, 'Milk', '🥛'),
  SeedProduct('Asukal (sachet)', 700, 550, 'Food', '🧂'),

  // Snacks
  SeedProduct('Piattos', 2000, 1700, 'Snacks', '🥔'),
  SeedProduct('Nova', 2000, 1700, 'Snacks', '🥔'),
  SeedProduct('Chippy', 1400, 1150, 'Snacks', '🌽'),
  SeedProduct('Skyflakes', 900, 700, 'Snacks', '🍘'),
  SeedProduct('Rebisco Crackers', 800, 620, 'Snacks', '🍘'),
  SeedProduct('Maxx Candy', 200, 150, 'Candy', '🍬'),
  SeedProduct('Storck Candy', 200, 150, 'Candy', '🍬'),

  // Drinks
  SeedProduct('Coke Mismo', 2500, 2150, 'Drinks', '🥤'),
  SeedProduct('Royal Mismo', 2500, 2150, 'Drinks', '🥤'),
  SeedProduct('Tubig (bottled)', 1500, 1100, 'Drinks', '💧'),
  SeedProduct('Zesto Juice', 1200, 950, 'Drinks', '🧃'),
  SeedProduct('Kopiko Lucky Day', 2000, 1700, 'Drinks', '🥤'),

  // Household and personal care
  SeedProduct('Palmolive sachet', 1000, 800, 'Toiletries', '🧴'),
  SeedProduct('Safeguard sachet', 1200, 950, 'Toiletries', '🧼'),
  SeedProduct('Tide sachet', 1200, 1000, 'Laundry', '🧺'),
  SeedProduct('Downy sachet', 1200, 1000, 'Laundry', '🧺'),
  SeedProduct('Colgate sachet', 1000, 800, 'Toiletries', '🪥'),
  SeedProduct('Kalamansi (piraso)', 300, 200, 'Fresh', '🍋'),
  SeedProduct('Itlog (piraso)', 1000, 850, 'Fresh', '🥚'),
  SeedProduct('Bawang (pack)', 1500, 1200, 'Fresh', '🧄'),
  SeedProduct('Sigarilyo (stick)', 1500, 1250, 'Other', '🚬'),
  SeedProduct('Yelo (bag)', 1000, 500, 'Other', '🧊'),
];

/// Starting suggestions in the product form. Categories are plain text on the
/// product row, so anything typed in the form joins this list from then on --
/// these are only the ones offered before any custom ones exist.
const List<String> suggestedCategories = [
  'Food',
  'Snacks',
  'Drinks',
  'Coffee',
  'Milk',
  'Candy',
  'Toiletries',
  'Laundry',
  'Fresh',
  'Other',
];

/// Quick-pick emoji for the product form. Purely optional -- a product with no
/// emoji falls back to the first letter of its name on a tinted tile.
const List<String> productEmoji = [
  '🍜', '🥫', '🐟', '☕', '🥛', '🍚', '🍞', '🥚',
  '🥔', '🌽', '🍘', '🍬', '🍫', '🍪', '🥤', '🧃',
  '💧', '🧊', '🧴', '🧼', '🪥', '🧺', '🧻', '🕯️',
  '🍋', '🧄', '🧅', '🥬', '🚬', '🔋', '📱', '🛒',
];
