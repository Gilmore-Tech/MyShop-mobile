import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_models/shared_models.dart';

/// Builds a printable/shareable earnings report PDF from an [EarningsReport].
///
/// Stays self-contained — no Flutter, theme, or asset dependencies — so the
/// same builder can run from a background isolate later if generation grows
/// past a few-hundred-row series.
class EarningsReportPdf {
  EarningsReportPdf._();

  /// Renders the report as PDF bytes ready for `Printing.sharePdf`.
  ///
  /// [providerName] / [providerPhone] are surfaced in the header so the
  /// document is self-identifying when shared as an attachment.
  /// [dateLabel] is the human-friendly window string already shown in the
  /// UI (e.g. "Last 7 days", "Apr 12 - Apr 19, 2026") — passed through so
  /// the PDF and the screen agree on what window the numbers cover.
  static Future<Uint8List> build({
    required EarningsReport report,
    required EarningsRole role,
    required String dateLabel,
    String? providerName,
    String? providerPhone,
  }) async {
    final doc = pw.Document(
      title: 'MyShop Earnings Report',
      author: providerName ?? 'MyShop Provider',
    );

    final generatedAt = DateTime.now();
    final bookingsLabel = role == EarningsRole.driver ? 'Trips' : 'Jobs';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 32),
        header: (ctx) => ctx.pageNumber == 1
            ? _buildHeader(
                role: role,
                dateLabel: dateLabel,
                generatedAt: generatedAt,
                providerName: providerName,
                providerPhone: providerPhone,
              )
            : pw.SizedBox.shrink(),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 18),
          _buildSummaryGrid(report: report, bookingsLabel: bookingsLabel),
          pw.SizedBox(height: 22),
          _buildBreakdownSection(
            report: report,
            bookingsLabel: bookingsLabel,
          ),
          pw.SizedBox(height: 22),
          _buildLegalNote(),
        ],
      ),
    );

    return doc.save();
  }

  // ─── Sections ────────────────────────────────────────────────────────────

  static pw.Widget _buildHeader({
    required EarningsRole role,
    required String dateLabel,
    required DateTime generatedAt,
    String? providerName,
    String? providerPhone,
  }) {
    final roleLabel = role == EarningsRole.driver ? 'Driver' : 'Artisan';
    final generatedFmt =
        DateFormat("MMM d, yyyy 'at' h:mm a").format(generatedAt);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'MyShop',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: _brandGold,
                    letterSpacing: -0.4,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Earnings Report — $roleLabel',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: _surfaceMuted,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Period',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: _textSecondary,
                      letterSpacing: 0.6,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    dateLabel,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        if (providerName != null || providerPhone != null)
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _surfaceMuted,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              children: [
                if (providerName != null) ...[
                  _kvPair(label: 'Provider', value: providerName),
                  pw.SizedBox(width: 24),
                ],
                if (providerPhone != null)
                  _kvPair(label: 'Phone', value: providerPhone),
              ],
            ),
          ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Generated $generatedFmt',
          style: pw.TextStyle(
            fontSize: 9,
            color: _textSecondary,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: _border, height: 1),
      ],
    );
  }

  static pw.Widget _buildSummaryGrid({
    required EarningsReport report,
    required String bookingsLabel,
  }) {
    final avgFareCell = report.bookingsCompleted == 0
        ? '—'
        : 'GHS ${_fmtGhs(report.averageFarePesewas)}';
    final hours = (report.hoursWorkedMinutes / 60).toStringAsFixed(1);

    final cells = <_SummaryCellData>[
      _SummaryCellData(
        label: 'Gross',
        value: 'GHS ${_fmtGhs(report.grossEarningsPesewas)}',
        sub: 'Cash + in-app',
      ),
      _SummaryCellData(
        label: 'Net',
        value: 'GHS ${_fmtGhs(report.netEarningsPesewas)}',
        sub: 'After commission',
        highlight: true,
      ),
      _SummaryCellData(
        label: 'Commission',
        value: 'GHS ${_fmtGhs(report.commissionChargedPesewas)}',
        sub: 'Recorded total',
      ),
      // Tips cell removed — no tip surface in the rider app yet, so the
      // backend's `tipsEarnedPesewas` is always 0 for rides.
      _SummaryCellData(
        label: bookingsLabel,
        value: '${report.bookingsCompleted}',
        sub: 'Completed',
      ),
      _SummaryCellData(
        label: 'Avg Fare',
        value: avgFareCell,
        sub: 'Per booking',
      ),
      _SummaryCellData(
        label: 'Active Hours',
        value: '${hours}h',
        sub: 'On a booking',
      ),
      if (report.trendPct != null)
        _SummaryCellData(
          label: 'Trend',
          value: _fmtTrend(report.trendPct!),
          sub: 'vs prior window',
        )
      else
        _SummaryCellData(
          label: 'Trend',
          value: '—',
          sub: 'No prior data',
        ),
    ];

    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in cells)
          pw.SizedBox(
            width: (PdfPageFormat.a4.availableWidth - 64 - 30) / 4,
            child: _summaryCell(c),
          ),
      ],
    );
  }

  static pw.Widget _buildBreakdownSection({
    required EarningsReport report,
    required String bookingsLabel,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Breakdown',
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        pw.SizedBox(height: 8),
        if (report.series.isEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: _surfaceMuted,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              'No bookings completed in this period.',
              style: pw.TextStyle(
                fontSize: 10,
                color: _textSecondary,
              ),
            ),
          )
        else
          _buildBreakdownTable(
            series: report.series,
            granularity: report.granularity,
            bookingsLabel: bookingsLabel,
          ),
      ],
    );
  }

  static pw.Widget _buildBreakdownTable({
    required List<EarningsReportPoint> series,
    required EarningsGranularity granularity,
    required String bookingsLabel,
  }) {
    final headerStyle = pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: _textSecondary,
      letterSpacing: 0.5,
    );
    final cellStyle = pw.TextStyle(fontSize: 10, color: _textPrimary);

    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.4),
        1: pw.FlexColumnWidth(1.0),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.4),
        4: pw.FlexColumnWidth(1.4),
        5: pw.FlexColumnWidth(1.0),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _surfaceMuted),
          children: [
            _tableCell('Period', headerStyle),
            _tableCell(bookingsLabel, headerStyle, align: pw.Alignment.center),
            _tableCell('Gross', headerStyle, align: pw.Alignment.centerRight),
            _tableCell('Net', headerStyle, align: pw.Alignment.centerRight),
            _tableCell('Commission', headerStyle,
                align: pw.Alignment.centerRight),
            // Tips column removed (see note on summary section above).
          ],
        ),
        for (final p in series)
          pw.TableRow(
            children: [
              _tableCell(
                  _formatBucketDate(p.bucketStart, granularity), cellStyle),
              _tableCell('${p.count}', cellStyle, align: pw.Alignment.center),
              _tableCell('GHS ${_fmtGhs(p.grossPesewas)}', cellStyle,
                  align: pw.Alignment.centerRight),
              _tableCell('GHS ${_fmtGhs(p.netPesewas)}', cellStyle,
                  align: pw.Alignment.centerRight),
              _tableCell('GHS ${_fmtGhs(p.commissionPesewas)}', cellStyle,
                  align: pw.Alignment.centerRight),
            ],
          ),
      ],
    );
  }

  static pw.Widget _buildLegalNote() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.5),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        'Earnings shown reflect MyShop\'s settled records and may exclude '
        'cash trips or pending Paystack settlements. This document is '
        'tax-ready but is not a tax statement; consult a qualified advisor '
        'for filings. Records are retained for 24 months.',
        style: pw.TextStyle(
          fontSize: 9,
          color: _textSecondary,
          lineSpacing: 2,
        ),
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context ctx) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'MyShop Provider Earnings',
            style: pw.TextStyle(fontSize: 8, color: _textSecondary),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  // ─── Cell helpers ────────────────────────────────────────────────────────

  static pw.Widget _summaryCell(_SummaryCellData c) {
    final bg = c.highlight ? _darkSlate : PdfColors.white;
    final fg = c.highlight ? PdfColors.white : _textPrimary;
    final subFg = c.highlight ? PdfColor.fromInt(0x99FFFFFF) : _textSecondary;

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(
          color: c.highlight ? _darkSlate : _border,
          width: 0.5,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            c.label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: subFg,
              letterSpacing: 0.6,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            c.value,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: fg,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            c.sub,
            style: pw.TextStyle(
              fontSize: 8,
              color: subFg,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _kvPair({required String label, required String value}) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '$label: ',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _textSecondary,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 10,
            color: _textPrimary,
          ),
        ),
      ],
    );
  }

  static pw.Widget _tableCell(
    String text,
    pw.TextStyle style, {
    pw.Alignment align = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      alignment: align,
      child: pw.Text(text, style: style),
    );
  }

  // ─── Formatters ──────────────────────────────────────────────────────────

  static String _fmtGhs(int pesewas) {
    final ghs = pesewas / 100;
    if (ghs == ghs.truncateToDouble()) return ghs.toStringAsFixed(0);
    return ghs.toStringAsFixed(2);
  }

  static String _fmtTrend(double pct) {
    final sign = pct >= 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(1)}%';
  }

  static String _formatBucketDate(DateTime utc, EarningsGranularity g) {
    final local = utc.toLocal();
    switch (g) {
      case EarningsGranularity.day:
        return DateFormat('EEE, MMM d').format(local);
      case EarningsGranularity.week:
        return 'Week of ${DateFormat('MMM d').format(local)}';
      case EarningsGranularity.month:
        return DateFormat('MMM yyyy').format(local);
    }
  }

  // ─── Brand palette mirrored from MyShopColors ────────────────────────────

  static const PdfColor _brandGold = PdfColor.fromInt(0xFFF5A623);
  static const PdfColor _darkSlate = PdfColor.fromInt(0xFF46535D);
  static const PdfColor _textPrimary = PdfColor.fromInt(0xFF161A1D);
  static const PdfColor _textSecondary = PdfColor.fromInt(0xFF555E68);
  static const PdfColor _surfaceMuted = PdfColor.fromInt(0xFFF3F5F6);
  static const PdfColor _border = PdfColor.fromInt(0xFFE5E7EB);
}

class _SummaryCellData {
  const _SummaryCellData({
    required this.label,
    required this.value,
    required this.sub,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String sub;
  final bool highlight;
}
