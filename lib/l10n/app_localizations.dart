import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_kk.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('kk'),
    Locale('ru')
  ];

  /// No description provided for @appTitle.
  ///
  /// In kk, this message translates to:
  /// **'Qoima'**
  String get appTitle;

  /// No description provided for @appVersion.
  ///
  /// In kk, this message translates to:
  /// **'Qoima v2.3 — Аяқ киім есебі'**
  String get appVersion;

  /// No description provided for @ok.
  ///
  /// In kk, this message translates to:
  /// **'Жарайды'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In kk, this message translates to:
  /// **'Болдырмау'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In kk, this message translates to:
  /// **'Сақтау'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In kk, this message translates to:
  /// **'Жою'**
  String get delete;

  /// No description provided for @close.
  ///
  /// In kk, this message translates to:
  /// **'Жабу'**
  String get close;

  /// No description provided for @confirm.
  ///
  /// In kk, this message translates to:
  /// **'Растау'**
  String get confirm;

  /// No description provided for @back.
  ///
  /// In kk, this message translates to:
  /// **'Артқа'**
  String get back;

  /// No description provided for @add.
  ///
  /// In kk, this message translates to:
  /// **'Қосу'**
  String get add;

  /// No description provided for @edit.
  ///
  /// In kk, this message translates to:
  /// **'Өзгерту'**
  String get edit;

  /// No description provided for @loading.
  ///
  /// In kk, this message translates to:
  /// **'Жүктелуде...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In kk, this message translates to:
  /// **'Қате'**
  String get error;

  /// No description provided for @copy.
  ///
  /// In kk, this message translates to:
  /// **'Көшіру'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In kk, this message translates to:
  /// **'Көшірілді'**
  String get copied;

  /// No description provided for @yes.
  ///
  /// In kk, this message translates to:
  /// **'Иә'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In kk, this message translates to:
  /// **'Жоқ'**
  String get no;

  /// No description provided for @search.
  ///
  /// In kk, this message translates to:
  /// **'Іздеу'**
  String get search;

  /// No description provided for @noData.
  ///
  /// In kk, this message translates to:
  /// **'Деректер жоқ'**
  String get noData;

  /// No description provided for @signIn.
  ///
  /// In kk, this message translates to:
  /// **'Кіру'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In kk, this message translates to:
  /// **'Шығу'**
  String get signOut;

  /// No description provided for @signOutConfirmTitle.
  ///
  /// In kk, this message translates to:
  /// **'Шығу'**
  String get signOutConfirmTitle;

  /// No description provided for @signOutConfirmBody.
  ///
  /// In kk, this message translates to:
  /// **'Шықпақшысыз ба?'**
  String get signOutConfirmBody;

  /// No description provided for @register.
  ///
  /// In kk, this message translates to:
  /// **'Тіркелу'**
  String get register;

  /// No description provided for @email.
  ///
  /// In kk, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In kk, this message translates to:
  /// **'Пароль'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In kk, this message translates to:
  /// **'Парольді растаңыз'**
  String get confirmPassword;

  /// No description provided for @yourName.
  ///
  /// In kk, this message translates to:
  /// **'Атыңыз'**
  String get yourName;

  /// No description provided for @namePlaceholder.
  ///
  /// In kk, this message translates to:
  /// **'Мысалы: Асқар Сейтқали'**
  String get namePlaceholder;

  /// No description provided for @emailPlaceholder.
  ///
  /// In kk, this message translates to:
  /// **'example@mail.com'**
  String get emailPlaceholder;

  /// No description provided for @passwordPlaceholder.
  ///
  /// In kk, this message translates to:
  /// **'Минимум 6 таңба'**
  String get passwordPlaceholder;

  /// No description provided for @confirmPasswordPlaceholder.
  ///
  /// In kk, this message translates to:
  /// **'Парольді қайталаңыз'**
  String get confirmPasswordPlaceholder;

  /// No description provided for @haveAccount.
  ///
  /// In kk, this message translates to:
  /// **'Аккаунт бар ма?'**
  String get haveAccount;

  /// No description provided for @noAccount.
  ///
  /// In kk, this message translates to:
  /// **'Аккаунт жоқ па?'**
  String get noAccount;

  /// No description provided for @createAccount.
  ///
  /// In kk, this message translates to:
  /// **'Аккаунт жасау'**
  String get createAccount;

  /// No description provided for @fillDetails.
  ///
  /// In kk, this message translates to:
  /// **'Рөліңізді таңдап, деректерді толтырыңыз'**
  String get fillDetails;

  /// No description provided for @chooseRole.
  ///
  /// In kk, this message translates to:
  /// **'Рөл таңдаңыз'**
  String get chooseRole;

  /// No description provided for @adminRole.
  ///
  /// In kk, this message translates to:
  /// **'Дүкен иесі'**
  String get adminRole;

  /// No description provided for @adminRoleSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Толық бақылау'**
  String get adminRoleSubtitle;

  /// No description provided for @sellerRole.
  ///
  /// In kk, this message translates to:
  /// **'Сатушы'**
  String get sellerRole;

  /// No description provided for @sellerRoleSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Шақырылған'**
  String get sellerRoleSubtitle;

  /// No description provided for @sellerRegisterHint.
  ///
  /// In kk, this message translates to:
  /// **'Тіркелгеннен кейін дүкен иесінің бизнес-кодын енгізесіз.'**
  String get sellerRegisterHint;

  /// No description provided for @selected.
  ///
  /// In kk, this message translates to:
  /// **'✓ Таңдалды'**
  String get selected;

  /// No description provided for @profileTitle.
  ///
  /// In kk, this message translates to:
  /// **'Профиль'**
  String get profileTitle;

  /// No description provided for @adminBadge.
  ///
  /// In kk, this message translates to:
  /// **'🏪 Дүкен иесі'**
  String get adminBadge;

  /// No description provided for @sellerBadge.
  ///
  /// In kk, this message translates to:
  /// **'🏷️ Сатушы'**
  String get sellerBadge;

  /// No description provided for @businessCode.
  ///
  /// In kk, this message translates to:
  /// **'Бизнес-код'**
  String get businessCode;

  /// No description provided for @businessCodeCopied.
  ///
  /// In kk, this message translates to:
  /// **'Бизнес-код көшірілді'**
  String get businessCodeCopied;

  /// No description provided for @sellers.
  ///
  /// In kk, this message translates to:
  /// **'Сатушылар'**
  String get sellers;

  /// No description provided for @manageSellers.
  ///
  /// In kk, this message translates to:
  /// **'Жалданбал сатушыларды басқару'**
  String get manageSellers;

  /// No description provided for @warehouses.
  ///
  /// In kk, this message translates to:
  /// **'Қоймалар'**
  String get warehouses;

  /// No description provided for @manageWarehouses.
  ///
  /// In kk, this message translates to:
  /// **'Қойма желісін басқару'**
  String get manageWarehouses;

  /// No description provided for @transfers.
  ///
  /// In kk, this message translates to:
  /// **'Перемещениялар'**
  String get transfers;

  /// No description provided for @transfersSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Қоймалар арасындағы тасымал'**
  String get transfersSubtitle;

  /// No description provided for @about.
  ///
  /// In kk, this message translates to:
  /// **'Қолданба туралы'**
  String get about;

  /// No description provided for @language.
  ///
  /// In kk, this message translates to:
  /// **'Тіл / Язык'**
  String get language;

  /// No description provided for @selectLanguage.
  ///
  /// In kk, this message translates to:
  /// **'Тілді таңдаңыз'**
  String get selectLanguage;

  /// No description provided for @kazakh.
  ///
  /// In kk, this message translates to:
  /// **'Қазақша'**
  String get kazakh;

  /// No description provided for @russian.
  ///
  /// In kk, this message translates to:
  /// **'Русский'**
  String get russian;

  /// No description provided for @pendingRequests.
  ///
  /// In kk, this message translates to:
  /// **'Күтудегі өтінімдер'**
  String get pendingRequests;

  /// No description provided for @sellersTitle.
  ///
  /// In kk, this message translates to:
  /// **'Сатушылар'**
  String get sellersTitle;

  /// No description provided for @activeSellers.
  ///
  /// In kk, this message translates to:
  /// **'Белсенді'**
  String get activeSellers;

  /// No description provided for @pendingTab.
  ///
  /// In kk, this message translates to:
  /// **'Күтуде'**
  String get pendingTab;

  /// No description provided for @noActiveSellers.
  ///
  /// In kk, this message translates to:
  /// **'Белсенді сатушы жоқ'**
  String get noActiveSellers;

  /// No description provided for @noPendingRequests.
  ///
  /// In kk, this message translates to:
  /// **'Күтудегі өтінім жоқ'**
  String get noPendingRequests;

  /// No description provided for @approve.
  ///
  /// In kk, this message translates to:
  /// **'Қабылдау'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In kk, this message translates to:
  /// **'Бас тарту'**
  String get reject;

  /// No description provided for @assignWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Қойма тағайындау'**
  String get assignWarehouse;

  /// No description provided for @removeSeller.
  ///
  /// In kk, this message translates to:
  /// **'Дүкеннен шығару'**
  String get removeSeller;

  /// No description provided for @confirmRemoveSeller.
  ///
  /// In kk, this message translates to:
  /// **'Сатушыны дүкеннен шығарасыз ба?'**
  String get confirmRemoveSeller;

  /// No description provided for @reassignWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Қойманы өзгерту'**
  String get reassignWarehouse;

  /// No description provided for @warehousesTitle.
  ///
  /// In kk, this message translates to:
  /// **'Қоймалар'**
  String get warehousesTitle;

  /// No description provided for @addWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Қойма қосу'**
  String get addWarehouse;

  /// No description provided for @warehouseName.
  ///
  /// In kk, this message translates to:
  /// **'Қойма атауы'**
  String get warehouseName;

  /// No description provided for @warehouseAddress.
  ///
  /// In kk, this message translates to:
  /// **'Мекенжай (міндетті емес)'**
  String get warehouseAddress;

  /// No description provided for @warehouseNote.
  ///
  /// In kk, this message translates to:
  /// **'Ескертпе (міндетті емес)'**
  String get warehouseNote;

  /// No description provided for @isMainWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Негізгі қойма'**
  String get isMainWarehouse;

  /// No description provided for @deleteWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Қойманы жою'**
  String get deleteWarehouse;

  /// No description provided for @deleteWarehouseConfirm.
  ///
  /// In kk, this message translates to:
  /// **'Қойманы жойғыңыз келе ме? Бұл қоймадағы барлық өнімдер тасымалданбаған болса байланысын жоғалтады.'**
  String get deleteWarehouseConfirm;

  /// No description provided for @noWarehouses.
  ///
  /// In kk, this message translates to:
  /// **'Қойма жоқ'**
  String get noWarehouses;

  /// No description provided for @noWarehousesHint.
  ///
  /// In kk, this message translates to:
  /// **'Алғашқы қоймаңызды қосыңыз'**
  String get noWarehousesHint;

  /// No description provided for @createFirstWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Алғашқы қойма жасаңыз'**
  String get createFirstWarehouse;

  /// No description provided for @onboardingTitle.
  ///
  /// In kk, this message translates to:
  /// **'Қошқелдіңіз! 🎉'**
  String get onboardingTitle;

  /// No description provided for @onboardingSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Бастау үшін алғашқы қоймаңызды жасаңыз'**
  String get onboardingSubtitle;

  /// No description provided for @onboardingCreateWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Қойма жасау'**
  String get onboardingCreateWarehouse;

  /// No description provided for @pairsCount.
  ///
  /// In kk, this message translates to:
  /// **'{count} жұп'**
  String pairsCount(int count);

  /// No description provided for @analyticsTitle.
  ///
  /// In kk, this message translates to:
  /// **'Аналитика'**
  String get analyticsTitle;

  /// No description provided for @stockTitle.
  ///
  /// In kk, this message translates to:
  /// **'Қойма'**
  String get stockTitle;

  /// No description provided for @contactTitle.
  ///
  /// In kk, this message translates to:
  /// **'Байланыс'**
  String get contactTitle;

  /// No description provided for @contactPhone.
  ///
  /// In kk, this message translates to:
  /// **'Телефон'**
  String get contactPhone;

  /// No description provided for @contactTelegram.
  ///
  /// In kk, this message translates to:
  /// **'Telegram'**
  String get contactTelegram;

  /// No description provided for @productsTitle.
  ///
  /// In kk, this message translates to:
  /// **'Өнімдер'**
  String get productsTitle;

  /// No description provided for @addProduct.
  ///
  /// In kk, this message translates to:
  /// **'Өнім қосу'**
  String get addProduct;

  /// No description provided for @productName.
  ///
  /// In kk, this message translates to:
  /// **'Атауы'**
  String get productName;

  /// No description provided for @brand.
  ///
  /// In kk, this message translates to:
  /// **'Бренд'**
  String get brand;

  /// No description provided for @type.
  ///
  /// In kk, this message translates to:
  /// **'Түрі'**
  String get type;

  /// No description provided for @material.
  ///
  /// In kk, this message translates to:
  /// **'Материал'**
  String get material;

  /// No description provided for @category.
  ///
  /// In kk, this message translates to:
  /// **'Категория'**
  String get category;

  /// No description provided for @color.
  ///
  /// In kk, this message translates to:
  /// **'Түс'**
  String get color;

  /// No description provided for @allWarehouses.
  ///
  /// In kk, this message translates to:
  /// **'Барлық қоймалар'**
  String get allWarehouses;

  /// No description provided for @selectWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Қойманы таңдаңыз'**
  String get selectWarehouse;

  /// No description provided for @noProductsInWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Бұл қоймада өнім жоқ'**
  String get noProductsInWarehouse;

  /// No description provided for @allProductsLabel.
  ///
  /// In kk, this message translates to:
  /// **'Барлығы'**
  String get allProductsLabel;

  /// No description provided for @inStockLabel.
  ///
  /// In kk, this message translates to:
  /// **'Қолда бар'**
  String get inStockLabel;

  /// No description provided for @soldLabel.
  ///
  /// In kk, this message translates to:
  /// **'Сатылды'**
  String get soldLabel;

  /// No description provided for @salesTitle.
  ///
  /// In kk, this message translates to:
  /// **'Сатулар'**
  String get salesTitle;

  /// No description provided for @makeSale.
  ///
  /// In kk, this message translates to:
  /// **'Сату жасау'**
  String get makeSale;

  /// No description provided for @selectProduct.
  ///
  /// In kk, this message translates to:
  /// **'Өнімді таңдаңыз'**
  String get selectProduct;

  /// No description provided for @selectSize.
  ///
  /// In kk, this message translates to:
  /// **'Размер таңдаңыз'**
  String get selectSize;

  /// No description provided for @quantity.
  ///
  /// In kk, this message translates to:
  /// **'Саны'**
  String get quantity;

  /// No description provided for @price.
  ///
  /// In kk, this message translates to:
  /// **'Бағасы'**
  String get price;

  /// No description provided for @discount.
  ///
  /// In kk, this message translates to:
  /// **'Жеңілдік (%)'**
  String get discount;

  /// No description provided for @total.
  ///
  /// In kk, this message translates to:
  /// **'Жиыны'**
  String get total;

  /// No description provided for @saleSuccess.
  ///
  /// In kk, this message translates to:
  /// **'Сату сәтті аяқталды!'**
  String get saleSuccess;

  /// No description provided for @noStock.
  ///
  /// In kk, this message translates to:
  /// **'Қоймада тауар жоқ'**
  String get noStock;

  /// No description provided for @transferTitle.
  ///
  /// In kk, this message translates to:
  /// **'Тасымал'**
  String get transferTitle;

  /// No description provided for @newTransfer.
  ///
  /// In kk, this message translates to:
  /// **'Жаңа тасымал'**
  String get newTransfer;

  /// No description provided for @fromWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Қайдан'**
  String get fromWarehouse;

  /// No description provided for @toWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Қайда'**
  String get toWarehouse;

  /// No description provided for @selectProduct2.
  ///
  /// In kk, this message translates to:
  /// **'Өнімді таңдаңыз'**
  String get selectProduct2;

  /// No description provided for @transferSuccess.
  ///
  /// In kk, this message translates to:
  /// **'Тасымал сәтті орындалды'**
  String get transferSuccess;

  /// No description provided for @joinTitle.
  ///
  /// In kk, this message translates to:
  /// **'Дүкенге қосылу'**
  String get joinTitle;

  /// No description provided for @enterBusinessCode.
  ///
  /// In kk, this message translates to:
  /// **'Бизнес-кодты енгізіңіз'**
  String get enterBusinessCode;

  /// No description provided for @businessCodeHint.
  ///
  /// In kk, this message translates to:
  /// **'Дүкен иесінен алыңыз'**
  String get businessCodeHint;

  /// No description provided for @sendRequest.
  ///
  /// In kk, this message translates to:
  /// **'Сұрау жіберу'**
  String get sendRequest;

  /// No description provided for @requestSent.
  ///
  /// In kk, this message translates to:
  /// **'Сұрау жіберілді. Дүкен иесі растауын күтіңіз.'**
  String get requestSent;

  /// No description provided for @cancelRequest.
  ///
  /// In kk, this message translates to:
  /// **'Сұрауды болдырмау'**
  String get cancelRequest;

  /// No description provided for @waitingApproval.
  ///
  /// In kk, this message translates to:
  /// **'Дүкен иесінің жауабын күтіп жатырсыз'**
  String get waitingApproval;

  /// No description provided for @requestApproved.
  ///
  /// In kk, this message translates to:
  /// **'Сұрауыңыз қабылданды!'**
  String get requestApproved;

  /// No description provided for @validationRequired.
  ///
  /// In kk, this message translates to:
  /// **'Бұл өрісті толтырыңыз'**
  String get validationRequired;

  /// No description provided for @validationEmail.
  ///
  /// In kk, this message translates to:
  /// **'Email форматы дұрыс емес'**
  String get validationEmail;

  /// No description provided for @validationPasswordMin.
  ///
  /// In kk, this message translates to:
  /// **'Пароль минимум 6 таңба'**
  String get validationPasswordMin;

  /// No description provided for @validationPasswordMatch.
  ///
  /// In kk, this message translates to:
  /// **'Парольдер сәйкес емес'**
  String get validationPasswordMatch;

  /// No description provided for @validationNameRequired.
  ///
  /// In kk, this message translates to:
  /// **'Атыңызды енгізіңіз'**
  String get validationNameRequired;

  /// No description provided for @validationEmailRequired.
  ///
  /// In kk, this message translates to:
  /// **'Email енгізіңіз'**
  String get validationEmailRequired;

  /// No description provided for @unknownError.
  ///
  /// In kk, this message translates to:
  /// **'Белгісіз қате. Қайталап көріңіз.'**
  String get unknownError;

  /// No description provided for @validationPasswordRequired.
  ///
  /// In kk, this message translates to:
  /// **'Парольді енгізіңіз'**
  String get validationPasswordRequired;

  /// No description provided for @validationCodeRequired.
  ///
  /// In kk, this message translates to:
  /// **'6 санды толық енгізіңіз'**
  String get validationCodeRequired;

  /// No description provided for @businessCodeSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Дүкен иесінің берген 6 санды бизнес-кодын енгізіңіз'**
  String get businessCodeSubtitle;

  /// No description provided for @requestSentBody.
  ///
  /// In kk, this message translates to:
  /// **'Ұсынысыңыз жіберілді. Дүкен иесі қабылдағаннан кейін автоматты түрде кіресіз.'**
  String get requestSentBody;

  /// No description provided for @history.
  ///
  /// In kk, this message translates to:
  /// **'Тарих'**
  String get history;

  /// No description provided for @selectMonth.
  ///
  /// In kk, this message translates to:
  /// **'Ай таңдаңыз'**
  String get selectMonth;

  /// No description provided for @apply.
  ///
  /// In kk, this message translates to:
  /// **'Қолдану'**
  String get apply;

  /// No description provided for @noSalesThisMonth.
  ///
  /// In kk, this message translates to:
  /// **'Осы айда сатылым жоқ'**
  String get noSalesThisMonth;

  /// No description provided for @operations.
  ///
  /// In kk, this message translates to:
  /// **'Операциялар'**
  String get operations;

  /// No description provided for @productDeleted.
  ///
  /// In kk, this message translates to:
  /// **'Тауар жойылды'**
  String get productDeleted;

  /// No description provided for @overviewSub.
  ///
  /// In kk, this message translates to:
  /// **'Жалпы шолу'**
  String get overviewSub;

  /// No description provided for @makeSaleHint.
  ///
  /// In kk, this message translates to:
  /// **'Сатыңыз'**
  String get makeSaleHint;

  /// No description provided for @sortBy.
  ///
  /// In kk, this message translates to:
  /// **'Сұрыптау'**
  String get sortBy;

  /// No description provided for @sortAZ.
  ///
  /// In kk, this message translates to:
  /// **'Алфавит бойынша А–Я'**
  String get sortAZ;

  /// No description provided for @sortZA.
  ///
  /// In kk, this message translates to:
  /// **'Алфавит бойынша Я–А'**
  String get sortZA;

  /// No description provided for @sortManyStock.
  ///
  /// In kk, this message translates to:
  /// **'Қалдығы көп'**
  String get sortManyStock;

  /// No description provided for @sortFewStock.
  ///
  /// In kk, this message translates to:
  /// **'Қалдығы аз'**
  String get sortFewStock;

  /// No description provided for @searchHint.
  ///
  /// In kk, this message translates to:
  /// **'Іздеу...'**
  String get searchHint;

  /// No description provided for @manageWarehouseSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Қоймамен жұмыс'**
  String get manageWarehouseSubtitle;

  /// No description provided for @inStockSubtitle.
  ///
  /// In kk, this message translates to:
  /// **'Қолда бар тауарлар'**
  String get inStockSubtitle;

  /// No description provided for @financialDashboard.
  ///
  /// In kk, this message translates to:
  /// **'Қаржылық дашборд'**
  String get financialDashboard;

  /// No description provided for @generalTab.
  ///
  /// In kk, this message translates to:
  /// **'Жалпы'**
  String get generalTab;

  /// No description provided for @sellersTab.
  ///
  /// In kk, this message translates to:
  /// **'Сатушылар'**
  String get sellersTab;

  /// No description provided for @warehouseTab.
  ///
  /// In kk, this message translates to:
  /// **'Қойма бойынша'**
  String get warehouseTab;

  /// No description provided for @monthRevenue.
  ///
  /// In kk, this message translates to:
  /// **'Ай кірісі'**
  String get monthRevenue;

  /// No description provided for @costPrice.
  ///
  /// In kk, this message translates to:
  /// **'Өзіндік құн'**
  String get costPrice;

  /// No description provided for @netProfit.
  ///
  /// In kk, this message translates to:
  /// **'Таза пайда'**
  String get netProfit;

  /// No description provided for @income.
  ///
  /// In kk, this message translates to:
  /// **'кіріс'**
  String get income;

  /// No description provided for @lossLabel.
  ///
  /// In kk, this message translates to:
  /// **'шығын'**
  String get lossLabel;

  /// No description provided for @soldPairsMonth.
  ///
  /// In kk, this message translates to:
  /// **'Осы айда сатылды'**
  String get soldPairsMonth;

  /// No description provided for @arrivedPairsMonth.
  ///
  /// In kk, this message translates to:
  /// **'Осы айда келді'**
  String get arrivedPairsMonth;

  /// No description provided for @topSalesTitle.
  ///
  /// In kk, this message translates to:
  /// **'🔥 Топ сатылымдар'**
  String get topSalesTitle;

  /// No description provided for @fastSalesTitle.
  ///
  /// In kk, this message translates to:
  /// **'⚡ Жылдам өткен тауарлар'**
  String get fastSalesTitle;

  /// No description provided for @fastSalesSub.
  ///
  /// In kk, this message translates to:
  /// **'Ең тез сатылды'**
  String get fastSalesSub;

  /// No description provided for @staleProductsTitle.
  ///
  /// In kk, this message translates to:
  /// **'⏳ Ескі қалдықтар'**
  String get staleProductsTitle;

  /// No description provided for @staleProductsSub.
  ///
  /// In kk, this message translates to:
  /// **'Қоймада 30 күннен астам'**
  String get staleProductsSub;

  /// No description provided for @popularSizesTitle.
  ///
  /// In kk, this message translates to:
  /// **'👟 Танымал размерлер'**
  String get popularSizesTitle;

  /// No description provided for @noFastSalesData.
  ///
  /// In kk, this message translates to:
  /// **'Жылдам сатылым деректері жоқ'**
  String get noFastSalesData;

  /// No description provided for @noStaleProductsMsg.
  ///
  /// In kk, this message translates to:
  /// **'Ескі қалдық жоқ 🎉'**
  String get noStaleProductsMsg;

  /// No description provided for @productDeletedShort.
  ///
  /// In kk, this message translates to:
  /// **'Жойылды'**
  String get productDeletedShort;

  /// No description provided for @purchasePrice.
  ///
  /// In kk, this message translates to:
  /// **'Сатып алу бағасы'**
  String get purchasePrice;

  /// No description provided for @sizeLabel.
  ///
  /// In kk, this message translates to:
  /// **'Размер'**
  String get sizeLabel;

  /// No description provided for @pairsUnit.
  ///
  /// In kk, this message translates to:
  /// **'жұп'**
  String get pairsUnit;

  /// No description provided for @noSalesThisMonthSimple.
  ///
  /// In kk, this message translates to:
  /// **'Осы айда сатулар жоқ'**
  String get noSalesThisMonthSimple;

  /// No description provided for @ranking.
  ///
  /// In kk, this message translates to:
  /// **'Рейтинг'**
  String get ranking;

  /// No description provided for @dailyActivity.
  ///
  /// In kk, this message translates to:
  /// **'Күндік белсенділік'**
  String get dailyActivity;

  /// No description provided for @warehouseRanking.
  ///
  /// In kk, this message translates to:
  /// **'Қоймалар рейтингі'**
  String get warehouseRanking;

  /// No description provided for @activeWarehouses.
  ///
  /// In kk, this message translates to:
  /// **'Белсенді қоймалар'**
  String get activeWarehouses;

  /// No description provided for @totalRevenueStat.
  ///
  /// In kk, this message translates to:
  /// **'Жалпы түсім'**
  String get totalRevenueStat;

  /// No description provided for @warehouseSuffix.
  ///
  /// In kk, this message translates to:
  /// **'қойма'**
  String get warehouseSuffix;

  /// No description provided for @revenueSuffix.
  ///
  /// In kk, this message translates to:
  /// **'Түсім'**
  String get revenueSuffix;

  /// No description provided for @salesSuffix.
  ///
  /// In kk, this message translates to:
  /// **'Сатылым'**
  String get salesSuffix;

  /// No description provided for @pairsSuffix.
  ///
  /// In kk, this message translates to:
  /// **'Жұп'**
  String get pairsSuffix;

  /// No description provided for @cartTitle.
  ///
  /// In kk, this message translates to:
  /// **'Себет'**
  String get cartTitle;

  /// No description provided for @clearCart.
  ///
  /// In kk, this message translates to:
  /// **'Себетті тазалау'**
  String get clearCart;

  /// No description provided for @clearCartConfirm.
  ///
  /// In kk, this message translates to:
  /// **'Барлық тауарды себеттен алып тастайсыз ба?'**
  String get clearCartConfirm;

  /// No description provided for @cartClear.
  ///
  /// In kk, this message translates to:
  /// **'Тазалау'**
  String get cartClear;

  /// No description provided for @cartEmpty.
  ///
  /// In kk, this message translates to:
  /// **'Себет бос'**
  String get cartEmpty;

  /// No description provided for @pickupMethod.
  ///
  /// In kk, this message translates to:
  /// **'Алу тәсілі'**
  String get pickupMethod;

  /// No description provided for @smartReservationTitle.
  ///
  /// In kk, this message translates to:
  /// **'Смарт-Бронь'**
  String get smartReservationTitle;

  /// No description provided for @smartReservationDesc.
  ///
  /// In kk, this message translates to:
  /// **'1 сағатқа брондаңыз, дүкенде киіп көріңіз'**
  String get smartReservationDesc;

  /// No description provided for @smartReservationBadge.
  ///
  /// In kk, this message translates to:
  /// **'10% депозит'**
  String get smartReservationBadge;

  /// No description provided for @clickCollectTitle.
  ///
  /// In kk, this message translates to:
  /// **'Click & Collect'**
  String get clickCollectTitle;

  /// No description provided for @clickCollectDesc.
  ///
  /// In kk, this message translates to:
  /// **'Онлайн төлеп, қоймадан алыңыз'**
  String get clickCollectDesc;

  /// No description provided for @clickCollectBadge.
  ///
  /// In kk, this message translates to:
  /// **'100% онлайн'**
  String get clickCollectBadge;

  /// No description provided for @deliveryTitle.
  ///
  /// In kk, this message translates to:
  /// **'Жеткізу'**
  String get deliveryTitle;

  /// No description provided for @deliveryDesc.
  ///
  /// In kk, this message translates to:
  /// **'Мекенжай көрсетіп, курьермен алыңыз'**
  String get deliveryDesc;

  /// No description provided for @enterDeliveryAddress.
  ///
  /// In kk, this message translates to:
  /// **'Жеткізу мекенжайын енгізіңіз'**
  String get enterDeliveryAddress;

  /// No description provided for @deliveryAddressLabel.
  ///
  /// In kk, this message translates to:
  /// **'Жеткізу мекенжайы *'**
  String get deliveryAddressLabel;

  /// No description provided for @deliveryAddressPlaceholder.
  ///
  /// In kk, this message translates to:
  /// **'Қала, көше, үй, пәтер'**
  String get deliveryAddressPlaceholder;

  /// No description provided for @noteOptional.
  ///
  /// In kk, this message translates to:
  /// **'Ескертпе (міндетті емес)'**
  String get noteOptional;

  /// No description provided for @additionalInfoHint.
  ///
  /// In kk, this message translates to:
  /// **'Қосымша ақпарат...'**
  String get additionalInfoHint;

  /// No description provided for @itemsUnavailable.
  ///
  /// In kk, this message translates to:
  /// **'{names} қолжетімсіз (сатылып кетті немесе дүкен жаңартылды). Себеттен алып тастаңыз.'**
  String itemsUnavailable(String names);

  /// No description provided for @ordersCreated.
  ///
  /// In kk, this message translates to:
  /// **'{count} тапсырыс құрылды'**
  String ordersCreated(int count);

  /// No description provided for @soldOutUnavailable.
  ///
  /// In kk, this message translates to:
  /// **'Сатылып кетті / қолжетімсіз'**
  String get soldOutUnavailable;

  /// No description provided for @goodsTotal.
  ///
  /// In kk, this message translates to:
  /// **'Тауар сомасы'**
  String get goodsTotal;

  /// No description provided for @totalToPay.
  ///
  /// In kk, this message translates to:
  /// **'Төленетін сома'**
  String get totalToPay;

  /// No description provided for @payNowDeposit.
  ///
  /// In kk, this message translates to:
  /// **'Қазір төлеу (10%)'**
  String get payNowDeposit;

  /// No description provided for @payAtStoreBalance.
  ///
  /// In kk, this message translates to:
  /// **'Дүкенде доплата (90%)'**
  String get payAtStoreBalance;

  /// No description provided for @confirmAndReserve.
  ///
  /// In kk, this message translates to:
  /// **'Растап брондау'**
  String get confirmAndReserve;

  /// No description provided for @confirmAndPay.
  ///
  /// In kk, this message translates to:
  /// **'Растап төлеу'**
  String get confirmAndPay;

  /// No description provided for @reserveWithAmount.
  ///
  /// In kk, this message translates to:
  /// **'Брондау — {amount} ₸'**
  String reserveWithAmount(String amount);

  /// No description provided for @payWithAmount.
  ///
  /// In kk, this message translates to:
  /// **'Төлеу — {amount} ₸'**
  String payWithAmount(String amount);

  /// No description provided for @pickupAddressLabel.
  ///
  /// In kk, this message translates to:
  /// **'Алу мекенжайы'**
  String get pickupAddressLabel;

  /// No description provided for @reservationTimeframe.
  ///
  /// In kk, this message translates to:
  /// **'Бронь мерзімі'**
  String get reservationTimeframe;

  /// No description provided for @oneHour.
  ///
  /// In kk, this message translates to:
  /// **'1 сағат'**
  String get oneHour;

  /// No description provided for @sizeQtyLabel.
  ///
  /// In kk, this message translates to:
  /// **'Өлшем: {size}  ×{qty}'**
  String sizeQtyLabel(String size, String qty);

  /// No description provided for @onlineTab.
  ///
  /// In kk, this message translates to:
  /// **'Онлайн'**
  String get onlineTab;

  /// No description provided for @totalRevenueLabel.
  ///
  /// In kk, this message translates to:
  /// **'Жалпы Түсірілке'**
  String get totalRevenueLabel;

  /// No description provided for @offlineOnlineRevSub.
  ///
  /// In kk, this message translates to:
  /// **'Офлайн: {offline} ₸  ·  Онлайн: {online} ₸'**
  String offlineOnlineRevSub(String offline, String online);

  /// No description provided for @marginLabel.
  ///
  /// In kk, this message translates to:
  /// **'Маржа'**
  String get marginLabel;

  /// No description provided for @pairsSoldLabel.
  ///
  /// In kk, this message translates to:
  /// **'Сатылған жұп'**
  String get pairsSoldLabel;

  /// No description provided for @offlineOnlinePairsSub.
  ///
  /// In kk, this message translates to:
  /// **'Офлайн: {offline}  ·  Онлайн: {online}'**
  String offlineOnlinePairsSub(String offline, String online);

  /// No description provided for @revenueOnline.
  ///
  /// In kk, this message translates to:
  /// **'Түсімі (Онлайн)'**
  String get revenueOnline;

  /// No description provided for @ordersLabel.
  ///
  /// In kk, this message translates to:
  /// **'Тапсырыстар'**
  String get ordersLabel;

  /// No description provided for @cancelledLabel.
  ///
  /// In kk, this message translates to:
  /// **'Бас тарту'**
  String get cancelledLabel;

  /// No description provided for @pairsSoldOnline.
  ///
  /// In kk, this message translates to:
  /// **'Сатылған жұп (онлайн)'**
  String get pairsSoldOnline;

  /// No description provided for @dailyActivityOnline.
  ///
  /// In kk, this message translates to:
  /// **'Күндік белсенділік (онлайн)'**
  String get dailyActivityOnline;

  /// No description provided for @totalChartAmount.
  ///
  /// In kk, this message translates to:
  /// **'Жалпы: {amount} ₸'**
  String totalChartAmount(String amount);

  /// No description provided for @noStaleItems.
  ///
  /// In kk, this message translates to:
  /// **'Жатып қалған тауар жоқ 👍'**
  String get noStaleItems;

  /// No description provided for @staleItemsTitle.
  ///
  /// In kk, this message translates to:
  /// **'Жатып қалған тауар (30+ күн)'**
  String get staleItemsTitle;

  /// No description provided for @topThreeSales.
  ///
  /// In kk, this message translates to:
  /// **'Топ-3 сатылымдар'**
  String get topThreeSales;

  /// No description provided for @noSalesLabel.
  ///
  /// In kk, this message translates to:
  /// **'Сатылым жоқ'**
  String get noSalesLabel;

  /// No description provided for @topOneSeller.
  ///
  /// In kk, this message translates to:
  /// **'🥇 Топ-1: {name}'**
  String topOneSeller(String name);

  /// No description provided for @sellerSalesCount.
  ///
  /// In kk, this message translates to:
  /// **'{count} сат · {pairs} жұп'**
  String sellerSalesCount(int count, int pairs);

  /// No description provided for @ordersTitle.
  ///
  /// In kk, this message translates to:
  /// **'Тапсырыстар'**
  String get ordersTitle;

  /// No description provided for @noPhoneNumber.
  ///
  /// In kk, this message translates to:
  /// **'Телефон нөмірі жоқ'**
  String get noPhoneNumber;

  /// No description provided for @noOrders.
  ///
  /// In kk, this message translates to:
  /// **'Тапсырыс жоқ'**
  String get noOrders;

  /// No description provided for @statusReserved.
  ///
  /// In kk, this message translates to:
  /// **'Брондалды'**
  String get statusReserved;

  /// No description provided for @statusPending.
  ///
  /// In kk, this message translates to:
  /// **'Күтуде'**
  String get statusPending;

  /// No description provided for @statusCompleted.
  ///
  /// In kk, this message translates to:
  /// **'Аяқталды'**
  String get statusCompleted;

  /// No description provided for @statusCancelled.
  ///
  /// In kk, this message translates to:
  /// **'Бас тартылды'**
  String get statusCancelled;

  /// No description provided for @goodsAmount.
  ///
  /// In kk, this message translates to:
  /// **'Тауар сомасы'**
  String get goodsAmount;

  /// No description provided for @paidDeposit.
  ///
  /// In kk, this message translates to:
  /// **'Төленген депозит'**
  String get paidDeposit;

  /// No description provided for @remainsAtStore.
  ///
  /// In kk, this message translates to:
  /// **'Дүкенде қалды'**
  String get remainsAtStore;

  /// No description provided for @paidLabel.
  ///
  /// In kk, this message translates to:
  /// **'Төленді'**
  String get paidLabel;

  /// No description provided for @showQrToSeller.
  ///
  /// In kk, this message translates to:
  /// **'Сатушыға осы QR кодты көрсетіңіз'**
  String get showQrToSeller;

  /// No description provided for @showQrToStore.
  ///
  /// In kk, this message translates to:
  /// **'Дүкенге осы QR кодты көрсетіңіз'**
  String get showQrToStore;

  /// No description provided for @onlineOrdersTitle.
  ///
  /// In kk, this message translates to:
  /// **'Онлайн тапсырыстар'**
  String get onlineOrdersTitle;

  /// No description provided for @enterOrderCode.
  ///
  /// In kk, this message translates to:
  /// **'Тапсырыс кодын енгізіңіз...'**
  String get enterOrderCode;

  /// No description provided for @findButton.
  ///
  /// In kk, this message translates to:
  /// **'Іздеу'**
  String get findButton;

  /// No description provided for @invalidCodeOrNotFound.
  ///
  /// In kk, this message translates to:
  /// **'Код қате немесе тапсырыс табылмады'**
  String get invalidCodeOrNotFound;

  /// No description provided for @orderNotForWarehouse.
  ///
  /// In kk, this message translates to:
  /// **'Бұл тапсырыс сіздің қоймаңызға тиесілі емес'**
  String get orderNotForWarehouse;

  /// No description provided for @orderNotFoundLabel.
  ///
  /// In kk, this message translates to:
  /// **'Тапсырыс табылмады'**
  String get orderNotFoundLabel;

  /// No description provided for @allWithCount.
  ///
  /// In kk, this message translates to:
  /// **'Барлығы {count}'**
  String allWithCount(int count);

  /// No description provided for @activeWithCount.
  ///
  /// In kk, this message translates to:
  /// **'Белсенді {count}'**
  String activeWithCount(int count);

  /// No description provided for @completedWithCount.
  ///
  /// In kk, this message translates to:
  /// **'Аяқталды {count}'**
  String completedWithCount(int count);

  /// No description provided for @cancelledWithCount.
  ///
  /// In kk, this message translates to:
  /// **'Бас тартылды {count}'**
  String cancelledWithCount(int count);

  /// No description provided for @orderFoundLabel.
  ///
  /// In kk, this message translates to:
  /// **'Тапсырыс табылды'**
  String get orderFoundLabel;

  /// No description provided for @noActiveOrders.
  ///
  /// In kk, this message translates to:
  /// **'Белсенді тапсырыс жоқ'**
  String get noActiveOrders;

  /// No description provided for @noCompletedOrders.
  ///
  /// In kk, this message translates to:
  /// **'Аяқталған тапсырыс жоқ'**
  String get noCompletedOrders;

  /// No description provided for @noCancelledOrders.
  ///
  /// In kk, this message translates to:
  /// **'Бас тартылған тапсырыс жоқ'**
  String get noCancelledOrders;

  /// No description provided for @noOrdersLabel.
  ///
  /// In kk, this message translates to:
  /// **'Тапсырыс жоқ'**
  String get noOrdersLabel;

  /// No description provided for @nameNotSpecified.
  ///
  /// In kk, this message translates to:
  /// **'Аты көрсетілмеген'**
  String get nameNotSpecified;

  /// No description provided for @phoneCopied.
  ///
  /// In kk, this message translates to:
  /// **'Телефон көшірілді'**
  String get phoneCopied;

  /// No description provided for @depositPaidBadge.
  ///
  /// In kk, this message translates to:
  /// **'Депозит төленді (10%)'**
  String get depositPaidBadge;

  /// No description provided for @payAtStoreLabel.
  ///
  /// In kk, this message translates to:
  /// **'Дүкенде доплата'**
  String get payAtStoreLabel;

  /// No description provided for @totalPaidLabel.
  ///
  /// In kk, this message translates to:
  /// **'Барлығы төленді'**
  String get totalPaidLabel;

  /// No description provided for @clientPaidFull.
  ///
  /// In kk, this message translates to:
  /// **'Клиент толық сомасын төледі ме?'**
  String get clientPaidFull;

  /// No description provided for @markAsDeliveredQ.
  ///
  /// In kk, this message translates to:
  /// **'Жеткізілді деп белгілеу?'**
  String get markAsDeliveredQ;

  /// No description provided for @markAsGivenQ.
  ///
  /// In kk, this message translates to:
  /// **'Берілді деп белгілеу?'**
  String get markAsGivenQ;

  /// No description provided for @confirmationTitle.
  ///
  /// In kk, this message translates to:
  /// **'Растау'**
  String get confirmationTitle;

  /// No description provided for @yesConfirmBtn.
  ///
  /// In kk, this message translates to:
  /// **'Иә, растаймын'**
  String get yesConfirmBtn;

  /// No description provided for @cancelOrderDialog.
  ///
  /// In kk, this message translates to:
  /// **'Тапсырысты болдырмау'**
  String get cancelOrderDialog;

  /// No description provided for @cancelOrderMsg.
  ///
  /// In kk, this message translates to:
  /// **'Тапсырыс болдырылмайды, тауар қоймаға оралады.'**
  String get cancelOrderMsg;

  /// No description provided for @cancelOrderBtn.
  ///
  /// In kk, this message translates to:
  /// **'Тапсырысты болдырмау'**
  String get cancelOrderBtn;

  /// No description provided for @fullPaymentLabel.
  ///
  /// In kk, this message translates to:
  /// **'Толық төлем'**
  String get fullPaymentLabel;

  /// No description provided for @deliveredLabel.
  ///
  /// In kk, this message translates to:
  /// **'Жеткізілді'**
  String get deliveredLabel;

  /// No description provided for @givenLabel.
  ///
  /// In kk, this message translates to:
  /// **'Тауар берілді'**
  String get givenLabel;

  /// No description provided for @cancelBtn.
  ///
  /// In kk, this message translates to:
  /// **'Болдырмау'**
  String get cancelBtn;

  /// No description provided for @smartResBadgeUpper.
  ///
  /// In kk, this message translates to:
  /// **'СМАРТ-БРОНЬ'**
  String get smartResBadgeUpper;

  /// No description provided for @clickCollectUpper.
  ///
  /// In kk, this message translates to:
  /// **'CLICK & COLLECT'**
  String get clickCollectUpper;

  /// No description provided for @deliveryUpper.
  ///
  /// In kk, this message translates to:
  /// **'ЖЕТКІЗУ'**
  String get deliveryUpper;

  /// No description provided for @storeTitle.
  ///
  /// In kk, this message translates to:
  /// **'Дүкен'**
  String get storeTitle;

  /// No description provided for @productSearchHint.
  ///
  /// In kk, this message translates to:
  /// **'Тауар іздеу...'**
  String get productSearchHint;

  /// No description provided for @noActiveStores.
  ///
  /// In kk, this message translates to:
  /// **'Белсенді дүкен жоқ'**
  String get noActiveStores;

  /// No description provided for @searchNotFoundMsg.
  ///
  /// In kk, this message translates to:
  /// **'«{query}» табылмады'**
  String searchNotFoundMsg(String query);

  /// No description provided for @noProductsLabel.
  ///
  /// In kk, this message translates to:
  /// **'Тауар жоқ'**
  String get noProductsLabel;

  /// No description provided for @outOfStock.
  ///
  /// In kk, this message translates to:
  /// **'Қолда жоқ'**
  String get outOfStock;

  /// No description provided for @addedToCartMsg.
  ///
  /// In kk, this message translates to:
  /// **'{name} себетке қосылды'**
  String addedToCartMsg(String name);

  /// No description provided for @addToCartBtn.
  ///
  /// In kk, this message translates to:
  /// **'Себетке'**
  String get addToCartBtn;

  /// No description provided for @returnsTitle.
  ///
  /// In kk, this message translates to:
  /// **'Қайтарулар'**
  String get returnsTitle;

  /// No description provided for @returnTabList.
  ///
  /// In kk, this message translates to:
  /// **'Тізім'**
  String get returnTabList;

  /// No description provided for @returnTabAnalytics.
  ///
  /// In kk, this message translates to:
  /// **'Аналитика'**
  String get returnTabAnalytics;

  /// No description provided for @returnStatusRequested.
  ///
  /// In kk, this message translates to:
  /// **'Сұраныс жіберілді'**
  String get returnStatusRequested;

  /// No description provided for @returnStatusApproved.
  ///
  /// In kk, this message translates to:
  /// **'Қабылданды'**
  String get returnStatusApproved;

  /// No description provided for @returnStatusReceived.
  ///
  /// In kk, this message translates to:
  /// **'Тауар алынды'**
  String get returnStatusReceived;

  /// No description provided for @returnStatusRefunded.
  ///
  /// In kk, this message translates to:
  /// **'Ақша қайтарылды'**
  String get returnStatusRefunded;

  /// No description provided for @returnStatusRejected.
  ///
  /// In kk, this message translates to:
  /// **'Бас тартылды'**
  String get returnStatusRejected;

  /// No description provided for @returnTypeOnline.
  ///
  /// In kk, this message translates to:
  /// **'Онлайн'**
  String get returnTypeOnline;

  /// No description provided for @returnTypeOffline.
  ///
  /// In kk, this message translates to:
  /// **'Офлайн'**
  String get returnTypeOffline;

  /// No description provided for @returnReasonSizeNotFit.
  ///
  /// In kk, this message translates to:
  /// **'Размер сәйкес емес'**
  String get returnReasonSizeNotFit;

  /// No description provided for @returnReasonQualityBad.
  ///
  /// In kk, this message translates to:
  /// **'Сапа нашар'**
  String get returnReasonQualityBad;

  /// No description provided for @returnReasonNotAsDescribed.
  ///
  /// In kk, this message translates to:
  /// **'Суретке сәйкес емес'**
  String get returnReasonNotAsDescribed;

  /// No description provided for @returnReasonJustDidntLike.
  ///
  /// In kk, this message translates to:
  /// **'Ұнамады'**
  String get returnReasonJustDidntLike;

  /// No description provided for @returnReasonOther.
  ///
  /// In kk, this message translates to:
  /// **'Басқа себеп'**
  String get returnReasonOther;

  /// No description provided for @returnPickupSelf.
  ///
  /// In kk, this message translates to:
  /// **'Өзім әкелемін'**
  String get returnPickupSelf;

  /// No description provided for @returnPickupCourier.
  ///
  /// In kk, this message translates to:
  /// **'Курьермен'**
  String get returnPickupCourier;

  /// No description provided for @returnRefundCard.
  ///
  /// In kk, this message translates to:
  /// **'Картамен'**
  String get returnRefundCard;

  /// No description provided for @returnRefundCash.
  ///
  /// In kk, this message translates to:
  /// **'Қолма-қол'**
  String get returnRefundCash;

  /// No description provided for @returnRefundExchange.
  ///
  /// In kk, this message translates to:
  /// **'Айырбас'**
  String get returnRefundExchange;

  /// No description provided for @returnFilterAll.
  ///
  /// In kk, this message translates to:
  /// **'Барлығы'**
  String get returnFilterAll;

  /// No description provided for @returnFilterNew.
  ///
  /// In kk, this message translates to:
  /// **'Жаңа'**
  String get returnFilterNew;

  /// No description provided for @returnFilterPending.
  ///
  /// In kk, this message translates to:
  /// **'Шешім күтуде'**
  String get returnFilterPending;

  /// No description provided for @returnFilterApproved.
  ///
  /// In kk, this message translates to:
  /// **'Қабылданды'**
  String get returnFilterApproved;

  /// No description provided for @returnFilterProcessing.
  ///
  /// In kk, this message translates to:
  /// **'Өңдеуде'**
  String get returnFilterProcessing;

  /// No description provided for @returnFilterReceived.
  ///
  /// In kk, this message translates to:
  /// **'Тауарды күтуде'**
  String get returnFilterReceived;

  /// No description provided for @returnFilterCompleted.
  ///
  /// In kk, this message translates to:
  /// **'Аяқталды'**
  String get returnFilterCompleted;

  /// No description provided for @returnFilterRejected.
  ///
  /// In kk, this message translates to:
  /// **'Бас тартылды'**
  String get returnFilterRejected;

  /// No description provided for @returnPerSellerTitle.
  ///
  /// In kk, this message translates to:
  /// **'Сатушылар бойынша'**
  String get returnPerSellerTitle;

  /// No description provided for @returnCreateButton.
  ///
  /// In kk, this message translates to:
  /// **'Қайтару жасау'**
  String get returnCreateButton;

  /// No description provided for @returnCancelRequest.
  ///
  /// In kk, this message translates to:
  /// **'Сұранысты болдырмау'**
  String get returnCancelRequest;

  /// No description provided for @returnApprove.
  ///
  /// In kk, this message translates to:
  /// **'Қабылдау'**
  String get returnApprove;

  /// No description provided for @returnReject.
  ///
  /// In kk, this message translates to:
  /// **'Бас тарту'**
  String get returnReject;

  /// No description provided for @returnReceiveTitle.
  ///
  /// In kk, this message translates to:
  /// **'Тауарды қабылдау'**
  String get returnReceiveTitle;

  /// No description provided for @returnConditionOk.
  ///
  /// In kk, this message translates to:
  /// **'Жарамды'**
  String get returnConditionOk;

  /// No description provided for @returnConditionBad.
  ///
  /// In kk, this message translates to:
  /// **'Жарамсыз'**
  String get returnConditionBad;

  /// No description provided for @returnConditionLabel.
  ///
  /// In kk, this message translates to:
  /// **'Тауар жағдайы'**
  String get returnConditionLabel;

  /// No description provided for @returnRefundTitle.
  ///
  /// In kk, this message translates to:
  /// **'Ақша қайтару'**
  String get returnRefundTitle;

  /// No description provided for @returnRefundMethodLabel.
  ///
  /// In kk, this message translates to:
  /// **'Қайтару тәсілі'**
  String get returnRefundMethodLabel;

  /// No description provided for @returnCompleteRefund.
  ///
  /// In kk, this message translates to:
  /// **'Аяқтау'**
  String get returnCompleteRefund;

  /// No description provided for @returnTimelineStep1.
  ///
  /// In kk, this message translates to:
  /// **'Сұраныс жіберілді'**
  String get returnTimelineStep1;

  /// No description provided for @returnTimelineStep2.
  ///
  /// In kk, this message translates to:
  /// **'Сатушы қарауда'**
  String get returnTimelineStep2;

  /// No description provided for @returnTimelineStep3.
  ///
  /// In kk, this message translates to:
  /// **'Тауарды дүкенге апарыңыз'**
  String get returnTimelineStep3;

  /// No description provided for @returnTimelineStep4.
  ///
  /// In kk, this message translates to:
  /// **'Ақша қайтарылды'**
  String get returnTimelineStep4;

  /// No description provided for @returnAnalyticsTitle.
  ///
  /// In kk, this message translates to:
  /// **'Қайтару аналитикасы'**
  String get returnAnalyticsTitle;

  /// No description provided for @returnRate.
  ///
  /// In kk, this message translates to:
  /// **'Қайтару үлесі'**
  String get returnRate;

  /// No description provided for @returnReasonBreakdown.
  ///
  /// In kk, this message translates to:
  /// **'Себептер бойынша'**
  String get returnReasonBreakdown;

  /// No description provided for @returnTopProducts.
  ///
  /// In kk, this message translates to:
  /// **'Ең жиі қайтарылатын тауарлар'**
  String get returnTopProducts;

  /// No description provided for @returnNoReturns.
  ///
  /// In kk, this message translates to:
  /// **'Қайтарулар жоқ'**
  String get returnNoReturns;

  /// No description provided for @returnNoReturnsHint.
  ///
  /// In kk, this message translates to:
  /// **'Белсенді қайтарулар жоқ'**
  String get returnNoReturnsHint;

  /// No description provided for @returnRejectReason.
  ///
  /// In kk, this message translates to:
  /// **'Бас тарту себебі'**
  String get returnRejectReason;

  /// No description provided for @returnEnterRejectReason.
  ///
  /// In kk, this message translates to:
  /// **'Себебін жазыңыз...'**
  String get returnEnterRejectReason;

  /// No description provided for @returnSellerNote.
  ///
  /// In kk, this message translates to:
  /// **'Сатушы ескертпесі'**
  String get returnSellerNote;

  /// No description provided for @returnNotesLabel.
  ///
  /// In kk, this message translates to:
  /// **'Ескертпе'**
  String get returnNotesLabel;

  /// No description provided for @returnPhotosLabel.
  ///
  /// In kk, this message translates to:
  /// **'Суреттер'**
  String get returnPhotosLabel;

  /// No description provided for @returnClientSection.
  ///
  /// In kk, this message translates to:
  /// **'Клиент'**
  String get returnClientSection;

  /// No description provided for @returnSourceSection.
  ///
  /// In kk, this message translates to:
  /// **'Бастапқы тапсырыс/сату'**
  String get returnSourceSection;

  /// No description provided for @returnTimelineTitle.
  ///
  /// In kk, this message translates to:
  /// **'Күй тарихы'**
  String get returnTimelineTitle;

  /// No description provided for @returnOfflineFindReceipt.
  ///
  /// In kk, this message translates to:
  /// **'Чекті табу'**
  String get returnOfflineFindReceipt;

  /// No description provided for @returnOfflineSelectItems.
  ///
  /// In kk, this message translates to:
  /// **'Тауарларды таңдау'**
  String get returnOfflineSelectItems;

  /// No description provided for @returnOfflineRefundMethod.
  ///
  /// In kk, this message translates to:
  /// **'Ақша қайтару тәсілі'**
  String get returnOfflineRefundMethod;

  /// No description provided for @returnOfflineReceiptHint.
  ///
  /// In kk, this message translates to:
  /// **'Чек нөмірі (ID бойынша іздеу)'**
  String get returnOfflineReceiptHint;

  /// No description provided for @returnOfflineQrTodo.
  ///
  /// In kk, this message translates to:
  /// **'QR сканер (жоспарда)'**
  String get returnOfflineQrTodo;

  /// No description provided for @returnSuccessMsg.
  ///
  /// In kk, this message translates to:
  /// **'Қайтару сұранысы жіберілді!'**
  String get returnSuccessMsg;

  /// No description provided for @returnApproveSuccess.
  ///
  /// In kk, this message translates to:
  /// **'Қайтару қабылданды'**
  String get returnApproveSuccess;

  /// No description provided for @returnRejectSuccess.
  ///
  /// In kk, this message translates to:
  /// **'Қайтару бас тартылды'**
  String get returnRejectSuccess;

  /// No description provided for @returnReceiveSuccess.
  ///
  /// In kk, this message translates to:
  /// **'Тауар қабылданды'**
  String get returnReceiveSuccess;

  /// No description provided for @returnRefundSuccess.
  ///
  /// In kk, this message translates to:
  /// **'Ақша қайтарылды!'**
  String get returnRefundSuccess;

  /// No description provided for @returnStockRestored.
  ///
  /// In kk, this message translates to:
  /// **'Тауар қоймаға оралды'**
  String get returnStockRestored;

  /// No description provided for @returnNoStock.
  ///
  /// In kk, this message translates to:
  /// **'Тауар қоймаға оралмады (жарамсыз)'**
  String get returnNoStock;

  /// No description provided for @returnDaysLeft.
  ///
  /// In kk, this message translates to:
  /// **'{days} күн қалды'**
  String returnDaysLeft(int days);

  /// No description provided for @returnActiveChip.
  ///
  /// In kk, this message translates to:
  /// **'Өңдеуде'**
  String get returnActiveChip;

  /// No description provided for @returnConfirmTitle.
  ///
  /// In kk, this message translates to:
  /// **'Растау'**
  String get returnConfirmTitle;

  /// No description provided for @returnSummaryTitle.
  ///
  /// In kk, this message translates to:
  /// **'Жиынтық'**
  String get returnSummaryTitle;

  /// No description provided for @returnReasonLabel.
  ///
  /// In kk, this message translates to:
  /// **'Қайтару себебі'**
  String get returnReasonLabel;

  /// No description provided for @returnPickupLabel.
  ///
  /// In kk, this message translates to:
  /// **'Жеткізу тәсілі'**
  String get returnPickupLabel;

  /// No description provided for @returnSelectItemsHint.
  ///
  /// In kk, this message translates to:
  /// **'Қайтаруға тауарларды таңдаңыз'**
  String get returnSelectItemsHint;

  /// No description provided for @returnItemsSection.
  ///
  /// In kk, this message translates to:
  /// **'Тауарлар'**
  String get returnItemsSection;

  /// No description provided for @returnAmountSection.
  ///
  /// In kk, this message translates to:
  /// **'Қайтару сомасы'**
  String get returnAmountSection;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['kk', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'kk':
      return AppLocalizationsKk();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
