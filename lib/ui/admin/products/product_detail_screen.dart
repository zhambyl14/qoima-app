import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/app_user.dart';
import '../../../core/supabase_config.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/cloudinary_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/color_picker_sheet.dart';
import '../../shared/prompt_text_dialog.dart';
import '../../widgets/image_crop_screen.dart';
import '../../../core/color_naming.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

import '../../../core/lang.dart';
class ProductDetailScreen extends StatefulWidget {
  final ProductModel product;
  const ProductDetailScreen({super.key, required this.product});
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _service = FirestoreService();
  int _photoIndex = 0;
  bool _photoExpanded = false;

  // Онлайн-магазин (жарияланған дүкен) бар ма — жоқ болса «Виден в
  // онлайн-витрине» блогы мүлдем көрсетілмейді (мағынасы жоқ).
  bool _storePublished = false;

  @override
  void initState() {
    super.initState();
    _service.getStore().then((store) {
      if (mounted && store != null && store.isPublished) {
        setState(() => _storePublished = true);
      }
    }).catchError((_) {});
  }

  // Суреттер жергілікті state-те — өңдеуден кейін бірден жаңарады
  // (widget.product.images өзгермейді). Деталь экраны осыны көрсетеді.
  late List<String> _images = List.of(widget.product.images);

  // Тауар да жергілікті state-те — атауын/түсін өңдегеннен кейін экран
  // бірден жаңа деректерді көрсетеді (widget.product иммутабельді).
  late ProductModel _product = widget.product;

  Future<void> _deleteBatch(BatchModel batch) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Удалить поставку?', 'Партияны өшіру керек пе?')),
        content: Text(
            tr('Действие необратимо. Поставка и связанные продажи будут удалены.', 'Әрекет қайтарылмайды. Партия және байланысты сатылымдар өшіріледі.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Отмена', 'Болдырмау')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: cRed),
            child: Text(tr('Удалить', 'Өшіру')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final removedImages =
          await _service.deleteBatch(widget.product.id, batch.id);
      if (removedImages.isNotEmpty) {
        // Товар толық өшті (партия/сатылым жоқ) — суреттерін Cloudinary-ден
        // тазалап, экраннан шығамыз (көрсететін тауар қалмады).
        await CloudinaryService().deleteMany(removedImages);
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      // Архивке көшірілген жағдай (сатылымы бар партия) — хабарлама көрсетеміз.
      if (!mounted) return;
      final msg = e is SaleException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: cInk2,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _editBatch(BatchModel batch) async {
    final purchaseCtrl =
        TextEditingController(text: batch.purchasePrice.toStringAsFixed(0));
    final sellingCtrl =
        TextEditingController(text: batch.sellingPrice.toStringAsFixed(0));
    DateTime tempDate = batch.dateArrived;
    final tempSizes = Map<String, int>.from(batch.sizesQuantity);

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr('Редактировать поставку', 'Партияны өңдеу')),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: tempDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setS(() => tempDate = picked);
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      '${tempDate.day.toString().padLeft(2, '0')}.${tempDate.month.toString().padLeft(2, '0')}.${tempDate.year}',
                    ),
                  ),
                  TextField(
                    controller: purchaseCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        InputDecoration(labelText: tr('Закупочная цена', 'Сатып алу бағасы')),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: sellingCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        InputDecoration(labelText: tr('Цена продажи', 'Сату бағасы')),
                  ),
                  const SizedBox(height: 10),
                  Text(tr('Размеры', 'Өлшемдер'),
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  ...tempSizes.keys.map((size) {
                    final qty = tempSizes[size] ?? 0;
                    return Row(
                      children: [
                        SizedBox(width: 34, child: Text(size)),
                        IconButton(
                          onPressed: qty > 0
                              ? () => setS(() => tempSizes[size] = qty - 1)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('$qty',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        IconButton(
                          onPressed: () =>
                              setS(() => tempSizes[size] = qty + 1),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Отмена', 'Болдырмау'))),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Сохранить', 'Сақтау'))),
          ],
        ),
      ),
    );

    if (save != true) return;

    await _service.updateBatch(
      productId: widget.product.id,
      batchId: batch.id,
      dateArrived: tempDate,
      purchasePrice:
          double.tryParse(purchaseCtrl.text.trim()) ?? batch.purchasePrice,
      sellingPrice:
          double.tryParse(sellingCtrl.text.trim()) ?? batch.sellingPrice,
      sizesQuantity: tempSizes,
    );
  }

