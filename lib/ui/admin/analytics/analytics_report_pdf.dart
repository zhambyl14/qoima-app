import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/lang.dart';
import '../../../data/models/sale_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

/// Айлық PDF есебін жасап, ішкі преview экранына апарады (сол экранда
/// «Поделиться» батырмасы әрқашан көрінеді — платформа share sheet-іне
/// тікелей сүйенбейміз, өйткені кейбір Android құрылғыларда ол тікелей PDF
/// көрсеткішке апарып, «Поделиться» батырмасынсыз қалдыруы мүмкін).
/// Файл серверде САҚТАЛМАЙДЫ — тек құрылғының уақытша кэшінде.
Future<void> generateAndShareMonthlyReport({
  required BuildContext context,
  required FirestoreService service,
  required DateTime month,
}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
        child: CircularProgressIndicator(color: cGreen, strokeWidth: 2.5)),
  );
  try {
    final sales = await service.watchSalesForMonth(month).first;
    final prevMonth = DateTime(month.year, month.month - 1);
    final prevSales = await service.watchSalesForMonth(prevMonth).first;

    final bytes = await _buildReportPdf(
        month: month, sales: sales, prevSales: prevSales);

    if (!context.mounted) return;
    Navigator.pop(context);

    final fname =
        'qoima_${month.year}_${month.month.toString().padLeft(2, '0')}.pdf';
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => _ReportPreviewScreen(bytes: bytes, filename: fname)),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            tr('Не удалось сформировать отчёт', 'Есеп жасалмады')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

class _ReportPreviewScreen extends StatelessWidget {
  final Uint8List bytes;
  final String filename;
  const _ReportPreviewScreen({required this.bytes, required this.filename});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 10),
                Text(tr('Отчёт', 'Есеп'),
                    style: manrope(20, FontWeight.w800, color: Colors.white)),
              ]),
            ),
          ),
        ),
        Expanded(
          child: PdfPreview(
            build: (format) async => bytes,
            pdfFileName: filename,
            allowSharing: true,
            allowPrinting: true,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            useActions: true,
          ),
        ),
      ]),
    );
  }
}

String _normMethod(String m) {
  final s = m.toLowerCase();
  if (s == 'card' || s.contains('карт') || s.contains('kaspi') || s.contains('halyk')) {
    return 'card';
  }
  return 'cash';
}

Future<Uint8List> _buildReportPdf({
  required DateTime month,
  required List<SaleModel> sales,
  required List<SaleModel> prevSales,
}) async {
  double revenueOf(Iterable<SaleModel> l) =>
      l.fold<double>(0, (a, e) => a + e.totalPrice);

  final pure = sales.where((s) => !s.isOnline).toList();
  final online = sales.where((s) => s.isOnline).toList();

  final offlineRevenue = revenueOf(pure);
  final onlineRevenue = revenueOf(online);
  final totalRevenue = offlineRevenue + onlineRevenue;

  final totalCost = sales.fold<double>(
      0,
      (acc, e) => acc +
          (e.isReturn
              ? -(e.purchasePrice * e.quantity)
              : e.purchasePrice * e.quantity));
  final margin = totalRevenue - totalCost;

  final cashRevenue = pure
      .where((s) => _normMethod(s.paymentMethod.isEmpty ? 'cash' : s.paymentMethod) == 'cash')
      .fold<double>(0, (a, e) => a + e.totalPrice);
  final cardRevenue = offlineRevenue - cashRevenue;

  final onlineUnits = online.fold<int>(
      0, (acc, e) => acc + (e.isReturn ? -e.quantity : e.quantity));
  final offlineUnits = pure.fold<int>(
      0, (acc, e) => acc + (e.isReturn ? -e.quantity : e.quantity));

  final returnsList = sales.where((s) => s.isReturn).toList();
  final returnsCount = returnsList.length;
  final returnedUnits = returnsList.fold<int>(0, (a, e) => a + e.quantity);

  final prevPure = prevSales.where((s) => !s.isOnline);
  final prevOnline = prevSales.where((s) => s.isOnline);
  final prevRevenue = revenueOf(prevPure) + revenueOf(prevOnline);
  final double changePct = prevRevenue > 0
      ? ((totalRevenue - prevRevenue) / prevRevenue * 100)
      : (totalRevenue > 0 ? 100 : 0);

  final regular = await PdfGoogleFonts.notoSansRegular();
  final bold = await PdfGoogleFonts.notoSansBold();
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);

  String money(num v) {
    final s = v.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}$buf ₸';
  }

  const monthNamesRu = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];
  final title = '${monthNamesRu[month.month - 1]} ${month.year}';

  final green = PdfColor.fromInt(0xFF00A862);
  final ink = PdfColor.fromInt(0xFF1A1A1A);
  final ink2 = PdfColor.fromInt(0xFF6B7280);
  final red = PdfColor.fromInt(0xFFDC2626);

  pw.Widget row(String label, String value, {PdfColor? color, bool bold_ = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 12, color: ink2)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 12.5,
                    color: color ?? ink,
                    fontWeight: bold_ ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  pw.Widget sectionTitle(String s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Text(s,
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold, color: green)),
      );

  final doc = pw.Document(theme: theme);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Qoima — отчёт за месяц',
              style: pw.TextStyle(fontSize: 12, color: ink2)),
          pw.Text(title,
              style:
                  pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: ink)),
          pw.SizedBox(height: 6),
          pw.Container(height: 2, color: green),

          sectionTitle('Выручка'),
          row('Общая выручка', money(totalRevenue), bold_: true),
          row('  Офлайн', money(offlineRevenue)),
          row('  Онлайн', money(onlineRevenue)),
          row('Изменение к прошлому месяцу',
              '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(1)}%',
              color: changePct >= 0 ? green : red, bold_: true),

          sectionTitle('Прибыль'),
          row('Себестоимость', money(totalCost)),
          row('Маржа', money(margin), color: margin >= 0 ? green : red, bold_: true),

          sectionTitle('Офлайн-продажи по оплате'),
          row('Наличными', money(cashRevenue)),
          row('Картой / переводом', money(cardRevenue)),
          row('Продано штук офлайн', '$offlineUnits'),

          sectionTitle('Онлайн-продажи'),
          row('Продано штук онлайн', '$onlineUnits'),
          row('Выручка онлайн', money(onlineRevenue)),

          sectionTitle('Возвраты'),
          row('Количество возвратов', '$returnsCount'),
          row('Возвращено штук', '$returnedUnits'),

          pw.SizedBox(height: 24),
          pw.Text('Сформировано в приложении Qoima',
              style: pw.TextStyle(fontSize: 9.5, color: ink2)),
        ],
      ),
    ),
  );

  return doc.save();
}
