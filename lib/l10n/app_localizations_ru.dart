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
  String get cartTitle => 'Корзина';

  @override
  String get clearCart => 'Очистить корзину';

  @override
  String get clearCartConfirm => 'Убрать все товары из корзины?';

  @override
  String get cartClear => 'Очистить';

  @override
  String get cartEmpty => 'Корзина пуста';

  @override
  String get pickupMethod => 'Способ получения';

  @override
  String get smartReservationTitle => 'Смарт-Бронь';

  @override
  String get smartReservationDesc =>
      'Забронируйте на 1 час и примерьте в магазине';

  @override
  String get smartReservationBadge => 'Депозит 10%';

  @override
  String get clickCollectTitle => 'Click & Collect';

  @override
  String get clickCollectDesc => 'Оплатите онлайн и заберите со склада';

  @override
  String get clickCollectBadge => '100% онлайн';

  @override
  String get deliveryTitle => 'Доставка';

  @override
  String get deliveryDesc => 'Укажите адрес и получите курьером';

  @override
  String get enterDeliveryAddress => 'Введите адрес доставки';

  @override
  String get deliveryAddressLabel => 'Адрес доставки *';

  @override
  String get deliveryAddressPlaceholder => 'Город, улица, дом, квартира';

  @override
  String get noteOptional => 'Примечание (необязательно)';

  @override
  String get additionalInfoHint => 'Дополнительная информация...';

  @override
  String itemsUnavailable(String names) {
    return '$names недоступны (проданы или магазин обновился). Уберите их из корзины.';
  }

  @override
  String ordersCreated(int count) {
    return 'Создано заказов: $count';
  }

  @override
  String get soldOutUnavailable => 'Продано / недоступно';

  @override
  String get goodsTotal => 'Сумма товаров';

  @override
  String get totalToPay => 'Сумма к оплате';

  @override
  String get payNowDeposit => 'Оплатить сейчас (10%)';

  @override
  String get payAtStoreBalance => 'Доплата в магазине (90%)';

  @override
  String get confirmAndReserve => 'Подтвердить и забронировать';

  @override
  String get confirmAndPay => 'Подтвердить и оплатить';

  @override
  String reserveWithAmount(String amount) {
    return 'Забронировать — $amount ₸';
  }

  @override
  String payWithAmount(String amount) {
    return 'Оплатить — $amount ₸';
  }

  @override
  String get pickupAddressLabel => 'Адрес получения';

  @override
  String get reservationTimeframe => 'Срок брони';

  @override
  String get oneHour => '1 час';

  @override
  String sizeQtyLabel(String size, String qty) {
    return 'Размер: $size  ×$qty';
  }

  @override
  String get onlineTab => 'Онлайн';

  @override
  String get totalRevenueLabel => 'Общая выручка';

  @override
  String offlineOnlineRevSub(String offline, String online) {
    return 'Офлайн: $offline ₸  ·  Онлайн: $online ₸';
  }

  @override
  String get marginLabel => 'Маржа';

  @override
  String get pairsSoldLabel => 'Продано пар';

  @override
  String offlineOnlinePairsSub(String offline, String online) {
    return 'Офлайн: $offline  ·  Онлайн: $online';
  }

  @override
  String get revenueOnline => 'Выручка (Онлайн)';

  @override
  String get ordersLabel => 'Заказы';

  @override
  String get cancelledLabel => 'Отмены';

  @override
  String get pairsSoldOnline => 'Продано пар (онлайн)';

  @override
  String get dailyActivityOnline => 'Дневная активность (онлайн)';

  @override
  String totalChartAmount(String amount) {
    return 'Итого: $amount ₸';
  }

  @override
  String get noStaleItems => 'Залежавшихся товаров нет 👍';

  @override
  String get staleItemsTitle => 'Залежавшийся товар (30+ дней)';

  @override
  String get topThreeSales => 'Топ-3 продаж';

  @override
  String get noSalesLabel => 'Продаж нет';

  @override
  String topOneSeller(String name) {
    return '🥇 Топ-1: $name';
  }

  @override
  String sellerSalesCount(int count, int pairs) {
    return '$count прод · $pairs пар';
  }

  @override
  String get ordersTitle => 'Заказы';

  @override
  String get noPhoneNumber => 'Нет номера телефона';

  @override
  String get noOrders => 'Заказов нет';

  @override
  String get statusReserved => 'Забронирован';

  @override
  String get statusPending => 'В ожидании';

  @override
  String get statusCompleted => 'Завершён';

  @override
  String get statusCancelled => 'Отменён';

  @override
  String get goodsAmount => 'Сумма товаров';

  @override
  String get paidDeposit => 'Оплаченный депозит';

  @override
  String get remainsAtStore => 'Осталось в магазине';

  @override
  String get paidLabel => 'Оплачено';

  @override
  String get showQrToSeller => 'Покажите этот QR-код продавцу';

  @override
  String get showQrToStore => 'Покажите этот QR-код магазину';

  @override
  String get onlineOrdersTitle => 'Онлайн-заказы';

  @override
  String get enterOrderCode => 'Введите код заказа...';

  @override
  String get findButton => 'Найти';

  @override
  String get invalidCodeOrNotFound => 'Неверный код или заказ не найден';

  @override
  String get orderNotForWarehouse => 'Этот заказ не относится к вашему складу';

  @override
  String get orderNotFoundLabel => 'Заказ не найден';

  @override
  String allWithCount(int count) {
    return 'Все $count';
  }

  @override
  String activeWithCount(int count) {
    return 'Активные $count';
  }

  @override
  String completedWithCount(int count) {
    return 'Завершённые $count';
  }

  @override
  String cancelledWithCount(int count) {
    return 'Отменённые $count';
  }

  @override
  String get orderFoundLabel => 'Заказ найден';

  @override
  String get noActiveOrders => 'Активных заказов нет';

  @override
  String get noCompletedOrders => 'Завершённых заказов нет';

  @override
  String get noCancelledOrders => 'Отменённых заказов нет';

  @override
  String get noOrdersLabel => 'Заказов нет';

  @override
  String get nameNotSpecified => 'Имя не указано';

  @override
  String get phoneCopied => 'Телефон скопирован';

  @override
  String get depositPaidBadge => 'Депозит оплачен (10%)';

  @override
  String get payAtStoreLabel => 'Доплата в магазине';

  @override
  String get totalPaidLabel => 'Всего оплачено';

  @override
  String get clientPaidFull => 'Клиент оплатил полную сумму?';

  @override
  String get markAsDeliveredQ => 'Отметить как доставленный?';

  @override
  String get markAsGivenQ => 'Отметить как выданный?';

  @override
  String get confirmationTitle => 'Подтверждение';

  @override
  String get yesConfirmBtn => 'Да, подтверждаю';

  @override
  String get cancelOrderDialog => 'Отменить заказ';

  @override
  String get cancelOrderMsg => 'Заказ будет отменён, товар вернётся на склад.';

  @override
  String get cancelOrderBtn => 'Отменить заказ';

  @override
  String get fullPaymentLabel => 'Полная оплата';

  @override
  String get deliveredLabel => 'Доставлен';

  @override
  String get givenLabel => 'Товар выдан';

  @override
  String get cancelBtn => 'Отмена';

  @override
  String get smartResBadgeUpper => 'СМАРТ-БРОНЬ';

  @override
  String get clickCollectUpper => 'CLICK & COLLECT';

  @override
  String get deliveryUpper => 'ДОСТАВКА';

  @override
  String get storeTitle => 'Магазин';

  @override
  String get productSearchHint => 'Поиск товара...';

  @override
  String get noActiveStores => 'Активных магазинов нет';

  @override
  String searchNotFoundMsg(String query) {
    return '«$query» не найдено';
  }

  @override
  String get noProductsLabel => 'Товаров нет';

  @override
  String get outOfStock => 'Нет в наличии';

  @override
  String addedToCartMsg(String name) {
    return '$name добавлен в корзину';
  }

  @override
  String get addToCartBtn => 'В корзину';

  @override
  String get returnsTitle => 'Возвраты';

  @override
  String get returnTabList => 'Список';

  @override
  String get returnTabAnalytics => 'Аналитика';

  @override
  String get returnStatusRequested => 'Запрос отправлен';

  @override
  String get returnStatusApproved => 'Принято';

  @override
  String get returnStatusReceived => 'Товар получен';

  @override
  String get returnStatusRefunded => 'Деньги возвращены';

  @override
  String get returnStatusRejected => 'Отклонено';

  @override
  String get returnTypeOnline => 'Онлайн';

  @override
  String get returnTypeOffline => 'Офлайн';

  @override
  String get returnReasonSizeNotFit => 'Не подошёл размер';

  @override
  String get returnReasonQualityBad => 'Плохое качество';

  @override
  String get returnReasonNotAsDescribed => 'Не соответствует описанию';

  @override
  String get returnReasonJustDidntLike => 'Не понравился';

  @override
  String get returnReasonOther => 'Другая причина';

  @override
  String get returnPickupSelf => 'Принесу сам';

  @override
  String get returnPickupCourier => 'Курьером';

  @override
  String get returnRefundCard => 'Картой';

  @override
  String get returnRefundCash => 'Наличными';

  @override
  String get returnRefundExchange => 'Обмен';

  @override
  String get returnFilterAll => 'Все';

  @override
  String get returnFilterNew => 'Новые';

  @override
  String get returnFilterPending => 'Ожидает решения';

  @override
  String get returnFilterApproved => 'Принято';

  @override
  String get returnFilterProcessing => 'Обработка';

  @override
  String get returnFilterReceived => 'Ожидает товар';

  @override
  String get returnFilterCompleted => 'Завершено';

  @override
  String get returnFilterRejected => 'Отклонено';

  @override
  String get returnPerSellerTitle => 'По продавцам';

  @override
  String get returnCreateButton => 'Оформить возврат';

  @override
  String get returnCancelRequest => 'Отменить запрос';

  @override
  String get returnApprove => 'Принять';

  @override
  String get returnReject => 'Отклонить';

  @override
  String get returnReceiveTitle => 'Приёмка товара';

  @override
  String get returnConditionOk => 'Пригодный';

  @override
  String get returnConditionBad => 'Не пригодный';

  @override
  String get returnConditionLabel => 'Состояние товара';

  @override
  String get returnRefundTitle => 'Возврат денег';

  @override
  String get returnRefundMethodLabel => 'Способ возврата';

  @override
  String get returnCompleteRefund => 'Завершить возврат';

  @override
  String get returnTimelineStep1 => 'Запрос отправлен';

  @override
  String get returnTimelineStep2 => 'Рассматривается продавцом';

  @override
  String get returnTimelineStep3 => 'Доставьте товар в магазин';

  @override
  String get returnTimelineStep4 => 'Средства возвращены';

  @override
  String get returnAnalyticsTitle => 'Аналитика возвратов';

  @override
  String get returnRate => 'Процент возвратов';

  @override
  String get returnReasonBreakdown => 'По причинам';

  @override
  String get returnTopProducts => 'Топ возвращаемых товаров';

  @override
  String get returnNoReturns => 'Возвратов нет';

  @override
  String get returnNoReturnsHint => 'Нет активных возвратов';

  @override
  String get returnRejectReason => 'Причина отклонения';

  @override
  String get returnEnterRejectReason => 'Укажите причину...';

  @override
  String get returnSellerNote => 'Заметка продавца';

  @override
  String get returnNotesLabel => 'Примечание';

  @override
  String get returnPhotosLabel => 'Фотографии';

  @override
  String get returnClientSection => 'Клиент';

  @override
  String get returnSourceSection => 'Исходный заказ/продажа';

  @override
  String get returnTimelineTitle => 'История статусов';

  @override
  String get returnOfflineFindReceipt => 'Найти чек';

  @override
  String get returnOfflineSelectItems => 'Выбор товаров';

  @override
  String get returnOfflineRefundMethod => 'Способ возврата';

  @override
  String get returnOfflineReceiptHint => 'Номер чека (поиск по ID)';

  @override
  String get returnOfflineQrTodo => 'QR-сканер (запланировано)';

  @override
  String get returnSuccessMsg => 'Запрос на возврат отправлен!';

  @override
  String get returnApproveSuccess => 'Возврат принят';

  @override
  String get returnRejectSuccess => 'Возврат отклонён';

  @override
  String get returnReceiveSuccess => 'Товар принят';

  @override
  String get returnRefundSuccess => 'Возврат завершён!';

  @override
  String get returnStockRestored => 'Товар возвращён на склад';

  @override
  String get returnNoStock => 'Товар не возвращён на склад (не пригоден)';

  @override
  String returnDaysLeft(int days) {
    return '$days дн. осталось';
  }

  @override
  String get returnActiveChip => 'В обработке';

  @override
  String get returnConfirmTitle => 'Подтверждение';

  @override
  String get returnSummaryTitle => 'Итог';

  @override
  String get returnReasonLabel => 'Причина возврата';

  @override
  String get returnPickupLabel => 'Способ доставки';

  @override
  String get returnSelectItemsHint => 'Выберите товары для возврата';

  @override
  String get returnItemsSection => 'Товары';

  @override
  String get returnAmountSection => 'Сумма возврата';
}
