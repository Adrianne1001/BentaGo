/// A fresh install opens with a stocked shelf instead of an empty screen.
/// These are the goods that turn over in almost every sari-sari store, priced
/// at rough 2026 street rates -- edit or delete any of them in Paninda.
///
/// The point is that she can sell something in the first minute of using the
/// app, rather than doing an hour of data entry before it does anything.
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
  SeedProduct('Lucky Me Pancit Canton', 1700, 1400, 'Pagkain', '🍜'),
  SeedProduct('Lucky Me Beef Noodles', 1300, 1050, 'Pagkain', '🍜'),
  SeedProduct('Argentina Corned Beef', 3500, 3000, 'Pagkain', '🥫'),
  SeedProduct('555 Sardinas', 2500, 2150, 'Pagkain', '🐟'),
  SeedProduct('Ligo Sardines', 2300, 1950, 'Pagkain', '🐟'),

  // Coffee, milk, sugar
  SeedProduct('Kopiko Blanca', 1000, 800, 'Kape', '☕'),
  SeedProduct('Nescafe 3-in-1', 1200, 950, 'Kape', '☕'),
  SeedProduct('Great Taste White', 1000, 800, 'Kape', '☕'),
  SeedProduct('Bear Brand sachet', 1600, 1350, 'Gatas', '🥛'),
  SeedProduct('Asukal (sachet)', 700, 550, 'Pagkain', '🧂'),

  // Snacks
  SeedProduct('Piattos', 2000, 1700, 'Meryenda', '🥔'),
  SeedProduct('Nova', 2000, 1700, 'Meryenda', '🥔'),
  SeedProduct('Chippy', 1400, 1150, 'Meryenda', '🌽'),
  SeedProduct('Skyflakes', 900, 700, 'Meryenda', '🍘'),
  SeedProduct('Rebisco Crackers', 800, 620, 'Meryenda', '🍘'),
  SeedProduct('Maxx Candy', 200, 150, 'Kendi', '🍬'),
  SeedProduct('Storck Candy', 200, 150, 'Kendi', '🍬'),

  // Drinks
  SeedProduct('Coke Mismo', 2500, 2150, 'Inumin', '🥤'),
  SeedProduct('Royal Mismo', 2500, 2150, 'Inumin', '🥤'),
  SeedProduct('Tubig (bottled)', 1500, 1100, 'Inumin', '💧'),
  SeedProduct('Zesto Juice', 1200, 950, 'Inumin', '🧃'),
  SeedProduct('Kopiko Lucky Day', 2000, 1700, 'Inumin', '🥤'),

  // Household and personal care
  SeedProduct('Palmolive sachet', 1000, 800, 'Sabon', '🧴'),
  SeedProduct('Safeguard sachet', 1200, 950, 'Sabon', '🧼'),
  SeedProduct('Tide sachet', 1200, 1000, 'Labada', '🧺'),
  SeedProduct('Downy sachet', 1200, 1000, 'Labada', '🧺'),
  SeedProduct('Colgate sachet', 1000, 800, 'Sabon', '🪥'),
  SeedProduct('Kalamansi (piraso)', 300, 200, 'Sariwa', '🍋'),
  SeedProduct('Itlog (piraso)', 1000, 850, 'Sariwa', '🥚'),
  SeedProduct('Bawang (pack)', 1500, 1200, 'Sariwa', '🧄'),
  SeedProduct('Sigarilyo (stick)', 1500, 1250, 'Iba pa', '🚬'),
  SeedProduct('Yelo (bag)', 1000, 500, 'Iba pa', '🧊'),
];

/// Offered as chips in the product form so categories stay consistent
/// instead of drifting into "Snacks", "snack", "Meryenda" for the same shelf.
const List<String> productCategories = [
  'Pagkain',
  'Meryenda',
  'Inumin',
  'Kape',
  'Gatas',
  'Kendi',
  'Sabon',
  'Labada',
  'Sariwa',
  'Iba pa',
];

/// Quick-pick emoji for the product form. Purely optional -- a product with no
/// emoji falls back to the first letter of its name on a tinted tile.
const List<String> productEmoji = [
  '🍜', '🥫', '🐟', '☕', '🥛', '🍚', '🍞', '🥚',
  '🥔', '🌽', '🍘', '🍬', '🍫', '🍪', '🥤', '🧃',
  '💧', '🧊', '🧴', '🧼', '🪥', '🧺', '🧻', '🕯️',
  '🍋', '🧄', '🧅', '🥬', '🚬', '🔋', '📱', '🛒',
];
