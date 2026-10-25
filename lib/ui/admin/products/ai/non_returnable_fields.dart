import 'package:flutter/material.dart';

import '../../../../core/feature_flags.dart';
import '../../../../core/lang.dart';
import '../../../../theme/qoima_design.dart';

/// «Қайтарылмайтын тауар» ауыстырғышы + себеп жазбасы.
///
/// Тек екі шарт орындалғанда көрінеді: (1) суперадмин `non_returnable`
/// жалаушасын қосқан, (2) суперадмин дәл осы дүкенге рұқсат берген
/// ([storeAllowed] = stores.allow_non_returnable). Күй формада тұрады.
/// Қосу және өңдеу формаларында ортақ.
class NonReturnableFields extends StatelessWidget {
  final bool storeAllowed;
  final bool value;
  final ValueChanged<bool> onChanged;
  final TextEditingController noteCtrl;

  /// Тауар ӘЛДЕҚАЙДА қайтарылмайтын болып белгіленген, бірақ жалауша өшік
  /// болса да иесі белгіні алып тастай алуы үшін (қосуға болмайды).
  final bool alreadyOn;

  const NonReturnableFields({
    super.key,
    required this.storeAllowed,
    required this.value,
    required this.onChanged,
    required this.noteCtrl,
    this.alreadyOn = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FeatureFlags.instance,
      builder: (context, _) {
        final flagOn = FeatureFlags.instance.isOn(FeatureFlags.nonReturnable);
        // Жалауша өшік: жаңа белгі қоюға болмайды, бар белгіні алуға болады.
        if (!storeAllowed) return const SizedBox.shrink();
        if (!flagOn && !alreadyOn) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: value ? cAmberTint : Colors.white,
            borderRadius: BorderRadius.circular(kR14),
            border: Border.all(
                color: value ? cAmber.withValues(alpha: 0.45) : cLine),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.assignment_return_outlined,
                  size: 20, color: cAmberInk),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Возврату не подлежит', 'Қайтарылмайды'),
                          style: manrope(14, FontWeight.w800, color: cInk)),
                      const SizedBox(height: 2),
                      Text(
                          tr('Покупатель увидит отметку на карточке и сможет оформить возврат только при браке.',
                              'Сатып алушы карточкада белгіні көреді; қайтару тек ақау болғанда ғана мүмкін.'),
                          style: manrope(11.5, FontWeight.w500,
                              color: cInk2, height: 1.3)),
                    ]),
              ),
              Switch(
                value: value,
                activeThumbColor: cGreen,
                onChanged: (flagOn || value) ? onChanged : null,
              ),
            ]),
            if (value) ...[
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                maxLength: 300,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: manrope(13.5, FontWeight.w600, color: cInk),
                decoration: InputDecoration(
                  labelText:
                      tr('Причина (необязательно)', 'Себебі (міндетті емес)'),
                  hintText: tr(
                      'Напр: нижнее бельё, гигиена', 'Мыс: іш киім, гигиена'),
                  filled: true,
                  fillColor: Colors.white,
                  counterText: '',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: cLine)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: cLine)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: cGreen, width: 1.5)),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }
}
