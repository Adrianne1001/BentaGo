import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import '../core/period.dart';
import 'app_database.dart';
import 'app_storage.dart';

enum ExportFormat { excel, pdf }

extension ExportFormatX on ExportFormat {
  String get label => switch (this) {
        ExportFormat.excel => 'Excel',
        ExportFormat.pdf => 'PDF',
      };

  String get extension => switch (this) {
        ExportFormat.excel => 'xlsx',
        ExportFormat.pdf => 'pdf',
      };

  String get description => switch (this) {
        ExportFormat.excel => 'Opens in Excel or Google Sheets. Figures are real '
            'numbers, so they can be re-totalled.',
        ExportFormat.pdf => 'Fixed layout, for printing or sending as-is.',
      };
}

/// One sold line. The report is a list of these rather than a list of sales,
/// because "how much Piattos moved in July" is the question being asked, and a
/// per-transaction row cannot answer it.
class ReportLine {
  const ReportLine({
    required this.saleId,
    required this.soldAt,
    required this.dayKey,
    required this.product,
    required this.qty,
    required this.unitPriceCentavos,
    required this.unitCostCentavos,
    required this.payment,
    this.customer,
  });

  final int saleId;
  final DateTime soldAt;
  final String dayKey;
  final String product;
  final int qty;
  final int unitPriceCentavos;
  final int unitCostCentavos;
  final String payment;
  final String? customer;

  /// Gross sales for the line: what the customer was charged.
  int get grossCentavos => unitPriceCentavos * qty;

  int get costCentavos => unitCostCentavos * qty;

  int get profitCentavos => grossCentavos - costCentavos;
}

/// A gathered report: the range it covers, its lines, and the totals that sit
/// above the table.
class ReportData {
  const ReportData({required this.period, required this.lines});

  final Period period;
  final List<ReportLine> lines;

  int get grossCentavos =>
      lines.fold<int>(0, (sum, l) => sum + l.grossCentavos);

  int get profitCentavos =>
      lines.fold<int>(0, (sum, l) => sum + l.profitCentavos);

  int get qty => lines.fold<int>(0, (sum, l) => sum + l.qty);

  /// Distinct transactions behind the lines, for context under the totals.
  int get saleCount => lines.map((l) => l.saleId).toSet().length;

  bool get isEmpty => lines.isEmpty;

  /// True when some line had no cost price on file, which makes the profit
  /// column optimistic. The report says so rather than presenting it as fact.
  bool get profitIsEstimate => lines.any((l) => l.unitCostCentavos <= 0);
}

/// Builds the sales report and writes it as .xlsx or .pdf.
///
/// Both writers are pure Dart, so this works identically on Windows and Android
/// with no platform channel involved.
class ExportService {
  ExportService(this._app, {Directory? rootOverride})
      : _rootOverride = rootOverride;

  final AppDatabase _app;
  final Directory? _rootOverride;

  Future<Directory> rootDirectory() =>
      appOwnedDirectory('Reports', override: _rootOverride);

  /// Every sold line in the range, oldest first.
  ///
  /// Cancelled sales are excluded by `s.voided = 0`. Lines taken off a sale are
  /// deleted outright when the correction is made, so there is nothing further
  /// to filter -- what is in `sale_items` is what was sold.
  Future<ReportData> gather(Period period) async {
    final rows = await _app.db.rawQuery('''
      SELECT s.id             AS sale_id,
             s.sold_at        AS sold_at,
             s.day_key        AS day_key,
             s.payment_type   AS payment_type,
             c.name           AS customer,
             i.product_name   AS product,
             i.qty            AS qty,
             i.unit_price_centavos AS unit_price,
             i.unit_cost_centavos  AS unit_cost
      FROM sale_items i
      JOIN sales s      ON s.id = i.sale_id
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.voided = 0 AND s.day_key BETWEEN ? AND ?
      ORDER BY s.sold_at ASC, i.id ASC
    ''', [period.startKey, period.endKey]);

    return ReportData(
      period: period,
      lines: rows.map((r) {
        final payment = r['payment_type'] as String?;
        return ReportLine(
          saleId: (r['sale_id'] as int?) ?? 0,
          soldAt: DateTime.fromMillisecondsSinceEpoch(
            (r['sold_at'] as int?) ?? 0,
          ),
          dayKey: r['day_key'] as String? ?? '',
          product: r['product'] as String? ?? '',
          qty: (r['qty'] as int?) ?? 0,
          unitPriceCentavos: (r['unit_price'] as int?) ?? 0,
          unitCostCentavos: (r['unit_cost'] as int?) ?? 0,
          // Reuses the model's mapping so legacy 'utang' rows read as Credit.
          payment: _paymentLabel(payment),
          customer: r['customer'] as String?,
        );
      }).toList(),
    );
  }

