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
}