  // ── Тауар карточкасын өңдеу (атауы, бренд, түрі, кімге, түсі, материал) ──
  Future<void> _editProductInfo() async {
    final p = _product;
    final catKey = p.effectiveCategoryKey;
    final nameCtrl = TextEditingController(text: p.name);
    final brandCtrl = TextEditingController(text: p.brand);
    final descCtrl = TextEditingController(text: p.description);
    final countryCtrl = TextEditingController(text: p.country);

    // Канондық тізімдер + ескі товардағы тізімнен тыс мән жоғалмасын
    final baseTypes = kTypesByCategory[catKey] ?? const <String>[];
    final types = [
      ...baseTypes,
      if (p.type.isNotEmpty && !baseTypes.contains(p.type)) p.type,
    ];
    final groups = [
      ...kProductTargetGroups,
      if (p.category.isNotEmpty && !kProductTargetGroups.contains(p.category))
        p.category,
    ];
    final baseMaterials = kMaterialsByCategory[catKey] ?? const <String>[];
    final materials = [
      ...baseMaterials,
      if (p.material.isNotEmpty && !baseMaterials.contains(p.material))
        p.material,
    ];

    String type = p.type;
    String group = p.category;
    String color = p.color;
    String colorHex = p.customColorHex; // HSV-мен таңдалған ерекше түс HEX-і
    String material = p.material;
    String season = p.season;
    // Дропдаун ішкі state-і «Свой вариант…» пунктінде қалып қоймауы үшін
    // key арқылы қайта құрылады.
    int typeNonce = 0;
    const customTypeOption = '__custom__';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Widget label(String text) => Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 8),
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cInk2)),
              );
          Widget chip(String text, bool sel, VoidCallback onTap) =>
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? cGreen : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: sel ? cGreen : cLine, width: sel ? 1.5 : 1),
                  ),
                  child: Text(text,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.white : cInk2)),
                ),
              );
          InputDecoration deco(String labelText) => InputDecoration(
                labelText: labelText,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: cLine)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: cLine)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: cGreen, width: 1.5)),
              );

          return Container(
            decoration: const BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                MediaQuery.of(ctx).viewInsets.bottom +
                    MediaQuery.of(ctx).padding.bottom +
                    24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                            color: cLine,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 14),
                  Text(tr('Редактировать товар', 'Тауарды өңдеу'),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: cInk)),
                  const SizedBox(height: 16),
                  TextField(
                      controller: nameCtrl,
                      decoration: deco(tr('Название товара', 'Тауар атауы'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: brandCtrl, decoration: deco('Бренд')),
                  label(tr('Тип товара', 'Тауар түрі')),
                  DropdownButtonFormField<String>(
                    key: ValueKey('etype-$typeNonce-$type'),
                    initialValue: types.contains(type) ? type : null,
                    isExpanded: true,
                    decoration: deco(tr('Тип', 'Түрі')),
                    items: [
                      ...types.map((e) => DropdownMenuItem(
                          value: e, child: Text(trValue(e)))),
                      DropdownMenuItem(
                        value: customTypeOption,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.edit_outlined,
                              size: 16, color: cGreen),
                          const SizedBox(width: 6),
                          Text(tr('Свой вариант…', 'Өз нұсқасы…'),
                              style: const TextStyle(
                                  color: cGreen,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v != customTypeOption) {
                        setS(() => type = v ?? type);
                        return;
                      }
                      final value = await promptTextDialog(
                        ctx,
                        title: tr('Свой тип товара', 'Өз тауар түрі'),
                        hint: tr('Например: Мокасины', 'Мысалы: Мокасиндер'),
                      );
                      setS(() {
                        typeNonce++;
                        if (value != null) {
                          if (!types.contains(value)) types.add(value);
                          type = value;
                        }
                      });
                    },
                  ),
                  label(tr('Кому', 'Кімге')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: groups
                        .map((g) => chip(trValue(g), group == g,
                            () => setS(() => group = g)))
                        .toList(),
                  ),
                  label(tr('Цвет', 'Түсі')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...ProductModel.colorOptions.map((opt) {
                        final name = opt['name'] as String;
                        final c = Color(opt['hex'] as int);
                        // Стандарт түс — тек custom HEX болмағанда таңдалған.
                        final sel = color == name && colorHex.isEmpty;
                        final isLight = c.computeLuminance() > 0.7;
                        return GestureDetector(
                          onTap: () => setS(() {
                            color = name;
                            colorHex = ''; // ерекше түсті тазалаймыз
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? c : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: sel ? c : cLine, width: sel ? 2 : 1),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: isLight
                                          ? Colors.grey.shade300
                                          : Colors.transparent,
                                      width: 1),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(trValue(name),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? (isLight ? cInk : Colors.white)
                                        : cInk2,
                                  )),
                            ]),
                          ),
                        );
                      }),
                      // Ерекше түс (HSV): таңдалса — осы чип белсенді, нақты
                      // түспен + автомат атпен көрінеді. Басу — қайта таңдау.
                      Builder(builder: (_) {
                        final hasCustom = colorHex.isNotEmpty;
                        final cc = hexToColor(colorHex);
                        final isLight =
                            (cc ?? cGreen).computeLuminance() > 0.7;
                        return GestureDetector(
                          onTap: () async {
                            final picked = await showCustomColorPicker(ctx,
                                initial: cc ?? const Color(0xFF12C97A));
                            if (picked != null) {
                              setS(() {
                                color = describeColorName(picked);
                                colorHex = colorToHex(picked);
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: hasCustom ? (cc ?? cGreen) : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: hasCustom ? (cc ?? cGreen) : cLine,
                                  width: hasCustom ? 2 : 1),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.colorize_rounded,
                                  size: 15,
                                  color: hasCustom
                                      ? (isLight ? cInk : Colors.white)
                                      : cGreen),
                              const SizedBox(width: 6),
                              Text(
                                  hasCustom
                                      ? trValue(color)
                                      : tr('Свой цвет', 'Өз түсі'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: hasCustom
                                        ? (isLight ? cInk : Colors.white)
                                        : cGreen,
                                  )),
                            ]),
                          ),
                        );
                      }),
                    ],
                  ),
                  label(tr('Материал (необязательно)', 'Материал (міндетті емес)')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...materials.map((m) => chip(
                          trValue(m),
                          material == m,
                          () =>
                              setS(() => material = material == m ? '' : m))),
                      chip(tr('✏️ Свой', '✏️ Өз нұсқасы'), false, () async {
                        final value = await promptTextDialog(
                          ctx,
                          title: tr('Свой материал', 'Өз материалы'),
                          hint: tr('Например: Нубук', 'Мысалы: Нубук'),
                        );
                        if (value == null) return;
                        setS(() {
                          if (!materials.contains(value)) {
                            materials.add(value);
                          }
                          material = value;
                        });
                      }),
                    ],
                  ),
                  label(tr('Сезон (необязательно)', 'Сезон (міндетті емес)')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kSeasons
                        .map((s) => chip(trValue(s), season == s,
                            () => setS(() => season = season == s ? '' : s)))
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                      controller: countryCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: deco(tr('Страна производства (необязательно)', 'Өндірілген ел (міндетті емес)'))),
                  const SizedBox(height: 12),
                  TextField(
                      controller: descCtrl,
                      maxLines: 4,
                      minLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: deco(tr('Описание (необязательно)', 'Сипаттама (міндетті емес)'))
                          .copyWith(alignLabelWithHint: true)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (nameCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(tr('Введите название товара', 'Тауар атауын енгізіңіз')),
                            backgroundColor: cRed,
                            behavior: SnackBarBehavior.floating,
                          ));
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0),
                      child: Text(tr('Сохранить', 'Сақтау'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (saved != true) return;
    final newName = nameCtrl.text.trim();
    final newBrand = brandCtrl.text.trim();
    try {
      await _service.updateProductInfo(
        p.id,
        name: newName,
        brand: newBrand,
        type: type,
        material: material,
        category: group,
        color: color,
        colorHex: colorHex,
        description: descCtrl.text.trim(),
        country: countryCtrl.text.trim(),
        season: season,
      );
      if (!mounted) return;
      setState(() => _product = _product.copyWith(
            name: newName,
            brand: newBrand,
            type: type,
            material: material,
            category: group,
            color: color,
            customColorHex: colorHex,
            description: descCtrl.text.trim(),
            country: countryCtrl.text.trim(),
            season: season,
          ));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Товар обновлён', 'Тауар жаңартылды')),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Не удалось сохранить: $e', 'Сақтау мүмкін болмады: $e')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Тауарды бөлісу (публичный веб-сілтеме → WhatsApp/Telegram/копия) ──────
  // Сілтемені кез келген адам браузерде аша алады (қосымша қажет емес).
  // Дүкен публичный болмаса, бет «қолжетімсіз» деп көрсетеді (Edge Function).
  bool _togglingStorefront = false;

  Future<void> _toggleStorefront(bool hidden) async {
    if (_togglingStorefront) return;
    setState(() {
      _togglingStorefront = true;
      _product = _product.copyWith(storefrontHidden: hidden);
    });
    try {
      await _service.setStorefrontHidden(_product.id, hidden);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(hidden
              ? tr('Товар скрыт с онлайн-витрины', 'Тауар онлайн-витринадан жасырылды')
              : tr('Товар снова в витрине', 'Тауар қайта витринада')),
          backgroundColor: hidden ? cInk2 : cGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      // Сәтсіз — күйді артқа қайтарамыз.
      if (mounted) {
        setState(() => _product = _product.copyWith(storefrontHidden: !hidden));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Не удалось изменить', 'Өзгерту сәтсіз')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _togglingStorefront = false);
    }
  }

  Widget _buildStorefrontToggle() {
    final noPhoto = _images.isEmpty;
    // Фотосыз тауар витринада көрінбейді (сурет қосылса — автоматты шығады).
    final hidden = _product.storefrontHidden || noPhoto;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: noPhoto
            ? cAmberTint
            : (hidden ? cBg : cGreenTint.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: noPhoto
                ? cAmber.withValues(alpha: 0.4)
                : (hidden ? cLine : cGreen.withValues(alpha: 0.3))),
      ),
      child: Row(children: [
        Icon(
            noPhoto
                ? Icons.add_a_photo_outlined
                : (hidden ? Icons.visibility_off_outlined : Icons.storefront_outlined),
            color: noPhoto
                ? const Color(0xFF92400E)
                : (hidden ? cInk3 : cGreenDeep),
            size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  noPhoto
                      ? tr('Не в витрине — нет фото', 'Витринада жоқ — фото жоқ')
                      : hidden
                          ? tr('Скрыт с онлайн-витрины', 'Онлайн-витринадан жасырын')
                          : tr('Виден в онлайн-витрине', 'Онлайн-витринада көрінеді'),
                  style: manrope(13.5, FontWeight.w700,
                      color: noPhoto
                          ? const Color(0xFF92400E)
                          : (hidden ? cInk2 : cGreenDeep))),
              Text(
                  noPhoto
                      ? tr('Добавьте фото, чтобы показать покупателям', 'Сатып алушыларға көрсету үшін фото қосыңыз')
                      : hidden
                          ? tr('Остаётся на складе для учёта', 'Есеп үшін қоймада қалады')
                          : tr('Покупатели видят этот товар', 'Сатып алушылар бұл тауарды көреді'),
                  style: manrope(11.5, FontWeight.w500, color: cInk3)),
            ],
          ),
        ),
        Switch(
          value: !hidden,
          activeThumbColor: Colors.white,
          activeTrackColor: cGreen,
          onChanged: (_togglingStorefront || noPhoto)
              ? null
              : (v) => _toggleStorefront(!v),
        ),
      ]),
    );
  }

  Future<void> _shareProduct(BuildContext originContext) async {
    final p = _product;
    final url = SupabaseConfig.productShareUrl(p.id);
    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Ссылки для обмена ещё не настроены',
            'Бөлісу сілтемесі әлі бапталмаған')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final text = p.name.isNotEmpty ? '${p.name}\n$url' : url;
    // iPad/iOS-та share sheet popover анкерін талап етеді (sharePositionOrigin).
    // Бөлісу батырмасының экрандағы тіктөртбұрышын береміз — болмаса
    // PlatformException("sharePositionOrigin: argument must be set").
    Rect? origin;
    final box = originContext.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    }
    try {
      await Share.share(text, subject: p.name, sharePositionOrigin: origin);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Не удалось поделиться: $e', 'Бөлісу мүмкін болмады: $e')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _openPhotoManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhotoManagerSheet(
        productId: widget.product.id,
        initial: _images,
        onChanged: (updated) {
          if (!mounted) return;
          setState(() {
            _images = updated;
            if (_photoIndex >= _images.length) {
              _photoIndex = _images.isEmpty ? 0 : _images.length - 1;
            }
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    final isAdmin = context.read<AppUser>().isAdmin;

    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<BatchModel>>(
        stream: _service.watchBatchesWithCost(p.id),
        builder: (context, batchSnap) {
          final batches = batchSnap.data ?? [];
          final activeBatches =
              batches.where((b) => b.totalQuantity > 0).toList();
          final soldBatches =
              batches.where((b) => b.totalQuantity <= 0).toList();
          final totalPairs =
              batches.fold<int>(0, (s, b) => s + b.totalQuantity);

          final Map<String, int> totalSizes = {};
          for (final b in batches) {
            b.sizesQuantity
                .forEach((k, v) => totalSizes[k] = (totalSizes[k] ?? 0) + v);
          }
          final availSizes = totalSizes.entries
              .where((e) => e.value > 0)
              .toList()
            ..sort((a, b) =>
                (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0));

          // Статус белгісін тірі қоймадан аламыз (сатылым/қайтарудан кейін
          // p.status ескіріп қалуы мүмкін). Дерек әлі жүктелмесе — p.status.
          final inStock = batchSnap.hasData
              ? batches.any((b) => b.totalAvailable > 0)
              : p.status == ProductModel.statusInStock;
          final statusLabel = inStock
              ? tr('В наличии', 'Қолда бар')
              : tr('Продано', 'Сатылды');

          return CustomScrollView(slivers: [
            // ── Фото ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: GestureDetector(
                onTap: () => setState(() => _photoExpanded = !_photoExpanded),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                  height: _photoExpanded
                      ? MediaQuery.of(context).size.height * 0.6
                      : 280,
                  child: Stack(fit: StackFit.expand, children: [
                    _images.isNotEmpty
                        ? PageView.builder(
                            itemCount: _images.length,
                            onPageChanged: (i) =>
                                setState(() => _photoIndex = i),
                            itemBuilder: (_, i) => Image.network(
                                  _images[i],
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _placeholder(),
                                ))
                        : _placeholder(),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.6)
                            ],
                            stops: const [0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 12,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.arrow_back_ios_new,
                                color: Colors.white, size: 18)),
                      ),
                    ),
                    // Оң жақ төбедегі әрекеттер: бөлісу · толық экран · сурет
                    // (сурет өңдеу — тек админ).
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      right: 12,
                      child: Row(children: [
                        Builder(
                          builder: (btnCtx) => _GlassIconBtn(
                            icon: Icons.ios_share,
                            onTap: () => _shareProduct(btnCtx),
                          ),
                        ),
                        if (_images.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _GlassIconBtn(
                            icon: _photoExpanded
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                            onTap: () => setState(
                                () => _photoExpanded = !_photoExpanded),
                          ),
                        ],
                        if (isAdmin) ...[
                          const SizedBox(width: 8),
                          _GlassIconBtn(
                            icon: Icons.add_a_photo_outlined,
                            onTap: _openPhotoManager,
                          ),
                        ],
                      ]),
                    ),
                    if (_images.length > 1)
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _images.length,
                            (i) => AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: i == _photoIndex ? 20 : 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: i == _photoIndex
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: inStock ? cGreen : Colors.grey,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(statusLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(p.articul,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),

            // ── Контент ────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Бренд + название
                  Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.brand.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: cGreen,
                                    letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(p.name,
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: cInk,
                                    letterSpacing: -0.5)),
                          ]),
                    ),
                    // Тауар карточкасын өңдеу — ТЕК АДМИН (партия
                    // карандашынан бөлек: атауы/түсі/кімге т.б.)
                    if (isAdmin)
                      IconButton(
                        onPressed: _editProductInfo,
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        color: cGreen,
                        visualDensity: VisualDensity.compact,
                        tooltip: tr('Редактировать товар', 'Тауарды өңдеу'),
                      ),
                    Column(children: [
                      Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: cGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.inventory_2_outlined,
                              color: cGreen, size: 22)),
                      const SizedBox(height: 4),
                      Text(tr('$totalPairs шт.', '$totalPairs дана'),
                          style: const TextStyle(
                              fontSize: 11,
                              color: cInk2,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ]),
                  const SizedBox(height: 8),
                  // Теги
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _Tag(label: trValue(p.type), icon: Icons.category_outlined),
                    _Tag(label: trValue(p.category), icon: Icons.people_outline),
                    if (p.color.isNotEmpty)
                      _Tag(label: trValue(p.color), icon: Icons.palette_outlined),
                    if (p.material.isNotEmpty)
                      _Tag(label: trValue(p.material), icon: Icons.texture_outlined),
                    if (p.season.isNotEmpty)
                      _Tag(label: trValue(p.season), icon: Icons.wb_sunny_outlined),
                    if (p.country.isNotEmpty)
                      _Tag(label: p.country, icon: Icons.public_outlined),
                  ]),
                  const SizedBox(height: 12),

                  // Онлайн-витрина: тауарды жасыру/көрсету — тек админ ЖӘНЕ
                  // онлайн-магазины (жарияланған дүкені) бар болса.
                  if (isAdmin && _storePublished) _buildStorefrontToggle(),

                  // Описание
                  if (p.description.isNotEmpty) ...[
                    _SecTitle(tr('Описание', 'Сипаттама')),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cLine),
                      ),
                      child: Text(p.description,
                          style: const TextStyle(
                              fontSize: 13.5, color: cInk2, height: 1.45)),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Скидка қою «Менің дүкенім → Скидки» бөліміне көшті.
                  // (Бұл жерде енді тауарға тікелей скидка қоюшы кнопка жоқ.)

                  const SizedBox(height: 8),

                  // Размерлер блогы
                  if (context.read<AppUser>().isAdmin) ...[
                    // Админ: тек қолда бар размерлер (Wrap)
                    if (availSizes.isNotEmpty) ...[
                      _SecTitle(tr('Доступные размеры', 'Қолжетімді өлшемдер')),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: availSizes
                            .map((e) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: cGreen
                                            .withValues(alpha: 0.3)),
                                    boxShadow: [
                                      BoxShadow(
                                          color: cGreen
                                              .withValues(alpha: 0.06),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2))
                                    ],
                                  ),
                                  child: Column(children: [
                                    Text(e.key,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                            color: cGreen)),
                                    Text(tr('${e.value} шт', '${e.value} дана'),
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: cInk2)),
                                  ]),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ] else ...[
                    // Саттушы: барлық размерлер grid-те (қолда бар/жоқ)
                    _SecTitle(tr('Размеры', 'Өлшемдер')),
                    const SizedBox(height: 10),
                    _buildSizesGrid(totalSizes),
                    const SizedBox(height: 20),
                  ],

                  // Партии
                  _SecTitle(tr('Партии поставок', 'Жеткізілім партиялары')),
                  const SizedBox(height: 10),
                  if (batchSnap.connectionState == ConnectionState.waiting)
                    const Center(
                        child:
                            CircularProgressIndicator(color: cGreen))
                  else if (batches.isEmpty)
                    Text(tr('Нет партий', 'Партия жоқ'),
                        style: TextStyle(color: cInk3))
                  else ...[
                    if (activeBatches.isNotEmpty) ...[
                      _SecTitle(tr('В наличии', 'Қолда бар')),
                      const SizedBox(height: 8),
                      ...activeBatches.map((b) => _BatchWithSales(
                            batch: b,
                            productId: p.id,
                            service: _service,
                            isArchived: false,
                            onEdit: () => _editBatch(b),
                            onDelete: () => _deleteBatch(b),
                          )),
                    ],
                    if (soldBatches.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _SecTitle(tr('Продано', 'Сатылды')),
                      const SizedBox(height: 8),
                      ...soldBatches.map((b) => _BatchWithSales(
                            batch: b,
                            productId: p.id,
                            service: _service,
                            isArchived: true,
                          )),
                    ],
                  ],
                ]),
              ),
            ),
          ]);
        },
      ),

      // Сату MakeSaleScreen-нен басталады (SalesScreen FAB арқылы)
      bottomNavigationBar: null,
    );
  }

  // Саттушы үшін: барлық размерлер grid-те
  Widget _buildSizesGrid(Map<String, int> allSizes) {
    final sorted = allSizes.entries.toList()
      ..sort((a, b) =>
          (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0));
    if (sorted.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: sorted.length,
      itemBuilder: (_, i) {
        final size = sorted[i].key;
        final qty = sorted[i].value;
        final avail = qty > 0;
        return Container(
          decoration: BoxDecoration(
            color: avail
                ? cGreen.withValues(alpha: 0.1)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: avail
                  ? cGreen.withValues(alpha: 0.1)
                  : cLine,
              width: 1.5,
            ),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(size,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: avail ? cGreen : cInk3,
                )),
            Text(avail ? tr('$qty шт.', '$qty дана') : tr('нет', 'жоқ'),
                style: TextStyle(
                  fontSize: 11,
                  color: avail ? cInk2 : cInk3,
                )),
          ]),
        );
      },
    );
  }

  Widget _placeholder() => Container(
      color: const Color(0xFFEEF2FF),
      child: const Center(
          child: Icon(Icons.inventory_2_outlined,
              size: 60, color: cGreen)));
}

