import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../providers/ride_receipt_provider.dart';

// PRD § 4.6 — ride receipt artifact.
// Built from a [RideReceiptData] (already loaded from GET /v1/rides/:id once the
// ride is completed) so the document renders without an extra backend round-trip.
// Use `Printing.sharePdf(bytes:..., filename:..)` to surface the system share
// sheet (covers WhatsApp, Email, Drive AND Save-to-Files / Save-to-Phone in one
// place). Mirrors the escrow payment receipt in
// features/services/utils/payment_receipt_pdf.dart for a consistent look.

const _gold = PdfColor.fromInt(0xFFF5A623);
const _goldDark = PdfColor.fromInt(0xFFD48E1A);
const _darkText = PdfColor.fromInt(0xFF161A1D);
const _textSecondary = PdfColor.fromInt(0xFF555E68);
const _success = PdfColor.fromInt(0xFF27AE60);
const _surfaceGrey = PdfColor.fromInt(0xFFF3F5F6);
const _divider = PdfColor.fromInt(0xFFE2E5E8);

/// Builds the PDF receipt for a completed ride.
Future<Uint8List> buildRideReceiptPdf(RideReceiptData r) async {
  final doc = pw.Document(
    title: 'MyShop Receipt ${r.rideId}',
    author: 'MyShop',
    subject: 'Ride Receipt',
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(r),
          pw.SizedBox(height: 28),
          _amountBlock(r),
          pw.SizedBox(height: 24),
          _sectionLabel('TRIP'),
          pw.SizedBox(height: 10),
          _tripTable(r),
          pw.SizedBox(height: 22),
          _sectionLabel('PAYMENT BREAKDOWN'),
          pw.SizedBox(height: 10),
          _breakdownTable(r),
          pw.SizedBox(height: 22),
          _sectionLabel('PAYMENT METHOD'),
          pw.SizedBox(height: 8),
          pw.Text(
            r.paymentMethodLabel,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _darkText,
            ),
          ),
          pw.Spacer(),
          _footer(),
        ],
      ),
    ),
  );

  return doc.save();
}

pw.Widget _header(RideReceiptData r) {
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
                'Ride Receipt',
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
              r.rideId,
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (r.dateTimeLabel.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                r.dateTimeLabel,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.white,
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

pw.Widget _amountBlock(RideReceiptData r) {
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
          r.totalPaidDisplay,
          style: pw.TextStyle(
            fontSize: 32,
            fontWeight: pw.FontWeight.bold,
            color: _darkText,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'with ${r.driverName}',
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

pw.Widget _tripTable(RideReceiptData r) {
  final rows = <(String, String)>[
    ('Driver', r.driverName),
    ('Vehicle', r.vehicleDisplay),
    ('Pickup', r.pickupAddress),
    ('Destination', r.dropoffAddress),
    if (r.dateTimeLabel.isNotEmpty) ('Date & Time', r.dateTimeLabel),
  ];
  return _rows(rows);
}

pw.Widget _breakdownTable(RideReceiptData r) {
  final rows = <(String, String)>[
    ('Base Fare', r.baseFareDisplay),
    ('Distance (${r.distanceKm.toStringAsFixed(1)} km)', r.distanceFareDisplay),
    ('Booking Fee', r.bookingFeeDisplay),
    ('Taxes & Levies', r.taxesDisplay),
    ('Total Paid', r.totalPaidDisplay),
  ];
  return _rows(rows, emphasizeLast: true);
}

pw.Widget _rows(List<(String, String)> rows, {bool emphasizeLast = false}) {
  return pw.Column(
    children: [
      for (var i = 0; i < rows.length; i++) ...[
        _detailRow(
          rows[i].$1,
          rows[i].$2,
          emphasize: emphasizeLast && i == rows.length - 1,
        ),
        if (i != rows.length - 1) pw.Container(height: 0.6, color: _divider),
      ],
    ],
  );
}

pw.Widget _detailRow(String label, String value, {bool emphasize = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 9),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 2,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: emphasize ? 11 : 10,
              fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: emphasize ? _darkText : _textSecondary,
            ),
          ),
        ),
        pw.Expanded(
          flex: 3,
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: emphasize ? 11 : 10,
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

pw.Widget _footer() {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Container(height: 0.6, color: _divider),
      pw.SizedBox(height: 10),
      pw.Text(
        'Thank you for riding with MyShop.',
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
