/// Ақылды көптілді іздеу: қазақ/орыс кириллицасы ↔ латын транслитерациясы
/// және регистрге тәуелсіздік.
///
/// Транслитерация бір бағытта (кирилл→латын) жасалады, бірақ [matches] сұраныс
/// пен мәтінді ЕКЕУІН де нормалап салыстырғандықтан, латынша терілген сұраныс
/// кириллица мәтінмен (және керісінше) сәйкес келеді.
class SearchHelper {
  // Кириллица → латын транслитерация картасы (қазақ әріптерін қоса).
  static const Map<String, String> _cyrToLat = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo',
    'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm',
    'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
    'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
    'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
    // Қазақ әріптері
    'ә': 'a', 'і': 'i', 'ң': 'n', 'ғ': 'g', 'ү': 'u', 'ұ': 'u',
    'қ': 'k', 'ө': 'o', 'һ': 'h',
  };

  /// Жолды нормалайды: кіші әріп + транслитерация (кирилл→латын).
  static String normalize(String s) {
    final lower = s.toLowerCase().trim();
    final buf = StringBuffer();
    for (int i = 0; i < lower.length; i++) {
      final ch = lower[i];
      buf.write(_cyrToLat[ch] ?? ch);
    }
    return buf.toString();
  }

  /// [text] [query]-ге сәйкес келе ме (ақылды салыстыру):
  /// 1. Регистрге тәуелсіз тікелей substring
  /// 2. Екеуі де латынға нормаланған substring
  /// 3. Нормаланған сұраныс ↔ түпнұсқа мәтін (және керісінше)
  static bool matches(String text, String query) {
    if (query.isEmpty) return true;

    final qLower = query.toLowerCase().trim();
    final tLower = text.toLowerCase().trim();

    // 1. Тікелей регистрсіз сәйкестік
    if (tLower.contains(qLower)) return true;

    // 2. Екеуі де латынға нормаланған
    final qNorm = normalize(query);
    final tNorm = normalize(text);
    if (tNorm.contains(qNorm)) return true;

    // 3. Нормаланған сұраныс, түпнұсқа мәтін
    if (tLower.contains(qNorm)) return true;

    // 4. Түпнұсқа сұраныс, нормаланған мәтін
    if (tNorm.contains(qLower)) return true;

    return false;
  }

  /// Балл: жоғары = жақсырақ сәйкестік (нәтижелерді сұрыптауға).
  static int score(String text, String query) {
    final tLower = text.toLowerCase();
    final qLower = query.toLowerCase();

    // Сұраныстан басталса = ең жоғары балл
    if (tLower.startsWith(qLower)) return 3;
    // Нормаланғаны басталса
    if (normalize(text).startsWith(normalize(query))) return 2;
    // Тек қамтыса = төмен балл
    if (matches(text, query)) return 1;
    return 0;
  }
}