// ── Партия + её продажи ───────────────────────────────────────────────────────
class _BatchWithSales extends StatelessWidget {
  final BatchModel batch;
  final String productId;
  final FirestoreService service;
  final bool isArchived;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _BatchWithSales({
    required this.batch,
    required this.productId,
    required this.service,
    this.isArchived = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final d = batch.dateArrived;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final margin = batch.sellingPrice - batch.purchasePrice;
    final sizes = batch.sizesQuantity.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key}(${e.value})')
        .join('  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isArchived ? const Color(0xFFF3F4F6) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isArchived ? Border.all(color: const Color(0xFFD1D5DB)) : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Заголовок партии
        Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: cGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.local_shipping_outlined,
                    size: 16, color: cGreen),
              ),
              const SizedBox(width: 8),
              Text(tr('Поставка от $dateStr', '$dateStr жеткізілімі'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: cInk)),
              if (isArchived) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tr('Продано', 'Сатылды'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (!isArchived && context.read<AppUser>().isAdmin) ...[
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: cGreen,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: cRed,
                  visualDensity: VisualDensity.compact,
                ),
              ],
              Text(tr('${batch.totalQuantity} шт.', '${batch.totalQuantity} дана'),
                  style: const TextStyle(
                      color: cInk2,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              if (context.read<AppUser>().isAdmin) ...[
                _PriceTag(
                    label: tr('Закуп', 'Сатып алу'),
                    value: '${batch.purchasePrice.toStringAsFixed(0)} ₸',
                    color: cRed),
                const SizedBox(width: 8),
              ],
              _PriceTag(
                  label: tr('Продажа', 'Сату'),
                  value: '${batch.sellingPrice.toStringAsFixed(0)} ₸',
                  color: cGreen),
              if (context.read<AppUser>().isAdmin) ...[
                const SizedBox(width: 8),
                _PriceTag(
                    label: 'Маржа',
                    value:
                        '${margin >= 0 ? "+" : ""}${margin.toStringAsFixed(0)} ₸',
                    color: margin >= 0 ? cGreen : cRed),
              ],
            ]),
            if (sizes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(sizes,
                  style: const TextStyle(
                      fontSize: 11, color: cInk2)),
            ],
          ]),
        ),

        // Продажи этой партии
        FutureBuilder<List<SaleModel>>(
          future: service.getSalesForProduct(productId),
          builder: (_, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            final sales =
                snap.data!.where((s) => s.batchId == batch.id).toList();
            if (sales.isEmpty) return const SizedBox.shrink();

            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Row(children: [
                      const Icon(Icons.receipt_long_outlined,
                          size: 14, color: cInk3),
                      const SizedBox(width: 6),
                      Text(tr('Продажи из этой партии — ${sales.length} опер.', 'Осы партиядан сатылымдар — ${sales.length} опер.'),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cInk2)),
                    ]),
                  ),
                  ...sales.map((s) => _SaleRow(sale: s)),
                  const SizedBox(height: 8),
                ]);
          },
        ),
      ]),
    );
  }
}

