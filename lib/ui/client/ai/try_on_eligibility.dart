import '../../../data/models/product_model.dart';

/// Онлайн киіп көруге жарайтын тауар ма.
///
/// Ереже серверді (supabase/functions/virtual-tryon `garmentCategory`)
/// ДӘЛ қайталайды — екеуін БІР коммитте өзгерту керек:
///  • tshirt, outer — барлық түрлері (жоғарғы киім);
///  • pants — барлығы (төменгі киім);
///  • dress — «Юбка» (төменгі), «Платье/Сарафан/Костюм» (бүтін), өз түрі — auto;
///  • sport — «Спортивный костюм», «Топ», «Леггинсы», «Шорты» (жабдық емес);
///  • ЕШҚАШАН: Детские% аудиториясы, underwear, kids және киім емес категориялар.
bool isTryOnEligible(ProductModel p) {
  if (p.category.startsWith('Детские')) return false;
  if (p.images.isEmpty) return false;
  switch (p.effectiveCategoryKey) {
    case 'tshirt':
    case 'outer':
    case 'pants':
    case 'dress':
      return true;
    case 'sport':
      return const {'Спортивный костюм', 'Топ', 'Леггинсы', 'Шорты'}
          .contains(p.type);
    default:
      return false;
  }
}

/// «Образ құрастыру» үшін тауар жарай ма (ai-stylist `slotsFor`-пен сәйкес).
bool isLookEligible(ProductModel p) {
  switch (p.effectiveCategoryKey) {
    case 'shoes':
    case 'tshirt':
    case 'outer':
    case 'pants':
    case 'dress':
    case 'caps':
    case 'acc':
    case 'jewelry':
      return true;
    case 'sport':
      return const {'Спортивный костюм', 'Топ', 'Леггинсы', 'Шорты'}
          .contains(p.type);
    default:
      return false;
  }
}
