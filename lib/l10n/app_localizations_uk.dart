// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'PIPSTATS';

  @override
  String get headerTitle => 'PIPSTATS';

  @override
  String get systemTab => 'СИСТЕМА';

  @override
  String get vaultTab => 'СХОВИЩЕ';

  @override
  String get sysInfoTab => 'SYSINFO';

  @override
  String get charge => 'ЗАРЯД';

  @override
  String get uptime => 'АПТАЙМ';

  @override
  String get batteryCapacity => 'ЄМНІСТЬ';

  @override
  String get screenTime => 'ЕКРАННИЙ ЧАС';

  @override
  String refreshIn(Object seconds) {
    return 'ОНОВЛЕННЯ $secondsс';
  }

  @override
  String get deviceInfoLoadFailed =>
      'НЕ ВДАЛОСЯ ЗАВАНТАЖИТИ ІНФОРМАЦІЮ ПРО ПРИСТРІЙ';

  @override
  String get periodDay => 'День';

  @override
  String get periodWeek => 'Тиждень';

  @override
  String get periodMonth => 'Місяць';

  @override
  String get periodAll => 'Весь час';

  @override
  String get applicationsHeader => '[ ЗАСТОСУНКИ ]';

  @override
  String get sortTime => 'ЧАС';

  @override
  String get sortLaunch => 'ЗАПУСК';

  @override
  String get noDataYet => 'ДАНИХ ЩЕ НЕМАЄ';

  @override
  String get shortHistory =>
      'НЕМАЄ НАКОПИЧЕНОЇ ІСТОРІЇ ДО ЦЬОГО ПЕРІОДУ — дані збираються з часом';

  @override
  String get appInfo => 'ІНФО ПРО ЗАСТОСУНОК';

  @override
  String get resetStats => 'СКИНУТИ СТАТИСТИКУ';

  @override
  String get usageAccessRequired => 'ПОТРІБЕН ДОСТУП ДО ВИКОРИСТАННЯ';

  @override
  String get grantAccessHint =>
      'Надайте його тут:\nНалаштування > Спеціальний доступ > Статистика використання';

  @override
  String get grantAccess => 'НАДАТИ ДОСТУП';

  @override
  String get seedVault => '[ SEED СХОВИЩЕ ]';

  @override
  String get connectSeedVault => 'ПІДКЛЮЧІТЬ SEED СХОВИЩЕ АБО ВВЕДІТЬ АДРЕСУ';

  @override
  String get connectSeedVaultBtn => 'ПІДКЛЮЧИТИ (SEED СХОВИЩЕ)';

  @override
  String get addressHint => 'base58 адреса або name.skr';

  @override
  String get scanWallet => 'СКАНУВАТИ ГАМАНЕЦЬ';

  @override
  String get rescan => 'ПЕРЕСКАНУВАТИ';

  @override
  String get remove => 'ВИДАЛИТИ';

  @override
  String addrLabel(Object address) {
    return 'АДРЕСА: $address';
  }

  @override
  String walletLabel(Object label) {
    return 'МІТКА: $label';
  }

  @override
  String solBalance(Object balance) {
    return 'БАЛАНС SOL: $balance';
  }

  @override
  String estValue(Object amount) {
    return 'ОЦІНКА: ~\$$amount';
  }

  @override
  String get pricesUnavailable => 'ЦІНИ НЕДОСТУПНІ';

  @override
  String get metadataUnavailable =>
      'МЕТАДАНІ ТОКЕНІВ/NFT НЕДОСТУПНІ (НЕМАЄ HELIUS KEY)';

  @override
  String get delegations => '[ ДЕЛЕГУВАННЯ ]';

  @override
  String get tabDelegations => 'ДЕЛЕГ';

  @override
  String get tabTokens => 'ТОКЕНИ';

  @override
  String get tabNfts => 'NFT';

  @override
  String get tabTx => 'TX';

  @override
  String get connectWalletToScan => 'ПІДКЛЮЧИТЬ ГАМАНЕЦЬ ДЛЯ СКАНУВАННЯ';

  @override
  String get scanning => 'СКАНУВАННЯ...';

  @override
  String get noActiveDelegations => 'АКТИВНИХ ДЕЛЕГУВАНЬ НЕ ЗНАЙДЕНО';

  @override
  String accountLabel(Object account) {
    return 'АКАУНТ: $account';
  }

  @override
  String mintLabel(Object mint) {
    return 'MINT: $mint';
  }

  @override
  String delegateLabel(Object delegate) {
    return 'ДЕЛЕГАТ: $delegate';
  }

  @override
  String approvedAmountLabel(Object amount) {
    return 'ЗАТВЕРДЖЕНА СУМА: $amount';
  }

  @override
  String get revoke => 'ВІДКЛИКАТИ';

  @override
  String get pleaseWait => 'ЗАЧЕКАЙТЕ...';

  @override
  String get closeAuthority => '[ ПРАВО ЗАКРИТТЯ ]';

  @override
  String get noCloseAuthorityRisks => 'РИЗИКІВ ПРАВА ЗАКРИТТЯ НЕМАЄ';

  @override
  String closeAuthorityLabel(Object authority) {
    return 'ПРАВО ЗАКРИТТЯ: $authority';
  }

  @override
  String get closeAuthorityWarning =>
      'Право закриття дозволяє спалити та закрити цей акаунт.';

  @override
  String get tokens => '[ ТОКЕНИ ]';

  @override
  String get noTokens => 'ТОКЕНІВ НЕМАЄ';

  @override
  String get nfts => '[ NFT ]';

  @override
  String get noNfts => 'NFT НЕМАЄ';

  @override
  String get unnamed => 'БЕЗ ІМЕНІ';

  @override
  String moreCount(Object count) {
    return '… ще +$count';
  }

  @override
  String spamHidden(Object count) {
    return '$count спам/спалених NFT приховано';
  }

  @override
  String get transactions => '[ ТРАНЗАКЦІЇ ]';

  @override
  String get noTransactions => 'ТРАНЗАКЦІЙ НЕМАЄ';

  @override
  String get statusOk => 'OK';

  @override
  String get statusFailed => 'НЕВДАЧА';

  @override
  String txStatusSig(Object status, Object sig) {
    return '[$status] $sig';
  }

  @override
  String txSlot(Object slot) {
    return 'слот $slot';
  }

  @override
  String feeSol(Object fee) {
    return 'КОМІСІЯ: $fee SOL';
  }

  @override
  String protoLabel(Object programs) {
    return 'ПРОТОКОЛ: $programs';
  }

  @override
  String solTransfer(Object dest, Object sol) {
    return '-> $dest  ($sol SOL)';
  }

  @override
  String tokenTransfer(Object dest, Object amount) {
    return '-> $dest  ($amount raw)';
  }

  @override
  String get timeJustNow => 'щойно';

  @override
  String timeMinutesAgo(Object minutes) {
    return '$minutesхв тому';
  }

  @override
  String timeHoursAgo(Object hours) {
    return '$hoursгод тому';
  }

  @override
  String timeDaysAgo(Object days) {
    return '$daysд тому';
  }

  @override
  String get revokeSection => '[ ВІДКЛИКАТИ ] *';

  @override
  String get revokeClearsHint => '* ВІДКЛИКАННЯ ОЧИЩАЄ ДЕЛЕГАТА ТОКЕН-АКАУНТА.';

  @override
  String get revokeDisclaimer =>
      'Кожне делегування вище має кнопку ВІДКЛИКАТИ. Підпис виконується в Seed Сховищі (подвійний дотик). Розробник не несе відповідальності за ваші дії тут. Дійте на власний ризик.';

  @override
  String revokedOk(Object sig) {
    return 'ВІДКЛИКАНО — tx: $sig';
  }

  @override
  String revokeError(Object error) {
    return 'ПОМИЛКА ВІДКЛИКАННЯ: $error';
  }

  @override
  String scanError(Object error) {
    return 'ПОМИЛКА СКАНУВАННЯ: $error';
  }

  @override
  String authError(Object error) {
    return 'ПОМИЛКА АВТОРИЗАЦІЇ: $error';
  }

  @override
  String get seedVaultUnavailable => 'SEED СХОВИЩЕ НЕДОСТУПНЕ АБО СКАСОВАНО';

  @override
  String get domainNotFound => 'ДОМЕН НЕ ЗНАЙДЕНО';

  @override
  String get invalidAddress => 'НЕКОРЕКТНА АДРЕСА — має бути base58 pubkey';

  @override
  String get privacy => '[ КОНФІДЕНЦІЙНІСТЬ ]';

  @override
  String get tapToView => 'ТОРКНІТЬСЯ ЩОБ ПЕРЕГЛЯНУТИ >';

  @override
  String get privacyPolicy => 'ПОЛІТИКА КОНФІДЕНЦІЙНОСТІ';

  @override
  String get privacyBody =>
      'Device Stats зберігає ваші дані на пристрої. Статистика використання зберігається лише в локальній базі даних. Коли ви підключаєте гаманець, застосунок виконує лише запити читання до публічних API Solana, використовуючи вашу публічну адресу. Приватні ключі та seed-фрази ніколи не покидають захищене Seed Сховище. Жодні персональні дані не продаються та не передаються. Повну політику див. у PRIVACY.md.';

  @override
  String get close => 'ЗАКРИТИ';

  @override
  String get cancel => 'СКАСУВАТИ';

  @override
  String get reset => 'СКИНУТИ';

  @override
  String get resetGroup => '[ СКИНУТИ ГРУПУ ]';

  @override
  String get pullToRefresh => 'ПОТЯГНІТЬ ДЛЯ ОНОВЛЕННЯ';

  @override
  String get calibrateCapacity => 'КАЛІБРУВАТИ ЄМНІСТЬ';

  @override
  String get enterKnownCapacityMah => 'ВВЕДІТЬ ВІДОМУ ЄМНІСТЬ У МАГ';

  @override
  String get calibrate => 'КАЛІБРУВАТИ';

  @override
  String get infoTab => 'ІНФО';

  @override
  String get termsOfService => 'УМОВИ ВИКОРИСТАННЯ';

  @override
  String get aboutApp => 'ПРО ПРОГРАМУ';

  @override
  String appVersion(Object version) {
    return 'Версія $version';
  }

  @override
  String get appDescription =>
      'Device Stats відстежує час роботи та запуски додатків локально. Хмарка відсутня, трекінг відсутній. Створено для Solana Mobile.';

  @override
  String get termsBody =>
      'Device Stats (\"Додаток\") надається як є без гарантій. Дані використання залишаються на вашому пристрої. Розробник не несе відповідальності за будь-які збитки. Користуючись Додатком, ви приймаєте ці умови. Повні умови на https://pipstats.pages.dev/terms';

  @override
  String get tipButton => 'ТІП';

  @override
  String get tipTitle => 'ВІДПРАВИТИ ТІП (SKR)';

  @override
  String get tipAmountHint => 'СУМА (SKR)';

  @override
  String get tipSend => 'ВІДПРАВИТИ';

  @override
  String get tipSending => 'ПІДПИС...';

  @override
  String tipSuccess(Object sig) {
    return 'ТІП ВІДПРАВЛЕНО! TX: $sig';
  }

  @override
  String tipError(Object error) {
    return 'ПОМИЛКА ТІПУ: $error';
  }

  @override
  String get tipNoWallet => 'СПОЧАТКУ ПІДКЛЮЧІТЬ ГАМАНЕЦЬ';

  @override
  String get tipInvalidAmount => 'НЕВІРНА СУМА';

  @override
  String get tipCancelled => 'ТРАНЗАКЦІЮ СКАСОВАНО';

  @override
  String get tipNoSkrAccount => 'НЕ ЗНАЙДЕНО АКАУНТУ SKR ДЛЯ ЦЬОГО ГАМАНЦЯ.';

  @override
  String get tipAuthRequired => 'ПОТРІБНА АВТОРИЗАЦІЯ MWA';

  @override
  String get tipIdentityMismatch => 'НЕВІДПОВІДНІСТЬ ІДЕНТИФІКАЦІЇ ГАМАНЦЯ';

  @override
  String get tipInsufficientSol => 'НЕДОСТАТНЬО SOL';

  @override
  String get tipInsufficientSkr => 'НЕДОСТАТНЬО SKR';

  @override
  String get aboutTitle => 'ПРО DEVICE STATS';

  @override
  String get website => 'ВЕБСАЙТ';

  @override
  String get delegationAlertTitle => '! АКТИВНІ ДОЗВОЛИ НА ТОКЕНИ';

  @override
  String delegationAlertBody(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString токен-акаунтів мають активних делегатів',
      few: '$countString токен-акаунти мають активних делегатів',
      one: '1 токен-акаунт має активного делегата',
    );
    return '$_temp0, який може витрачати ці токени без повторного запиту. Відкличте ті, яких не впізнаєте.';
  }

  @override
  String get monitoringTitle => 'МОНІТОРИНГ ПЕРЕРВАНО';

  @override
  String get monitoringStopped =>
      'Фоновий збір не працює — в історії використання та батареї будуть прогалини.';

  @override
  String get monitoringRestart => 'ПЕРЕЗАПУСТИТИ';

  @override
  String get monitoringBatteryOpt =>
      'Керування живленням Android може вбивати фоновий збір на цьому пристрої.';

  @override
  String get monitoringAllow => 'ДОЗВОЛИТИ';

  @override
  String get monitoringNoNotif =>
      'Сповіщення заблоковані, тож сповіщення моніторингу не показується.';

  @override
  String get monitoringEnableNotif => 'УВІМКНУТИ';

  @override
  String get appCharging => 'ЗАРЯДЖАЄТЬСЯ';

  @override
  String appScreenShare(String pct) {
    return '$pct% ЕКРАНУ';
  }

  @override
  String appDrainEstimate(String mah) {
    return '~$mah mAh';
  }

  @override
  String get appDrainMeasuring => 'ВИМІРЮВАННЯ';

  @override
  String periodDrainTotal(String mah) {
    return 'РОЗРЯДЖЕНО ЗА ПЕРІОД: $mah mAh';
  }

  @override
  String exportDone(String name) {
    return 'Збережено в Downloads: $name';
  }

  @override
  String get exportFailed => 'Експорт не вдався';

  @override
  String get exportNothing => 'Нема чого експортувати';

  @override
  String get searchHint => 'ФІЛЬТР ЗАСТОСУНКІВ';

  @override
  String get searchNoMatch => 'НЕМАЄ ЗБІГІВ';

  @override
  String get batteryChartTitle => 'БАТАРЕЯ';

  @override
  String get batteryChartEmpty => 'ЗБИРАЄМО ЗАМІРИ';

  @override
  String netUsage(String down, String up) {
    return '$down вх · $up вих';
  }

  @override
  String revokeAll(int count) {
    return 'ВІДКЛИКАТИ ВСІ ($count)';
  }

  @override
  String revokeAllConfirm(int count, int txs) {
    return 'Відкликати делегата на всіх $count токен-акаунтах? Це надсилається як $txs транзакцій, і кожну треба підтвердити в гаманці.';
  }

  @override
  String revokeAllDone(int count) {
    return 'Відкликано дозволів: $count';
  }

  @override
  String get batteryChartFlat => 'БЕЗ ЗМІН — НА ЗАРЯДЦІ АБО ПРОСТІЙ';
}