  String fileNameFor(Period period, ExportFormat format) =>
      'bentago-report-${period.fileLabel}.${format.extension}';

  /// Gathers and writes in one call, returning the file to share.
  Future<File> export(Period period, ExportFormat format) async {
    final data = await gather(period);
    return write(data, format);
  }

  Future<File> write(ReportData data, ExportFormat format) async {
    final dir = await rootDirectory();
    final file = File(
      p.join(dir.path, fileNameFor(data.period, format)),
    );
    final bytes = switch (format) {
      ExportFormat.excel => buildExcel(data),
      ExportFormat.pdf => await buildPdf(data),
    };
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  // --- column layout, shared by both writers --------------------------------

  static const List<String> _headers = [
    'Date',
    'Time',
    'Sale #',
    'Product',
    'Qty',
    'Unit price',
    'Unit cost',
    'Gross sales',
    'Profit',
    'Payment',
    'Customer',
  ];

  // --- Excel ----------------------------------------------------------------

  /// Money lands as numbers, not strings, so the sheet can be re-totalled,
  /// pivoted and filtered. That is the whole reason to prefer xlsx over the
  /// CSV the backup already writes.
  List<int> buildExcel(ReportData data) {
    final book = Excel.createExcel();
    const sheetName = 'Sales';
    final sheet = book[sheetName];
    book.setDefaultSheet(sheetName);
    // createExcel() seeds a 'Sheet1' that would otherwise ship empty.
    if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');

    final bold = CellStyle(bold: true);
    final title = CellStyle(bold: true, fontSize: 14);

    void row(List<CellValue?> cells) => sheet.appendRow(cells);

    row([TextCellValue('BentaGo — Sales report')]);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .cellStyle = title;

    row([TextCellValue('Period'), TextCellValue(data.period.label)]);
    row([
      TextCellValue('Covering'),
      TextCellValue(
        '${Dates.readableDay(data.period.start)} to '
        '${Dates.readableDay(data.period.end)}',
      ),
    ]);
    row([
      TextCellValue('Generated'),
      TextCellValue(Dates.readableDay(DateTime.now())),
    ]);
    row([]);

    // Totals sit above the table, so the two numbers that matter are read
    // before any scrolling happens.
    row([
      TextCellValue('Total gross sales'),
      DoubleCellValue(data.grossCentavos / 100),
    ]);
    row([
      TextCellValue('Total profit'),
      DoubleCellValue(data.profitCentavos / 100),
    ]);
    row([TextCellValue('Items sold'), IntCellValue(data.qty)]);
    row([TextCellValue('Transactions'), IntCellValue(data.saleCount)]);
    for (var i = 5; i <= 8; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i))
          .cellStyle = bold;
    }
    if (data.profitIsEstimate) {
      row([
        TextCellValue('Note'),
        TextCellValue(
          'Some items have no cost price on file, so profit is an estimate.',
        ),
      ]);
    }
    row([]);

    final headerRowIndex = sheet.maxRows;
    row([for (final h in _headers) TextCellValue(h)]);
    for (var i = 0; i < _headers.length; i++) {
      sheet
          .cell(
            CellIndex.indexByColumnRow(
              columnIndex: i,
              rowIndex: headerRowIndex,
            ),
          )
          .cellStyle = bold;
    }

    for (final line in data.lines) {
      row([
        DateCellValue.fromDateTime(line.soldAt),
        TextCellValue(Dates.time(line.soldAt)),
        IntCellValue(line.saleId),
        TextCellValue(line.product),
        IntCellValue(line.qty),
        DoubleCellValue(line.unitPriceCentavos / 100),
        DoubleCellValue(line.unitCostCentavos / 100),
        DoubleCellValue(line.grossCentavos / 100),
        DoubleCellValue(line.profitCentavos / 100),
        TextCellValue(line.payment),
        TextCellValue(line.customer ?? ''),
      ]);
    }

    sheet.setColumnWidth(0, 12);
    sheet.setColumnWidth(1, 10);
    sheet.setColumnWidth(2, 8);
    sheet.setColumnWidth(3, 30);
    for (var i = 4; i <= 8; i++) {
      sheet.setColumnWidth(i, 13);
    }
    sheet.setColumnWidth(9, 10);
    sheet.setColumnWidth(10, 18);

