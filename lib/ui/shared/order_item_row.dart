import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/lang.dart';
import '../../data/models/cart_item_model.dart';
import '../../theme/qoima_design.dart';

/// Ағымдағы дүкеннің қаласы — процесс бойы БІР рет оқылады.
///
/// «Басқа қала ма?» деген сұрақ әр тапсырыс карточкасында туындайды, ал жауабы
/// сеанс ішінде өзгермейді. Әр карточка өз сұранысын жіберсе — экранда 20
/// тапсырыс болса, 20 бірдей сұраныс кетер еді.
class StoreCityCache {
  static Future<String>? _pending;
  static String? _value;

  static String? get cached => _value;

  static Future<String> load() async {
    if (_value != null) return _value!;
    return _pending ??= _fetch();
  }

  static Future<String> _fetch() async {
    try {
      final sb = Supabase.instance.client;
      final owner = await sb.rpc('app_owner_uid');
      final row = await sb
          .from('stores')
          .select('city')
          .eq('admin_uid', owner as Object)
          .maybeSingle();
      _value = ((row?['city'] as String?) ?? '').trim();
    } catch (_) {
      _value = '';
    }
    _pending = null;
    return _value!;
  }
}

/// Тапсырыс позициясы — АДМИН мен САТУШЫ көретін түрі.
///
/// НЕГЕ КЕРЕК: бұрын мұнда бір ғана жол тұратын — «New Balance 530 (EU 42)».
/// Сол атаумен қоймада 4 түс, 2 модификация тұруы мүмкін. Сатушы қайсысын
/// беретінін БІЛМЕЙТІН де, қате тауар беріп жіберетін — ал клиент оны үйде
/// ашып көргенде возврат басталатын. Енді фото + бренд/түс/түрі + артикул
/// көрінеді: тауарды қолға алмай тұрып тануға жеткілікті.
///
/// Клиент экранында қолданылмайды (онда өз, ықшам түрі бар).
class OrderItemRow extends StatelessWidget {
  final CartItemModel item;

  /// Курьер «өлшеп көру» свопын жасағанда — қай өлшем қалды/қайтты деген
  /// белгіні көрсету үшін.
  final bool showFittingNote;

  const OrderItemRow({
    super.key,
    required this.item,
    this.showFittingNote = true,
  });

  @override
  Widget build(BuildContext context) {
    final identity = item.identityLine;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Фото: ең жылдам тану тәсілі ────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 46,
            height: 46,
            child: item.imageUrl.isEmpty
                ? _placeholder()
                : Image.network(item.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.productName,
                style: manrope(13.5, FontWeight.w800, color: cInk),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (identity.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(trValue(identity),
                    style: manrope(11.5, FontWeight.w600, color: cInk2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _chip(tr('Размер ${item.size}', '${item.size} өлшем'),
                  strong: true),
              if (item.qty > 1) _chip('×${item.qty}'),
              if (item.articul.isNotEmpty) _chip(item.articul),
            ]),
            // ── «Өлшеп көру»: қосалқы өлшем де жиналуы керек ────────────────
            if (showFittingNote && item.hasAltSize && !item.fittingResolved)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: _note(
                    Icons.checkroom_rounded,
                    tr('Примерка: положите ещё ${item.altSize}',
                        'Өлшеп көру: ${item.altSize} өлшемін де салыңыз'),
                    cAmber),
              ),
            if (showFittingNote && item.fittingResolved)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: _note(
                    Icons.assignment_return_rounded,
                    tr('Клиент взял ${item.size}, возвращается ${item.returningSize}',
                        'Клиент ${item.size} алды, ${item.returningSize} қайтады'),
                    cBlue),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        Text('${item.subtotal.toStringAsFixed(0)} ₸',
            style: manrope(13.5, FontWeight.w800, color: cInk)),
      ]),
    );
  }

  static Widget _placeholder() => Container(
        color: cGreenTint,
        child: const Icon(Icons.inventory_2_outlined, size: 20, color: cGreen),
      );

  static Widget _chip(String text, {bool strong = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: strong ? cGreenTint : cBg,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(text,
            style: manrope(11, FontWeight.w800,
                color: strong ? cGreenDeep : cInk2)),
      );

  static Widget _note(IconData icon, String text, Color tone) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 5),
          Expanded(
            child: Text(text,
                style: manrope(11, FontWeight.w700, color: tone)),
          ),
        ],
      );
}

