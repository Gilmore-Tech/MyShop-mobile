import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../providers/payment_provider.dart';

// PRD § 7.2 / 4.6 — payment receipt artifact.
// Built from a [PaymentConfirmation] returned by /payments/initiate so the
// document can be rendered the moment the success dialog appears, with no
// extra round-trip to the backend. Use `Printing.sharePdf(bytes:..., filename:..)`
// to surface the system share sheet (covers WhatsApp, Email, Drive AND
// Save-to-Files / Save-to-Phone in one place).

const _gold = PdfColor.fromInt(0xFFF5A623);
const _goldDark = PdfColor.fromInt(0xFFD48E1A);
const _darkText = PdfColor.fromInt(0xFF161A1D);
const _textSecondary = PdfColor.fromInt(0xFF555E68);
const _success = PdfColor.fromInt(0xFF27AE60);
const _surfaceGrey = PdfColor.fromInt(0xFFF3F5F6);
const _divider = PdfColor.fromInt(0xFFE2E5E8);

/// Builds the PDF receipt for a completed escrow payment.
Future<Uint8List> buildPaymentReceiptPdf(PaymentConfirmation c) async {
  final doc = pw.Document(
    title: 'MyShop Receipt ${c.transactionRef}',
    author: 'MyShop',
    subject: 'Payment Receipt',
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(c),
          pw.SizedBox(height: 28),
          _amountBlock(c),
          pw.SizedBox(height: 24),
          _sectionLabel('PAYMENT DETAILS'),
          pw.SizedBox(height: 10),
          _detailsTable(c),
          pw.SizedBox(height: 28),
          _sectionLabel('NOTES'),
          pw.SizedBox(height: 8),
          pw.Text(
            'Funds are held in escrow and released to the provider after dual '
            'confirmation. Keep this receipt for your records — it is the '
            'reference for any dispute or refund request.',
            style: const pw.TextStyle(
              fontSize: 10,
              color: _textSecondary,
              lineSpacing: 3,
            ),
          ),
          pw.Spacer(),
          _footer(c),
        ],
      ),
    ),
  );

  return doc.save();
}

pw.Widget _header(PaymentConfirmation c) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(18),
    decoration: pw.BoxDecoration(
      gradient: pw.LinearGradient(
        colors: const [_gold, _goldDark],
        begin: pw.Alignment.topLeft,
        end: pw.Alignment.bottomRight,
      ),
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'MyShop',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Payment Receipt',
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.white,
                ),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(20),
              ),
              child: pw.Text(
                'PAID',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _success,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              c.transactionRef,
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              c.dateTimeLabel,
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.white,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _amountBlock(PaymentConfirmation c) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(vertical: 22, horizontal: 16),
    decoration: pw.BoxDecoration(
      color: _surfaceGrey,
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Column(
      children: [
        pw.Text(
          'TOTAL PAID',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _textSecondary,
            letterSpacing: 1.4,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          c.amountDisplay,
          style: pw.TextStyle(
            fontSize: 32,
            fontWeight: pw.FontWeight.bold,
            color: _darkText,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'to ${c.artisanName}',
          style: const pw.TextStyle(
            fontSize: 11,
            color: _textSecondary,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _sectionLabel(String label) => pw.Text(
      label,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: _textSecondary,
        letterSpacing: 1.4,
      ),
    );

pw.Widget _detailsTable(PaymentConfirmation c) {
  final rows = <(String, String)>[
    ('Transaction Ref', c.transactionRef),
    ('Provider', c.artisanName),
    ('Job', c.jobTitle),
    ('Method', c.method.label),
    ('Amount', c.amountDisplay),
    ('Date & Time', c.dateTimeLabel),
    ('Status', 'Completed (Escrowed)'),
  ];

  return pw.Column(
    children: [
      for (var i = 0; i < rows.length; i++) ...[
        _detailRow(rows[i].$1, rows[i].$2),
        if (i != rows.length - 1) pw.Container(height: 0.6, color: _divider),
      ],
    ],
  );
}

pw.Widget _detailRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 9),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 2,
          child: pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 10,
              color: _textSecondary,
            ),
          ),
        ),
        pw.Expanded(
          flex: 3,
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _darkText,
            ),
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _footer(PaymentConfirmation c) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Container(height: 0.6, color: _divider),
      pw.SizedBox(height: 10),
      pw.Text(
        'Thank you for using MyShop.',
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: _darkText,
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        'This receipt is generated electronically — no signature required.',
        style: const pw.TextStyle(fontSize: 8, color: _textSecondary),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        'Support: support@myshop.com.gh   ·   myshop.com.gh',
        style: const pw.TextStyle(fontSize: 8, color: _textSecondary),
      ),
    ],
  );
}
