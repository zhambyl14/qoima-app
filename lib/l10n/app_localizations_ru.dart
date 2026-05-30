// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Qoima';

  @override
  String get appVersion => 'Qoima v2.3 — Учёт обуви';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Отмена';

  @override
  String get save => 'Сохранить';

  @override
  String get delete => 'Удалить';

  @override
  String get close => 'Закрыть';

  @override
  String get confirm => 'Подтвердить';

  @override
  String get back => 'Назад';

  @override
  String get add => 'Добавить';

  @override
  String get edit => 'Изменить';

  @override
  String get loading => 'Загрузка...';

  @override
  String get error => 'Ошибка';

  @override
  String get copy => 'Копировать';

  @override
  String get copied => 'Скопировано';

  @override
  String get yes => 'Да';

  @override
  String get no => 'Нет';

  @override
  String get search => 'Поиск';

  @override
  String get noData => 'Нет данных';

  @override
  String get signIn => 'Войти';

  @override
  String get signOut => 'Выйти';

  @override
  String get signOutConfirmTitle => 'Выйти';

  @override
  String get signOutConfirmBody => 'Вы уверены, что хотите выйти?';

  @override
  String get register => 'Зарегистрироваться';

  @override
  String get email => 'Email';

  @override
  String get password => 'Пароль';

  @override
  String get confirmPassword => 'Подтвердите пароль';

  @override
  String get yourName => 'Ваше имя';

  @override
  String get namePlaceholder => 'Например: Асқар Сейтқали';

  @override
  String get emailPlaceholder => 'example@mail.com';

  @override
  String get passwordPlaceholder => 'Минимум 6 символов';

  @override
  String get confirmPasswordPlaceholder => 'Повторите пароль';

  @override
  String get haveAccount => 'Уже есть аккаунт?';

  @override
  String get noAccount => 'Нет аккаунта?';

  @override
  String get createAccount => 'Создать аккаунт';

  @override
  String get fillDetails => 'Выберите роль и заполните данные';

  @override
  String get chooseRole => 'Выберите роль';

  @override
  String get adminRole => 'Владелец магазина';

  @override
  String get adminRoleSubtitle => 'Полный контроль';

  @override
  String get sellerRole => 'Продавец';

  @override
  String get sellerRoleSubtitle => 'По приглашению';

  @override
  String get sellerRegisterHint =>
      'После регистрации введите бизнес-код владельца магазина.';

  @override
  String get selected => '✓ Выбрано';

  @override
  String get profileTitle => 'Профиль';

  @override
  String get adminBadge => '🏪 Владелец магазина';

  @override
  String get sellerBadge => '🏷️ Продавец';

  @override
  String get businessCode => 'Бизнес-код';

  @override
  String get businessCodeCopied => 'Бизнес-код скопирован';

  @override
  String get sellers => 'Продавцы';

  @override
  String get manageSellers => 'Управление наёмными продавцами';

  @override
  String get warehouses => 'Склады';

  @override
  String get manageWarehouses => 'Управление сетью складов';

  @override
  String get transfers => 'Перемещения';

  @override
  String get transfersSubtitle => 'Перемещение между складами';

  @override
  String get about => 'О приложении';

  @override
  String get language => 'Тіл / Язык';

  @override
  String get selectLanguage => 'Выберите язык';

  @override
  String get kazakh => 'Қазақша';

  @override
  String get russian => 'Русский';

  @override
  String get pendingRequests => 'Ожидающие заявки';

  @override
  String get sellersTitle => 'Продавцы';

  @override
  String get activeSellers => 'Активные';

  @override
  String get pendingTab => 'Ожидают';

  @override
  String get noActiveSellers => 'Нет активных продавцов';

  @override
  String get noPendingRequests => 'Нет ожидающих заявок';

  @override
  String get approve => 'Принять';

  @override
  String get reject => 'Отклонить';

  @override
  String get assignWarehouse => 'Назначить склад';

  @override
  String get removeSeller => 'Исключить из магазина';

  @override
  String get confirmRemoveSeller => 'Исключить продавца из магазина?';

  @override
  String get reassignWarehouse => 'Изменить склад';

  @override
  String get warehousesTitle => 'Склады';

  @override
  String get addWarehouse => 'Добавить склад';

  @override
  String get warehouseName => 'Название склада';

  @override
  String get warehouseAddress => 'Адрес (необязательно)';

  @override
  String get warehouseNote => 'Примечание (необязательно)';

  @override
  String get isMainWarehouse => 'Основной склад';

  @override
  String get deleteWarehouse => 'Удалить склад';

  @override
  String get deleteWarehouseConfirm =>
      'Удалить склад? Товары этого склада потеряют привязку, если не были перемещены.';

  @override
  String get noWarehouses => 'Нет складов';

  @override
  String get noWarehousesHint => 'Добавьте первый склад';

  @override
  String get createFirstWarehouse => 'Создайте первый склад';

  @override
  String get onboardingTitle => 'Добро пожаловать! 🎉';

  @override
  String get onboardingSubtitle => 'Создайте первый склад, чтобы начать работу';

  @override
  String get onboardingCreateWarehouse => 'Создать склад';

  @override
  String pairsCount(int count) {
    return '$count пар';
  }

  @override
  String get analyticsTitle => 'Аналитика';

  @override
  String get stockTitle => 'Склад';

  @override
  String get contactTitle => 'Контакты';

  @override
  String get contactPhone => 'Телефон';

  @override
  String get contactTelegram => 'Telegram';

  @override
  String get productsTitle => 'Товары';

  @override
  String get addProduct => 'Добавить товар';

  @override
  String get productName => 'Название';

  @override
  String get brand => 'Бренд';

  @override
  String get type => 'Тип';

  @override
  String get material => 'Материал';

  @override
  String get category => 'Категория';

  @override
  String get color => 'Цвет';

  @override
  String get allWarehouses => 'Все склады';

  @override
  String get selectWarehouse => 'Выберите склад';

  @override
  String get noProductsInWarehouse => 'В этом складе нет товаров';

  @override
  String get allProductsLabel => 'Все';

  @override
  String get inStockLabel => 'В наличии';

  @override
  String get soldLabel => 'Продано';

  @override
  String get salesTitle => 'Продажи';

  @override
  String get makeSale => 'Оформить продажу';

  @override
  String get selectProduct => 'Выберите товар';

  @override
  String get selectSize => 'Выберите размер';

  @override
  String get quantity => 'Количество';

  @override
  String get price => 'Цена';

  @override
  String get discount => 'Скидка (%)';

  @override
  String get total => 'Итого';

  @override
  String get saleSuccess => 'Продажа успешно завершена!';

  @override
  String get noStock => 'Нет товара на складе';

  @override
  String get transferTitle => 'Перемещение';

  @override
  String get newTransfer => 'Новое перемещение';

  @override
  String get fromWarehouse => 'Откуда';

  @override
  String get toWarehouse => 'Куда';

  @override
  String get selectProduct2 => 'Выберите товар';

  @override
  String get transferSuccess => 'Перемещение успешно выполнено';

  @override
  String get joinTitle => 'Присоединиться к магазину';

  @override
  String get enterBusinessCode => 'Введите бизнес-код';

  @override
  String get businessCodeHint => 'Получите у владельца магазина';

  @override
  String get sendRequest => 'Отправить запрос';

  @override
  String get requestSent =>
      'Запрос отправлен. Ожидайте подтверждения владельца.';

  @override
  String get cancelRequest => 'Отменить запрос';

  @override
  String get waitingApproval => 'Ожидаем подтверждения владельца';

  @override
  String get requestApproved => 'Ваш запрос принят!';

  @override
  String get validationRequired => 'Заполните это поле';

  @override
  String get validationEmail => 'Неверный формат email';

  @override
  String get validationPasswordMin => 'Пароль минимум 6 символов';

  @override
  String get validationPasswordMatch => 'Пароли не совпадают';

  @override
  String get validationNameRequired => 'Введите ваше имя';

  @override
  String get validationEmailRequired => 'Введите email';

  @override
  String get unknownError => 'Неизвестная ошибка. Попробуйте снова.';

  @override
  String get validationPasswordRequired => 'Введите пароль';

  @override
  String get validationCodeRequired => 'Введите полный 6-значный код';

  @override
  String get businessCodeSubtitle =>
      'Введите 6-значный бизнес-код от владельца магазина';

  @override
  String get requestSentBody =>
      'Ваш запрос отправлен. После одобрения владельца вы войдёте автоматически.';

  @override
  String get history => 'История';

  @override
  String get selectMonth => 'Выберите месяц';

  @override
  String get apply => 'Применить';

  @override
  String get noSalesThisMonth => 'В этом месяце продаж нет';

  @override
  String get operations => 'Операции';

  @override
  String get productDeleted => 'Товар удалён';

  @override
  String get overviewSub => 'Общий обзор';

  @override
  String get makeSaleHint => 'Продавайте';

  @override
  String get sortBy => 'Сортировка';

  @override
  String get sortAZ => 'По алфавиту А–Я';

  @override
  String get sortZA => 'По алфавиту Я–А';

  @override
  String get sortManyStock => 'Много остатков';

  @override
  String get sortFewStock => 'Мало остатков';

  @override
  String get searchHint => 'Поиск...';

  @override
  String get manageWarehouseSubtitle => 'Управление складом';

  @override
  String get inStockSubtitle => 'Товары в наличии';

  @override
  String get financialDashboard => 'Финансовый дашборд';

  @override
  String get generalTab => 'Общее';

  @override
  String get sellersTab => 'Продавцы';

  @override
  String get warehouseTab => 'По складам';

  @override
  String get monthRevenue => 'Выручка за месяц';

  @override
  String get costPrice => 'Себестоимость';

  @override
  String get netProfit => 'Чистая прибыль';

  @override
  String get income => 'доход';

  @override
  String get lossLabel => 'убыток';

  @override
  String get soldPairsMonth => 'Продано за месяц';

  @override
  String get arrivedPairsMonth => 'Поступило за месяц';

  @override
  String get topSalesTitle => '🔥 Топ продаж';

  @override
  String get fastSalesTitle => '⚡ Хиты — быстрый оборот';

  @override
  String get fastSalesSub => 'Распроданы быстрее всего';

  @override
  String get staleProductsTitle => '⏳ Залежавшийся товар';

  @override
  String get staleProductsSub => 'Более 30 дней на складе';

  @override
  String get popularSizesTitle => '👟 Популярные размеры';

  @override
  String get noFastSalesData => 'Нет данных о быстрых продажах';

  @override
  String get noStaleProductsMsg => 'Залежавшихся товаров нет 🎉';

  @override
  String get productDeletedShort => 'Удалён';

  @override
  String get purchasePrice => 'Закупочная цена';

  @override
  String get sizeLabel => 'Размер';

  @override
  String get pairsUnit => 'пар';

  @override
  String get noSalesThisMonthSimple => 'В этом месяце продаж нет';

  @override
  String get ranking => 'Рейтинг';

  @override
  String get dailyActivity => 'Активность по дням';

  @override
  String get warehouseRanking => 'Рейтинг складов';

  @override
  String get activeWarehouses => 'Активных складов';

  @override
  String get totalRevenueStat => 'Общая выручка';

  @override
  String get warehouseSuffix => 'склад';

  @override
  String get revenueSuffix => 'Выручка';

  @override
  String get salesSuffix => 'Продаж';

  @override
  String get pairsSuffix => 'Пар';

  @override
  String get cartTitle => 'Себет';

  @override
  String get clearCart => 'Себетті тазалау';

  @override
  String get clearCartConfirm => 'Барлық тауарды себеттен алып тастайсыз ба?';

  @override
  String get cartClear => 'Тазалау';

  @override
  String get cartEmpty => 'Себет бос';

  @override
  String get pickupMethod => 'Алу тәсілі';

  @override
  String get smartReservationTitle => 'Смарт-Бронь';

  @override
  String get smartReservationDesc =>
      '1 сағатқа брондаңыз, дүкенде киіп көріңіз';

  @override
  String get smartReservationBadge => '10% депозит';

  @override
  String get clickCollectTitle => 'Click & Collect';

  @override
  String get clickCollectDesc => 'Онлайн төлеп, қоймадан алыңыз';

  @override
  String get clickCollectBadge => '100% онлайн';

  @override
  String get deliveryTitle => 'Жеткізу';

  @override
  String get deliveryDesc => 'Мекенжай көрсетіп, курьермен алыңыз';

  @override
  String get enterDeliveryAddress => 'Жеткізу мекенжайын енгізіңіз';

  @override
  String get deliveryAddressLabel => 'Жеткізу мекенжайы *';

  @override
  String get deliveryAddressPlaceholder => 'Қала, көше, үй, пәтер';

  @override
  String get noteOptional => 'Ескертпе (міндетті емес)';

  @override
  String get additionalInfoHint => 'Қосымша ақпарат...';

  @override
  String itemsUnavailable(String names) {
    return '$names қолжетімсіз (сатылып кетті немесе дүкен жаңартылды). Себеттен алып тастаңыз.';
  }

  @override
  String ordersCreated(int count) {
    return '$count тапсырыс құрылды';
  }

  @override
  String get soldOutUnavailable => 'Сатылып кетті / қолжетімсіз';

  @override
  String get goodsTotal => 'Тауар сомасы';

  @override
  String get totalToPay => 'Төленетін сома';

  @override
  String get payNowDeposit => 'Қазір төлеу (10%)';

  @override
  String get payAtStoreBalance => 'Дүкенде доплата (90%)';

  @override
  String get confirmAndReserve => 'Растап брондау';

  @override
  String get confirmAndPay => 'Растап төлеу';

  @override
  String reserveWithAmount(String amount) {
    return 'Брондау — $amount ₸';
  }

  @override
  String payWithAmount(String amount) {
    return 'Төлеу — $amount ₸';
  }

  @override
  String get pickupAddressLabel => 'Алу мекенжайы';

  @override
  String get reservationTimeframe => 'Бронь мерзімі';

  @override
  String get oneHour => '1 сағат';

  @override
  String sizeQtyLabel(String size, String qty) {
    return 'Өлшем: $size  ×$qty';
  }

  @override
  String get onlineTab => 'Онлайн';

  @override
  String get totalRevenueLabel => 'Жалпы Түсірілке';

  @override
  String offlineOnlineRevSub(String offline, String online) {
    return 'Офлайн: $offline ₸  ·  Онлайн: $online ₸';
  }

  @override
  String get marginLabel => 'Маржа';

  @override
  String get pairsSoldLabel => 'Сатылған жұп';

  @override
  String offlineOnlinePairsSub(String offline, String online) {
    return 'Офлайн: $offline  ·  Онлайн: $online';
  }

  @override
  String get revenueOnline => 'Түсімі (Онлайн)';

  @override
  String get ordersLabel => 'Тапсырыстар';

  @override
  String get cancelledLabel => 'Бас тарту';

  @override
  String get pairsSoldOnline => 'Сатылған жұп (онлайн)';

  @override
  String get dailyActivityOnline => 'Күндік белсенділік (онлайн)';

  @override
  String totalChartAmount(String amount) {
    return 'Жалпы: $amount ₸';
  }

  @override
  String get noStaleItems => 'Жатып қалған тауар жоқ 👍';

  @override
  String get staleItemsTitle => 'Жатып қалған тауар (30+ күн)';

  @override
  String get topThreeSales => 'Топ-3 сатылымдар';

  @override
  String get noSalesLabel => 'Сатылым жоқ';

  @override
  String topOneSeller(String name) {
    return '🥇 Топ-1: $name';
  }

  @override
  String sellerSalesCount(int count, int pairs) {
    return '$count сат · $pairs жұп';
  }

  @override
  String get ordersTitle => 'Тапсырыстар';

  @override
  String get noPhoneNumber => 'Телефон нөмірі жоқ';

  @override
  String get noOrders => 'Тапсырыс жоқ';

  @override
  String get statusReserved => 'Брондалды';

  @override
  String get statusPending => 'Күтуде';

  @override
  String get statusCompleted => 'Аяқталды';

  @override
  String get statusCancelled => 'Бас тартылды';

  @override
  String get goodsAmount => 'Тауар сомасы';

  @override
  String get paidDeposit => 'Төленген депозит';

  @override
  String get remainsAtStore => 'Дүкенде қалды';

  @override
  String get paidLabel => 'Төленді';

  @override
  String get showQrToSeller => 'Сатушыға осы QR кодты көрсетіңіз';

  @override
  String get showQrToStore => 'Дүкенге осы QR кодты көрсетіңіз';

  @override
  String get onlineOrdersTitle => 'Онлайн тапсырыстар';

  @override
  String get enterOrderCode => 'Тапсырыс кодын енгізіңіз...';

  @override
  String get findButton => 'Іздеу';

  @override
  String get invalidCodeOrNotFound => 'Код қате немесе тапсырыс табылмады';

  @override
  String get orderNotForWarehouse =>
      'Бұл тапсырыс сіздің қоймаңызға тиесілі емес';

  @override
  String get orderNotFoundLabel => 'Тапсырыс табылмады';

  @override
  String allWithCount(int count) {
    return 'Барлығы $count';
  }

  @override
  String activeWithCount(int count) {
    return 'Белсенді $count';
  }

  @override
  String completedWithCount(int count) {
    return 'Аяқталды $count';
  }

  @override
  String cancelledWithCount(int count) {
    return 'Бас тартылды $count';
  }

  @override
  String get orderFoundLabel => 'Тапсырыс табылды';

  @override
  String get noActiveOrders => 'Белсенді тапсырыс жоқ';

  @override
  String get noCompletedOrders => 'Аяқталған тапсырыс жоқ';

  @override
  String get noCancelledOrders => 'Бас тартылған тапсырыс жоқ';

  @override
  String get noOrdersLabel => 'Тапсырыс жоқ';

  @override
  String get nameNotSpecified => 'Аты көрсетілмеген';

  @override
  String get phoneCopied => 'Телефон көшірілді';

  @override
  String get depositPaidBadge => 'Депозит төленді (10%)';

  @override
  String get payAtStoreLabel => 'Дүкенде доплата';

  @override
  String get totalPaidLabel => 'Барлығы төленді';

  @override
  String get clientPaidFull => 'Клиент толық сомасын төледі ме?';

  @override
  String get markAsDeliveredQ => 'Жеткізілді деп белгілеу?';

  @override
  String get markAsGivenQ => 'Берілді деп белгілеу?';

  @override
  String get confirmationTitle => 'Растау';

  @override
  String get yesConfirmBtn => 'Иә, растаймын';

  @override
  String get cancelOrderDialog => 'Тапсырысты болдырмау';

  @override
  String get cancelOrderMsg => 'Тапсырыс болдырылмайды, тауар қоймаға оралады.';

  @override
  String get cancelOrderBtn => 'Тапсырысты болдырмау';

  @override
  String get fullPaymentLabel => 'Толық төлем';

  @override
  String get deliveredLabel => 'Жеткізілді';

  @override
  String get givenLabel => 'Тауар берілді';

  @override
  String get cancelBtn => 'Болдырмау';

  @override
  String get smartResBadgeUpper => 'СМАРТ-БРОНЬ';

  @override
  String get clickCollectUpper => 'CLICK & COLLECT';

  @override
  String get deliveryUpper => 'ЖЕТКІЗУ';

  @override
  String get storeTitle => 'Дүкен';

  @override
  String get productSearchHint => 'Тауар іздеу...';

  @override
  String get noActiveStores => 'Белсенді дүкен жоқ';

  @override
  String searchNotFoundMsg(String query) {
    return '«$query» табылмады';
  }

  @override
  String get noProductsLabel => 'Тауар жоқ';

  @override
  String get outOfStock => 'Қолда жоқ';

  @override
  String addedToCartMsg(String name) {
    return '$name себетке қосылды';
  }

  @override
  String get addToCartBtn => 'Себетке';
}
