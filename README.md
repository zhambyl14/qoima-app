<div align="center">

# Qoima App

![Version](https://img.shields.io/badge/version-1.0.0-brightgreen?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue?style=flat-square&logo=flutter)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=flat-square&logo=dart&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-enabled-FFCA28?style=flat-square&logo=firebase&logoColor=black)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

**Киім дүкені мен қойма есебіне арналған мобильді маркетплейс платформасы**

*Sellers · Clients · Warehouse · Analytics · Marketplace*

</div>

---

## Жоба туралы

**Qoima** — киім және аяқ киім сататын дүкендерге арналған кешенді B2C мобильді платформа. Жүйе бір уақытта бірнеше рөлді қолдайды: **superadmin**, **admin (дүкен иесі)**, **seller (сатушы)**, **courier (курьер)**, **client (сатып алушы)** және **guest (қонақ)**. Firebase негізіндегі нақты уақыттағы деректер синхронизациясы арқылы дүкен иесі қойманы, тапсырыстарды, аналитиканы және маркетплейс профилін бір қолданбадан басқарады.

---

## Технологиялық стек

| Технология | Рөлі |
|---|---|
| ![Flutter](https://img.shields.io/badge/-Flutter-02569B?logo=flutter&logoColor=white&style=flat-square) | Кросс-платформалы UI |
| ![Dart](https://img.shields.io/badge/-Dart-0175C2?logo=dart&logoColor=white&style=flat-square) | Бағдарламалау тілі |
| ![Firebase Auth](https://img.shields.io/badge/-Firebase_Auth-FFCA28?logo=firebase&logoColor=black&style=flat-square) | Аутентификация |
| ![Firestore](https://img.shields.io/badge/-Cloud_Firestore-FFCA28?logo=firebase&logoColor=black&style=flat-square) | NoSQL дерекқор |
| ![Cloudinary](https://img.shields.io/badge/-Cloudinary-3448C5?logo=cloudinary&logoColor=white&style=flat-square) | Сурет хостинг |
| ![Provider](https://img.shields.io/badge/-Provider-02569B?logo=flutter&logoColor=white&style=flat-square) | State management |

**Негізгі пакеттер:** `provider` · `cloud_firestore` · `firebase_auth` · `fl_chart` · `pdf` · `printing` · `qr_flutter` · `image_picker` · `shimmer` · `google_fonts`

---

## Негізгі мүмкіндіктер

### Аутентификация және рөлдер
- Клиент тіркелуі — телефон + email + пароль жүйесі
- Seller/Admin — email + пароль
- Реактивті Auth Gate — Provider арқылы автоматты навигация
- Email верификациясы және парольді қалпына келтіру

### Дүкен иесі (Admin) панелі
- Қойма басқару: бірнеше қойма, тауар қалдықтары, партиялар (batch)
- 8 категориялы тауар каталогы: Аяқ киім, Футболкалар, Сыртқы киім, Бас киім, Шалбар, Көйлек, Аксессуарлар, Спорт
- Сатылым, қайтару және баланс жүйесі (PDF чек + QR)
- Жеңілдік және промо-код жүйесі
- Онлайн тапсырыстарды өңдеу
- Маркетплейсте дүкен ашу — модерациялы заявка жүйесі

### Клиент тәжірибесі
- Каталог шолу, іздеу, сүзгі (категория / мақсатты топ / қала)
- Себет және тапсырыс беру
- Тапсырыс тарихы мен қайтару сұраулары
- Таңдаулылар тізімі
- Бронь (резерв) функциясы

### Superadmin
- Маркетплейс дүкен заявкаларын бекіту / қабылдамау
- Дүкен деректерін өзгерту сұраулары (diff экраны)
- Дүкендерді блоктау / блоктан шығару
- Баннер басқару

### Аналитика мен есептер
- `fl_chart` негізіндегі сатылым графиктері
- PDF форматындағы чектер мен есептер (`pdf` + `printing`)
- Денормализацияланған счётчиктер арқылы жылдам статистика

### Курьер
- Жеткізу тапсырмаларының тізімі мен күйін жаңарту

---

## Орнату нұсқаулығы

### Алғышарттар

- [Flutter SDK](https://flutter.dev/docs/get-started/install) >= 3.0.0
- [Dart SDK](https://dart.dev/get-dart) >= 3.0.0
- Firebase жобасы (Firestore, Authentication қосылған)
- Android Studio / VS Code

### 1. Репозиторийді клондау

```bash
git clone https://github.com/<your-username>/qoima.git
cd qoima
```

### 2. Тәуелділіктерді орнату

```bash
flutter pub get
```

### 3. Firebase конфигурациясы

Firebase консолінен жүктеп алынған файлдарды орналастырыңыз:

```
android/app/google-services.json    # Android үшін
ios/Runner/GoogleService-Info.plist  # iOS үшін
lib/firebase_options.dart            # FlutterFire CLI генерациясы
```

> **Назар аударыңыз:** Бұл файлдарды `.gitignore`-ға қосыңыз (төменде қараңыз).

### 4. Қолданбаны іске қосу

```bash
flutter run
```

### 5. Release build (Android)

```bash
flutter build apk --release
# немесе App Bundle үшін:
flutter build appbundle --release
```

---

## Security

> **МАҢЫЗДЫ ЕСКЕРТУ**

Жобада Firebase конфигурация файлдары мен басқа құпия деректер бар. Оларды **ешқашан** Git тарихына жүктемеңіз.

Келесі файлдар `.gitignore` ішінде болуы **міндетті**:

```gitignore
# Firebase — NEVER commit these
google-services.json
GoogleService-Info.plist
lib/firebase_options.dart

# Environment variables
.env
.env.local
*.env

# Signing keys
*.keystore
*.jks
key.properties
```

Егер осы файлдардың бірі кездейсоқ `git add` болып кетсе, Git кэшінен жойыңыз:

```bash
git rm --cached android/app/google-services.json
git commit -m "fix: remove sensitive file from tracking"
```

Содан кейін Firebase Console арқылы барлық API кілттерін ауыстырыңыз.

---

## Commit стилі — Semantic Commits

Бұл жоба **Semantic Commits** жүйесін қолданады. Барлық commit-тер келесі форматта жазылуы тиіс:

```
<type>(<scope>): <қысқаша сипаттама>
```

### Типтер

| Тип | Қашан қолданылады |
|---|---|
| `feat` | Жаңа мүмкіндік қосқанда |
| `fix` | Қатені түзеткенде |
| `docs` | Тек құжаттама өзгерткенде |
| `refactor` | Логиканы өзгертпей кодты қайта жазғанда |
| `style` | Форматтау, нүктелер, бос орындар (логика жоқ) |
| `test` | Тест қосқанда немесе өзгерткенде |
| `chore` | Build жүйесі, тәуелділіктер, CI |
| `perf` | Өнімділікті арттырғанда |

### Мысалдар

```bash
feat(auth): клиент тіркелуіне email верификациясы қосылды
fix(cart): себеттегі қайталанған тауарлар санауы дұрысталды
docs(readme): орнату нұсқаулығы жаңартылды
refactor(orders): PDF генерациясы жеке сервиске шығарылды
chore(deps): flutter pub upgrade
```

---

## Жоба құрылымы

```
lib/
├── core/            # Утилиттер, провайдерлер, конфигурация
├── data/
│   ├── models/      # Dart моделдері (Firestore маппинг)
│   ├── repositories/
│   └── services/    # Auth, Cloudinary
├── theme/           # AppTheme, дизайн токендері
├── ui/
│   ├── admin/       # Дүкен иесі панелі
│   ├── auth/        # Кіру / тіркелу экрандары
│   ├── client/      # Клиент каталогы, тапсырыстар
│   ├── courier/     # Жеткізу экрандары
│   ├── guest/       # Қонақ режимі
│   ├── onboarding/  # Дүкен ашу заявкасы
│   ├── profile/     # Профиль
│   ├── seller/      # Сатушы панелі
│   └── superadmin/  # Модерация
└── main.dart
```

---

## Лицензия

Copyright (c) 2026 Zhambyl Magzhan. Барлық құқықтар қорғалған.

Бұл бағдарламалық жасақтаманы иеленушінің жазбаша рұқсатынсыз көшіруге, таратуға немесе өзгертуге тыйым салынады.

---

<div align="center">
Made with Flutter &amp; Firebase
</div>