// ── Строка продажи внутри партии ──────────────────────────────────────────────
class _SaleRow extends StatelessWidget {
  final SaleModel sale;
  const _SaleRow({required this.sale});

  @override
  Widget build(BuildContext context) {
    final d = sale.saleDate;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final sizes = sale.sizesSold.entries
        .where((e) => e.value > 0)
        .map((e) => tr('Р.${e.key}×${e.value}', 'Ө.${e.key}×${e.value}'))
        .join('  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: cGreenTint,
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.shopping_bag_outlined,
                color: cGreen, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sizes,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cInk)),
              Row(children: [
                Text(
                    sale.sellerName.isNotEmpty
                        ? '• $dateStr • ${sale.sellerName}'
                        : '• $dateStr',
                    style: const TextStyle(
                        fontSize: 10, color: cInk3)),
              ]),
            ]),
          ),
          Text('${sale.totalPrice.toStringAsFixed(0)} ₸',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cGreen)),
        ]),
      ),
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────
class _PriceTag extends StatelessWidget {
  final String label, value;
  final Color color;
  const _PriceTag(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(7)),
      child: Column(children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                color: color.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600)),
        Text(value,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w700)),
      ]));
}

class _Tag extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Tag({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: cBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cLine)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: cInk2),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: cInk2,
                fontWeight: FontWeight.w500)),
      ]));
}