    final bytes = book.save();
    if (bytes == null) {
      throw StateError('Could not encode the Excel file.');
    }
    return bytes;
  }

  // --- PDF ------------------------------------------------------------------

  /// Landscape, because eleven columns do not fit across A4 portrait at a size
  /// anyone would read.
  ///
  /// Figures carry no peso sign: the writer's built-in fonts are the 14 standard
  /// PDF ones, which are WinAnsi-encoded and have no glyph for U+20B1. Rather
  /// than embed a font for one character, the money columns are plain numbers
  /// and the heading says PHP.
  Future<List<int>> buildPdf(ReportData data) async {
    final doc = pw.Document(
      title: pdfSafe('BentaGo sales report - ${data.period.label}'),
    );

    const muted = PdfColors.grey700;
    final periodLabel = pdfSafe(data.period.label);
    final coverage = pdfSafe(
      '${Dates.readableDay(data.period.start)} to '
      '${Dates.readableDay(data.period.end)}',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 28),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox.shrink()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  'BentaGo - $periodLabel',
                  style: const pw.TextStyle(fontSize: 9, color: muted),
                ),
              ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: muted),
          ),
        ),
        build: (context) => [
          pw.Text(
            'BentaGo - Sales report',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '$periodLabel  ($coverage)',
            style: const pw.TextStyle(fontSize: 11, color: muted),
          ),
          pw.SizedBox(height: 12),
          _pdfTotals(data),
          if (data.profitIsEstimate) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Some items have no cost price on file, so profit is an estimate.',
              style: pw.TextStyle(
                fontSize: 9,
                color: muted,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ],
          pw.SizedBox(height: 14),
          if (data.isEmpty)
            pw.Text(
              'No sales in this period.',
              style: const pw.TextStyle(fontSize: 11, color: muted),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: _headers,
              headerStyle: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              cellHeight: 16,
              headerAlignment: pw.Alignment.centerLeft,
              cellAlignments: const {
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
                7: pw.Alignment.centerRight,
                8: pw.Alignment.centerRight,
              },
              columnWidths: const {
                0: pw.FlexColumnWidth(1.5),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(0.8),
                3: pw.FlexColumnWidth(4),
                4: pw.FlexColumnWidth(0.8),
                5: pw.FlexColumnWidth(1.3),
                6: pw.FlexColumnWidth(1.3),
                7: pw.FlexColumnWidth(1.5),
                8: pw.FlexColumnWidth(1.3),
                9: pw.FlexColumnWidth(1.2),
                10: pw.FlexColumnWidth(2),
              },
              data: [
                for (final line in data.lines)
                  [
                    line.dayKey,
                    Dates.time(line.soldAt),
                    '${line.saleId}',
                    // Typed by the user, so it can hold anything.
                    pdfSafe(line.product),
                    '${line.qty}',
                    Money.plain(line.unitPriceCentavos),
                    Money.plain(line.unitCostCentavos),
                    Money.plain(line.grossCentavos),
                    Money.plain(line.profitCentavos),
                    line.payment,
                    pdfSafe(line.customer ?? ''),
                  ],
              ],
            ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _pdfTotals(ReportData data) {
    pw.Widget tile(String label, String value) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  label,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  value,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );

    return pw.Row(
      children: [
        tile('TOTAL GROSS SALES (PHP)', Money.plain(data.grossCentavos)),
        pw.SizedBox(width: 8),
        tile('TOTAL PROFIT (PHP)', Money.plain(data.profitCentavos)),
        pw.SizedBox(width: 8),
        tile('ITEMS SOLD', '${data.qty}'),
        pw.SizedBox(width: 8),
        tile('TRANSACTIONS', '${data.saleCount}'),
      ],
    );
  }
}

String _paymentLabel(String? code) => switch (code) {
      'credit' || 'utang' => 'Credit',
      'gcash' => 'GCash',
      _ => 'Cash',
    };

/// Folds text down to what the built-in PDF fonts can actually draw.
///
/// The writer ships the 14 standard PDF fonts, which are WinAnsi and have no
/// glyph for the typographic punctuation used across this app -- the en dash in
/// a week label, the em dash in a heading -- nor for the peso sign. Left alone,
/// the pdf package logs "Unable to find a font to draw" and silently omits the
/// character.
///
/// Product and customer names are whatever was typed into the app, so this runs
/// over every string that reaches the page rather than just the fixed headings.
/// Embedding a Unicode font would be the alternative, at roughly half a megabyte
/// in the APK for a handful of characters that have fine ASCII stand-ins.
String pdfSafe(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    out.write(switch (rune) {
      0x2013 || 0x2014 || 0x2212 => '-', // en dash, em dash, minus sign
      0x2018 || 0x2019 || 0x201B => "'",
      0x201C || 0x201D => '"',
      0x2026 => '...',
      0x00B7 || 0x2022 => '-', // middle dot, bullet
      0x20B1 => 'PHP', // peso sign
      0x00A0 => ' ',
      // Latin-1 is covered by WinAnsi; anything beyond it has no glyph to fall
      // back to, so it becomes a visible placeholder rather than vanishing.
      _ => rune < 0x20
          ? ' '
          : rune <= 0xFF
              ? String.fromCharCode(rune)
              : '?',
    });
  }
  return out.toString();
}
