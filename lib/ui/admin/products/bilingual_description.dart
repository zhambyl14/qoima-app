import 'package:flutter/material.dart';

import '../../../core/lang.dart';
import '../../../core/locale_context.dart';
import '../../../data/models/product_model.dart';
import '../../../data/services/product_assist_service.dart';
import '../../../theme/qoima_design.dart';

/// Форманың бастапқы сипаттама тілі: қолданба тілі (kk болса — қазақша).
String defaultDescriptionLang() =>
    LocaleContext.currentLang == 'kk' ? 'kk' : 'ru';

/// Қарсы тіл ('ru' ↔ 'kk').
String otherDescriptionLang(String lang) => lang == 'kk' ? 'ru' : 'kk';

/// Сипаттама өрісі + үстінде «РУС | ҚАЗ» ауыстырғыш. Екі контроллер де
/// сақталады: ауыстырғанда мәтін жоғалмайды, екеуі де сақтауға кетеді.
/// Тіл белгісінің жанындағы нүкте: сол тілде мәтін бар/жоқ екенін көрсетеді.
class BilingualDescriptionField extends StatelessWidget {
  final TextEditingController ruCtrl;
  final TextEditingController kkCtrl;

  /// Белсенді табтың тілі: 'ru' | 'kk'.
  final String lang;
  final ValueChanged<String> onLangChanged;
  final ValueChanged<String>? onChanged;
  final InputDecoration decoration;

  /// Аудару батырмасы: null болса көрсетілмейді.
  final VoidCallback? onTranslate;
  final bool translateBusy;

  const BilingualDescriptionField({
    super.key,
    required this.ruCtrl,
    required this.kkCtrl,
    required this.lang,
    required this.onLangChanged,
    required this.decoration,
    this.onChanged,
    this.onTranslate,
    this.translateBusy = false,
  });

  TextEditingController get _active => lang == 'kk' ? kkCtrl : ruCtrl;

  Widget _tab(String code, String label, bool hasText) {
    final sel = lang == code;
    return GestureDetector(
      onTap: () => onLangChanged(code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? cGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: manrope(12, FontWeight.w800,
                  color: sel ? Colors.white : cInk2)),
          const SizedBox(width: 5),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasText
                  ? (sel ? Colors.white : cGreen)
                  : (sel ? Colors.white.withValues(alpha: 0.45) : cLine),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Контроллер өзгергенде нүктелер мен «Аудару» жаңарады.
    return ListenableBuilder(
      listenable: Listenable.merge([ruCtrl, kkCtrl]),
      builder: (context, _) {
        final hasRu = ruCtrl.text.trim().isNotEmpty;
        final hasKk = kkCtrl.text.trim().isNotEmpty;
        final otherHas = lang == 'kk' ? hasRu : hasKk;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                  tr('Описание (необязательно)', 'Сипаттама (міндетті емес)'),
                  style: manrope(13, FontWeight.w600, color: cInk2)),
            ),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: cLine2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cLine),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _tab('ru', 'РУС', hasRu),
                _tab('kk', 'ҚАЗ', hasKk),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            // Тіл ауысқанда өріс басқа контроллермен қайта құрылады.
            key: ValueKey('desc-$lang'),
            controller: _active,
            onChanged: onChanged,
            maxLines: 4,
            minLines: 3,
            maxLength: ProductModel.descriptionMaxLength,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 15, color: cInk),
            decoration: decoration,
          ),
          if (onTranslate != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              GestureDetector(
                onTap: translateBusy ? null : onTranslate,
                child: Opacity(
                  opacity: otherHas || translateBusy ? 1 : 0.5,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cPurpleTint,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: cPurple.withValues(alpha: 0.4)),
                    ),
                    child: translateBusy
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    color: cPurple, strokeWidth: 2)),
                            const SizedBox(width: 7),
                            Text(tr('Перевожу…', 'Аударып жатыр…'),
                                style: manrope(12, FontWeight.w700,
                                    color: cPurpleInk)),
                          ])
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.translate_rounded,
                                size: 15, color: cPurple),
                            const SizedBox(width: 6),
                            Text(
                                lang == 'kk'
                                    ? tr('Перевести с русского', 'Орысшадан аудару')
                                    : tr('Перевести с казахского',
                                        'Қазақшадан аудару'),
                                style: manrope(12, FontWeight.w700,
                                    color: cPurpleInk)),
                          ]),
                  ),
                ),
              ),
            ]),
          ],
        ]);
      },
    );
  }
}

/// Аударма қатесі/өшірілген жалауша үшін қысқа достық хабар. Квота, жалауша,
/// желі сияқты нақты себептерді сервис хабарынан аламыз; ескі функция
/// режимді білмесе (bad_request) — жалпы «қазір қолжетімсіз».
String optionalAiMessage(ProductAssistException e) {
  switch (e.code) {
    case 'ai_quota_exceeded':
    case 'feature_disabled':
    case 'not_configured':
    case 'not_authorized':
    case 'network':
    case 'ai_busy':
    case 'invalid_session':
      return e.message;
    default:
      return tr('AI сейчас недоступен. Попробуйте позже.',
          'AI қазір қолжетімсіз. Кейінірек қайталаңыз.');
  }
}