// Сурет үстіндегі күңгірт-шыны батырма (артқа/бөлісу/толық экран/сурет).
class _GlassIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      );
}

class _SecTitle extends StatelessWidget {
  final String text;
  const _SecTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: cInk));
}


// ── Фото менеджер (қосу / жою, макс 4) ────────────────────────────────────────
class _PhotoManagerSheet extends StatefulWidget {
  final String productId;
  final List<String> initial;
  final void Function(List<String>) onChanged;
  const _PhotoManagerSheet({
    required this.productId,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<_PhotoManagerSheet> createState() => _PhotoManagerSheetState();
}

class _PhotoManagerSheetState extends State<_PhotoManagerSheet> {
  static const int _maxImages = 4;
  static const int _cropSize = 1080;

  final _service = FirestoreService();
  final _cloud = CloudinaryService();
  final _picker = ImagePicker();

  late List<String> _imgs = List.of(widget.initial);
  bool _busy = false;

  Future<void> _persist() async {
    await _service.updateProductImages(widget.productId, _imgs);
    widget.onChanged(List.of(_imgs));
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? cRed : cGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _remove(int i) async {
    if (_busy) return;
    // Соңғы фотоны өшіруге БОЛАДЫ — тауар онлайн-витринадан шығады, бірақ
    // қоймада қалады, бар тапсырыстар/сатылымдар тимейді. Растатып аламыз.
    if (_imgs.length <= 1) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(tr('Удалить последнее фото?', 'Соңғы фотоны өшіру?'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: Text(
            tr('Без фото товар пропадёт из онлайн-витрины, но останется на складе. Оформленные заказы не затрагиваются. Фото можно добавить позже.',
                'Фотосыз тауар онлайн-витринадан жоғалады, бірақ қоймада қалады. Рәсімделген тапсырыстар тимейді. Фотоны кейін қосуға болады.'),
            style: manrope(13, FontWeight.w500, color: cInk2),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Отмена', 'Болдырмау'))),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: cRed, foregroundColor: Colors.white),
                child: Text(tr('Удалить', 'Өшіру'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    final url = _imgs[i];
    setState(() {
      _imgs = List.of(_imgs)..removeAt(i);
      _busy = true;
    });
    try {
      await _persist();
      // Cloudinary-ден жою — best-effort (credentials бос болса үнсіз өтеді)
      await _cloud.deleteByUrl(url);
    } catch (e) {
      _snack(tr('Не удалось удалить: $e', 'Өшіру мүмкін болмады: $e'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(ImageSource source) async {
    if (_busy) return;
    if (_imgs.length >= _maxImages) {
      _snack(tr('Максимум $_maxImages фото', 'Ең көбі $_maxImages фото'), error: true);
      return;
    }
    final remaining = _maxImages - _imgs.length;
    List<XFile> picked;
    if (source == ImageSource.camera) {
      final shot =
          await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
      picked = shot == null ? <XFile>[] : [shot];
    } else {
      picked = await _picker.pickMultiImage(imageQuality: 90);
    }
    if (picked.isEmpty) return;
    final toAdd = picked.take(remaining).toList();

    // Әр суретке қолмен кадрлау экраны (жылжыту/масштабтау, 1:1).
    final bytesList = <Uint8List>[];
    for (var i = 0; i < toAdd.length; i++) {
      final raw = await toAdd[i].readAsBytes();
      if (!mounted) return;
      final cropped = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => ImageCropScreen(
            raw: raw,
            outputSize: _cropSize,
            title: toAdd.length > 1 ? tr('Фото ${i + 1} из ${toAdd.length}', 'Фото ${i + 1} / ${toAdd.length}') : null,
          ),
        ),
      );
      if (cropped != null) bytesList.add(cropped);
    }
    if (bytesList.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final urls = await _cloud.uploadBytesList(bytesList);
      setState(() => _imgs = [..._imgs, ...urls]);
      await _persist();
      if (picked.length > remaining) {
        _snack(tr('Добавлено $remaining — лимит $_maxImages фото', 'Қосылды $remaining — лимит $_maxImages фото'));
      }
    } catch (e) {
      _snack(tr('Ошибка загрузки: $e', 'Жүктеу қатесі: $e'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: cGreen),
              title: Text(tr('Сфотографировать', 'Суретке түсіру')),
              onTap: () {
                Navigator.pop(ctx);
                _add(ImageSource.camera);
              }),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: cGreen),
              title: Text(tr('Из галереи', 'Галереядан')),
              onTap: () {
                Navigator.pop(ctx);
                _add(ImageSource.gallery);
              }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Row(children: [
          Text(tr('Фотографии', 'Фотосуреттер'),
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: cInk)),
          const Spacer(),
          Text('${_imgs.length}/$_maxImages',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: cInk3)),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < _imgs.length; i++)
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(_imgs[i],
                    width: 84,
                    height: 84,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 84,
                        height: 84,
                        color: cBg,
                        child: const Icon(Icons.broken_image_outlined,
                            color: cInk3))),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: _busy ? null : () => _remove(i),
                  child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration:
                          const BoxDecoration(color: cRed, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 14)),
                ),
              ),
            ]),
          if (_imgs.length < _maxImages)
            GestureDetector(
              onTap: _busy ? null : _showAddOptions,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                    color: cGreenTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cGreen.withValues(alpha: 0.4))),
                child: const Icon(Icons.add_a_photo_outlined,
                    color: cGreen, size: 26),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(color: cGreen),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(tr('Квадрат 1:1 · максимум 4 фото', '1:1 шаршы · ең көбі 4 фото'),
              style: TextStyle(fontSize: 12, color: cInk3)),
        ),
      ]),
    );
  }
}

// (Ескі авто-центр кесу ImageCropScreen-ге көшті — қолданушы кадрды өзі таңдайды.)