/// Жеткізу мекенжайы — ҚАЛАСЫМЕН БІРГЕ.
///
/// НЕГЕ КЕРЕК: бұрын тек көше жазылатын («Бараева 28»). Дүкен өзі жеткізетін
/// қалада (курьерлік қызмет жоқ) сатушы қай ҚАЛАҒА жіберетінін білмейтін —
/// ал «Бараева» көшесі бірнеше қалада бар. Енді қала бөлек көрінеді әрі
/// дүкеннің қаласымен сәйкес келмесе АЙҚЫН ескерту шығады: ол — почтамен
/// жөнелту, қолмен апару емес.
class OrderDestinationCard extends StatefulWidget {
  final String city;
  final String address;

  /// Жеткізуді платформа курьері орындай ма (олай болса бұл карточка тек
  /// ақпарат үшін — сатушы ешқайда бармайды).
  final bool byCourier;

  const OrderDestinationCard({
    super.key,
    required this.city,
    required this.address,
    this.byCourier = false,
  });

  @override
  State<OrderDestinationCard> createState() => _OrderDestinationCardState();
}

class _OrderDestinationCardState extends State<OrderDestinationCard> {
  String _storeCity = StoreCityCache.cached ?? '';

  @override
  void initState() {
    super.initState();
    if (StoreCityCache.cached == null) {
      StoreCityCache.load().then((c) {
        if (mounted) setState(() => _storeCity = c);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final city = widget.city;
    final address = widget.address;
    final byCourier = widget.byCourier;
    final c = city.trim();
    final sc = _storeCity.trim();
    // Қала белгісіз болса «басқа қала» деп қорқытпаймыз, бірақ дәл солай
    // «сіздің қала» деп те айта алмаймыз — үнсіз қалдырамыз.
    final otherCity =
        c.isNotEmpty && sc.isNotEmpty && c.toLowerCase() != sc.toLowerCase();
    final tone = otherCity ? cAmber : cBlue;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(otherCity ? Icons.local_post_office_rounded : Icons.place_rounded,
            size: 17, color: tone),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(
                    c.isEmpty ? tr('Город не указан', 'Қала көрсетілмеген') : trValue(c),
                    style: manrope(13, FontWeight.w800, color: cInk),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (otherCity) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: cAmber, borderRadius: BorderRadius.circular(5)),
                  child: Text(tr('ДРУГОЙ ГОРОД', 'БАСҚА ҚАЛА'),
                      style: manrope(9, FontWeight.w800, color: Colors.white)),
                ),
              ],
            ]),
            if (address.trim().isNotEmpty)
              Text(address.trim(),
                  style: manrope(12, FontWeight.w600, color: cInk2)),
            const SizedBox(height: 3),
            Text(
                byCourier
                    ? tr('Курьер заберёт со склада и доставит сам',
                        'Курьер қоймадан алып, өзі жеткізеді')
                    : otherCity
                        ? tr('Другой город — отправьте почтой/курьерской службой и сообщите клиенту трек',
                            'Басқа қала — поштамен/жөнелту қызметімен жіберіп, клиентке трек хабарлаңыз')
                        : tr('Доставляете вы сами — свяжитесь с клиентом и согласуйте время',
                            'Өзіңіз жеткізесіз — клиентпен байланысып, уақытты келісіңіз'),
                style: manrope(11, FontWeight.w700, color: tone, height: 1.3)),
          ]),
        ),
      ]),
    );
  }
}
