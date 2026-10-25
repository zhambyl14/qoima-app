import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_user.dart';
import '../../../core/feature_flags.dart';
import '../../../core/lang.dart';
import '../../../data/models/catalog_hit.dart';
import '../../../data/services/ai_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/require_login.dart';
import '../client_shell.dart';
import 'ai_navigation.dart';

class _Msg {
  final String role; // 'user' | 'assistant'
  final String text;
  final List<CatalogHit> products;
  final bool isWelcome;
  const _Msg(this.role, this.text,
      {this.products = const [], this.isWelcome = false});
}

/// AI-көмекші: чат арқылы каталогтан тауар таңдау (ai-assistant функциясы).
/// Әңгіме экран тірі тұрғанда ғана жадта сақталады.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _ai = AiService();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  final List<_Msg> _msgs = [];
  bool _sending = false;
  int? _remaining;

  @override
  void initState() {
    super.initState();
    _msgs.add(_Msg(
      'assistant',
      tr('Здравствуйте! Я AI-помощник Qoima. Расскажите, что ищете: повод, бюджет, размер, и я подберу варианты из каталога.',
          'Сәлем! Мен Qoima AI-көмекшісімін. Не іздейтініңізді айтыңыз: себебі, бюджет, өлшем, ал мен каталогтан нұсқалар таңдап беремін.'),
      isWelcome: true,
    ));
    _loadQuota();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadQuota() async {
    final r = await _ai.quotaRemaining('assistant');
    if (!mounted) return;
    setState(() => _remaining = r);
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty || _sending) return;
    final ok = await requireLogin(
      context,
      reasonRu: 'Войдите, чтобы пользоваться AI-помощником',
      reasonKk: 'AI-көмекшіні қолдану үшін кіріңіз',
    );
    if (!ok || !mounted) return;
    HapticFeedback.selectionClick();
    final city = context.read<AppUser>().city;
    final userMsg =
        _Msg('user', text.length > 2000 ? text.substring(0, 2000) : text);
    setState(() {
      _msgs.add(userMsg);
      _sending = true;
    });
    _ctrl.clear();
    _toBottom();
    try {
      final history = [
        for (final m in _msgs)
          if (!m.isWelcome) AiChatMessage(m.role, m.text)
      ];
      final r = await _ai.assistantChat(history, city: city);
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg('assistant', r.reply, products: r.products));
        _remaining = r.remaining ?? _remaining;
        _sending = false;
      });
      _toBottom();
    } on AiException catch (e) {
      if (!mounted) return;
      // Сәтсіз сұрауды қайтарып, мәтінді өріске қайта саламыз.
      setState(() {
        _msgs.remove(userMsg);
        _sending = false;
        if (e.isQuota) _remaining = 0;
      });
      _ctrl.text = text;
      aiSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.remove(userMsg);
        _sending = false;
      });
      _ctrl.text = text;
      aiSnack(
          context,
          tr('Что-то пошло не так, попробуйте ещё раз',
              'Бірдеңе дұрыс болмады, қайталап көріңіз'),
          error: true);
    }
  }

  Future<void> _open(CatalogHit hit) async {
    final goCart = await openCatalogHit(context, hit);
    if (goCart == true && mounted) Navigator.of(context).pop(true);
  }

  // ── Тез қосу: өлшем таңдау парақшасы ──
  Future<void> _quickAdd(CatalogHit hit) async {
    HapticFeedback.selectionClick();
    final sizes = hit.sizeList;
    if (sizes.isEmpty) {
      aiSnack(context, tr('Нет в наличии', 'Қоймада жоқ'), error: true);
      return;
    }
    final size = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _SizeSheet(hit: hit),
    );
    if (size == null || !mounted) return;
    context.read<CartProvider>().addItem(hit.toCartItem(size));
    aiSnack(
      context,
      tr('Добавлено в корзину', 'Себетке қосылды'),
      action: SnackBarAction(
        label: tr('В корзину', 'Себетке'),
        textColor: Colors.white,
        onPressed: () {
          if (mounted) Navigator.of(context).pop(true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FeatureFlags.instance,
      builder: (context, _) {
        final on = FeatureFlags.instance.isOn(FeatureFlags.aiAssistant);
        return Scaffold(
          backgroundColor: cBg,
          body: Column(children: [
            QGradientHeader(
              title: tr('AI-помощник', 'AI-көмекші'),
              subtitle: tr('Подберу товары под ваш запрос',
                  'Сұранысыңызға сай тауар таңдап беремін'),
              showBack: true,
            ),
            Expanded(
              child: !on
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          tr('Функция временно отключена',
                              'Функция уақытша өшірулі'),
                          textAlign: TextAlign.center,
                          style: manrope(15, FontWeight.w600, color: cInk2),
                        ),
                      ),
                    )
                  : _buildChat(),
            ),
            if (on) _buildInput(),
          ]),
        );
      },
    );
  }

  Widget _buildChat() {
    final onlyWelcome = _msgs.length == 1;
    final itemCount = _msgs.length + (_sending ? 1 : 0) + (onlyWelcome ? 1 : 0);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      itemCount: itemCount,
      itemBuilder: (_, i) {
        if (i < _msgs.length) return _bubble(_msgs[i]);
        if (onlyWelcome && i == _msgs.length) return _suggestions();
        return const Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: _TypingBubble(),
          ),
        );
      },
    );
  }

  Widget _suggestions() {
    final items = [
      tr('Платье на той до 30 000 ₸', 'Тойға 30 000 ₸-ге дейін көйлек'),
      tr('Белые кроссовки 42 размер', '42 өлшемді ақ кроссовка'),
      tr('Подарок мужу', 'Күйеуге сыйлық'),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in items)
          GestureDetector(
            onTap: () => _send(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: cGreenTint,
                borderRadius: BorderRadius.circular(kRPill),
                border: Border.all(color: cGreenTint2),
              ),
              child: Text(s,
                  style: manrope(13, FontWeight.w700, color: cGreenDeep)),
            ),
          ),
      ]),
    );
  }

  Widget _bubble(_Msg m) {
    final isUser = m.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? cGreen : cSurface,
              border: isUser ? null : Border.all(color: cLine),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18),
              ),
            ),
            child: SelectableText(
              m.text,
              style: manrope(14, FontWeight.w500,
                  color: isUser ? Colors.white : cInk, height: 1.4),
            ),
          ),
          if (m.products.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 278,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: m.products.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _productCard(m.products[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _productCard(CatalogHit h) {
    return GestureDetector(
      onTap: () => _open(h),
      child: Container(
        width: 152,
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(kR16),
          border: Border.all(color: cLine),
          boxShadow: kShadowXs,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            SizedBox(
              width: 152,
              height: 140,
              child: h.imageUrl.isEmpty
                  ? const ColoredBox(color: cLine2)
                  : Image.network(h.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: cLine2)),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: GestureDetector(
                onTap: () => _quickAdd(h),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: cGreen,
                    shape: BoxShape.circle,
                    boxShadow: kShadowGreen,
                  ),
                  child: const Icon(Icons.add_shopping_cart_rounded,
                      color: Colors.white, size: 17),
                ),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(12.5, FontWeight.w700,
                      color: cInk, height: 1.25)),
              const SizedBox(height: 3),
              Text(money(h.price),
                  style: manrope(14, FontWeight.w800, color: cInk)),
              Text(h.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(11, FontWeight.w500, color: cInk3)),
              if (h.reason.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(h.reason,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(11, FontWeight.w500,
                        color: cGreenDeep, height: 1.3)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildInput() {
    final noQuota = _remaining == 0;
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        border: Border(top: BorderSide(color: cLine)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_remaining != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    noQuota
                        ? tr('Лимит сообщений на сегодня исчерпан',
                            'Бүгінгі хабарлама лимиті бітті')
                        : tr('Осталось сообщений сегодня: $_remaining',
                            'Бүгін қалған хабарлама: $_remaining'),
                    style: manrope(11.5, FontWeight.w600,
                        color: noQuota ? cRedInk : cInk3),
                  ),
                ),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  enabled: !noQuota,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: manrope(14, FontWeight.w500, color: cInk),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: tr('Что вы ищете?', 'Не іздейсіз?'),
                    hintStyle: manrope(14, FontWeight.w500, color: cInk3),
                    filled: true,
                    fillColor: cBg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kRPill),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: (_sending || noQuota) ? null : _send,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: (_sending || noQuota) ? null : kGrad,
                    color: (_sending || noQuota) ? cLine : null,
                    shape: BoxShape.circle,
                  ),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                              color: cGreen, strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward_rounded,
                          color: Colors.white, size: 22),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── Өлшем таңдау парақшасы ──────────────────────────────────────────────────
class _SizeSheet extends StatefulWidget {
  final CatalogHit hit;
  const _SizeSheet({required this.hit});

  @override
  State<_SizeSheet> createState() => _SizeSheetState();
}

class _SizeSheetState extends State<_SizeSheet> {
  String? _size;

  @override
  void initState() {
    super.initState();
    final s = widget.hit.sizeList;
    if (s.length == 1) _size = s.first;
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.hit;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(kR12),
              child: SizedBox(
                width: 56,
                height: 56,
                child: h.imageUrl.isEmpty
                    ? const ColoredBox(color: cLine2)
                    : Image.network(h.imageUrl, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(14, FontWeight.w700, color: cInk)),
                    Text(money(h.priceFor(_size)),
                        style: manrope(14, FontWeight.w800, color: cGreenDeep)),
                  ]),
            ),
          ]),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(tr('Размер', 'Өлшем'),
                style: manrope(12.5, FontWeight.w700, color: cInk2)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SizeChips(
              sizes: h.sizeList,
              selected: _size,
              onSelect: (s) => setState(() => _size = s),
            ),
          ),
          const SizedBox(height: 18),
          QPrimaryButton(
            label: tr('Добавить в корзину', 'Себетке қосу'),
            onPressed:
                _size == null ? null : () => Navigator.pop(context, _size),
          ),
        ]),
      ),
    );
  }
}

// ── «Жазып жатыр…» индикаторы ───────────────────────────────────────────────
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cSurface,
        border: Border.all(color: cLine),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
        ),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
              child: Opacity(
                opacity: 0.35 + 0.65 * _wave(_c.value, i),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      color: cGreen, shape: BoxShape.circle),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  // 0..1 толқын, әр нүкте 0.18 фазаға кешігеді.
  double _wave(double t, int i) {
    final x = (t - i * 0.18) % 1.0;
    return x < 0.5 ? x * 2 : (1 - x) * 2;
  }
}
