import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';

/// Қарапайым мәтін енгізу диалогы — тізімде жоқ «өз нұсқасын» жазу үшін
/// (тауар түрі, материал т.б.). Бос емес мән қайтарады, әйтпесе null.
Future<String?> promptTextDialog(
  BuildContext context, {
  required String title,
  String hint = '',
  String initial = '',
}) async {
  final ctrl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Отмена', 'Бас тарту'))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: cGreen, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: Text(tr('Готово', 'Дайын')),
        ),
      ],
    ),
  );
  return (result == null || result.isEmpty) ? null : result;
}
