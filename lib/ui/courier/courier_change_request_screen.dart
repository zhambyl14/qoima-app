import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/lang.dart';
import '../../data/models/courier_change_request_model.dart';
import '../../data/services/courier_service.dart';
import '../../theme/qoima_design.dart';
import 'courier_data_fields.dart';

/// Курьер — «Өзгертуге сұраныс» формасы (0074).
///
/// Тек өзгерген өрістер жіберіледі; модератор бекітпейінше деректер
/// ауыспайды. Табысты жіберілсе `true` қайтарып жабылады.
class CourierChangeRequestScreen extends StatefulWidget {
  final CourierProfile profile;
  const CourierChangeRequestScreen({super.key, required this.profile});

  @override
  State<CourierChangeRequestScreen> createState() =>
      _CourierChangeRequestScreenState();
}

class _CourierChangeRequestScreenState
    extends State<CourierChangeRequestScreen> {
  final _service = CourierService();
  late final TextEditingController _name;
  final _reason = TextEditingController();
  late String _city;
  bool _busy = false;
  String? _nameErr;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
    _city = widget.profile.city;
  }

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// Ағымдағы мәннен өзгеше өрістер ғана.
  Map<String, String> _diff() {
    final out = <String, String>{};
    final name = _name.text.trim();
    if (name != widget.profile.name) out['name'] = name;
    if (_city.isNotEmpty && _city != widget.profile.city) out['city'] = _city;
    return out;
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _submit() async {
    final changes = _diff();
    final nameErr = changes.containsKey('name') &&
            (changes['name']!.length < 2 || changes['name']!.length > 60)
        ? tr('Имя: от 2 до 60 символов', 'Есім: 2-ден 60 таңбаға дейін')
        : null;
    setState(() => _nameErr = nameErr);
    if (nameErr != null) return;
    if (changes.isEmpty) {
      _snack(tr('Вы ничего не изменили', 'Ештеңе өзгертілмеді'), cAmber);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      await _service.requestChange(changes, reason: _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(courierDataErrorText(e), cRed);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Запрос на изменение', 'Өзгертуге сұраныс'),
          subtitle: tr('Рассматривает модератор', 'Модератор қарайды'),
          showBack: true,
          compact: true,
        ),
        Expanded(
          child: ListView(
            // Scaffold клавиатураға өзі бейімделеді — viewInsets қосылмайды.
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cBlueTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: cBlueInk, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(
                              'Данные изменятся только после одобрения модератора. '
                                  'Номер для входа меняется отдельно — через Telegram '
                                  'в разделе «Пароль и номер входа».',
                              'Деректер модератор мақұлдағаннан кейін ғана өзгереді. '
                                  'Кіру нөмірі бөлек өзгереді — «Құпиясөз және кіру '
                                  'нөмірі» бөліміндегі Telegram арқылы.'),
                          style:
                              manrope(12.5, FontWeight.w600, color: cBlueInk),
                        ),
                      ),
                    ]),
              ),
              CourierTextField(
                label: tr('Имя', 'Есім'),
                controller: _name,
                maxLength: 60,
                errorText: _nameErr,
              ),
              CourierCityField(
                value: _city,
                onChanged: (c) => setState(() => _city = c),
              ),
              CourierTextField(
                label: tr('Причина (необязательно)', 'Себебі (міндетті емес)'),
                controller: _reason,
                maxLength: 500,
                maxLines: 3,
                hint: tr('Например: переехал в другой город',
                    'Мысалы: басқа қалаға көштім'),
              ),
              const SizedBox(height: 4),
              QPrimaryButton(
                label: tr('Отправить запрос', 'Сұраныс жіберу'),
                isLoading: _busy,
                onPressed: _busy ? null : _submit,
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
