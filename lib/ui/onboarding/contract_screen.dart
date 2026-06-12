import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:printing/printing.dart';
import '../../theme/qoima_design.dart';

/// Партнёрге арналған шарт (оферта). `assets/documents/shart.pdf`-ты қосымша
/// ішінде ашады. Owner дүкен ашу заявкасында осымен танысып, галочка қояды.
class ContractScreen extends StatelessWidget {
  const ContractScreen({super.key});

  Future<Uint8List> _bytes() async {
    final data = await rootBundle.load('assets/documents/shart.pdf');
    return data.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        const QGradientHeader(
          title: 'Договор оферты',
          subtitle: 'Условия для партнёров маркетплейса',
          showBack: true,
        ),
        Expanded(
          child: PdfPreview(
            build: (format) => _bytes(),
            useActions: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowPrinting: false,
            allowSharing: false,
            scrollViewDecoration: const BoxDecoration(color: cBg),
            loadingWidget: const Center(
              child: CircularProgressIndicator(color: cGreen, strokeWidth: 2),
            ),
          ),
        ),
      ]),
    );
  }
}
