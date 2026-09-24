// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'PIPSTATS';

  @override
  String get headerTitle => 'PIPSTATS';

  @override
  String get systemTab => 'SYSTEM';

  @override
  String get vaultTab => 'VAULT';

  @override
  String get sysInfoTab => 'SYSINFO';

  @override
  String get charge => 'CHARGE';

  @override
  String get uptime => 'UPTIME';

  @override
  String get batteryCapacity => 'CAPACITY';

  @override
  String get screenTime => 'SCREEN TIME';

  @override
  String refreshIn(Object seconds) {
    return 'NEXT REFRESH ${seconds}s';
  }

  @override
  String get deviceInfoLoadFailed => 'FAILED TO LOAD DEVICE INFO';

  @override
  String get periodDay => 'Day';

  @override
  String get periodWeek => 'Week';

  @override
  String get periodMonth => 'Month';

  @override
  String get periodAll => 'All time';

  @override
  String get applicationsHeader => '[ APPLICATIONS ]';

  @override
  String get sortTime => 'TIME';

  @override
  String get sortLaunch => 'LAUNCH';

  @override
  String get noDataYet => 'NO DATA YET';

  @override
  String get shortHistory =>
      'NO ACCUMULATED HISTORY BEFORE THIS PERIOD — data builds up over time';

  @override
  String get appInfo => 'APP INFO';

  @override
  String get resetStats => 'RESET STATS';

  @override
  String get usageAccessRequired => 'USAGE ACCESS REQUIRED';

  @override
  String get grantAccessHint =>
      'Grant it in:\nSettings > Special access > Usage statistics';

  @override
  String get grantAccess => 'GRANT ACCESS';

  @override
  String get seedVault => '[ SEED VAULT ]';

  @override
  String get connectSeedVault => 'CONNECT SEED VAULT OR ENTER ADDRESS';

  @override
  String get connectSeedVaultBtn => 'CONNECT (SEED VAULT)';

  @override
  String get addressHint => 'base58 address or name.skr';

  @override
  String get scanWallet => 'SCAN WALLET';

  @override
  String get rescan => 'RESCAN';

  @override
  String get remove => 'REMOVE';

  @override
  String addrLabel(Object address) {
    return 'ADDR: $address';
  }

  @override
  String walletLabel(Object label) {
    return 'LABEL: $label';
  }

  @override
  String solBalance(Object balance) {
    return 'SOL BALANCE: $balance';
  }

  @override
  String estValue(Object amount) {
    return 'EST. VALUE: ~\$$amount';
  }

  @override
  String get pricesUnavailable => 'PRICES UNAVAILABLE';

  @override
  String get metadataUnavailable =>
      'TOKEN/NFT METADATA UNAVAILABLE (NO HELIUS KEY)';

  @override
  String get delegations => '[ DELEGATIONS ]';

  @override
  String get tabDelegations => 'DELEG';

  @override
  String get tabTokens => 'TOKENS';

  @override
  String get tabNfts => 'NFT';

  @override
  String get tabTx => 'TX';

  @override
  String get connectWalletToScan => 'CONNECT WALLET TO SCAN';

  @override
  String get scanning => 'SCANNING...';

  @override
  String get noActiveDelegations => 'NO ACTIVE DELEGATIONS FOUND';

  @override
  String accountLabel(Object account) {
    return 'ACCOUNT: $account';
  }

  @override
  String mintLabel(Object mint) {
    return 'MINT: $mint';
  }

  @override
  String delegateLabel(Object delegate) {
    return 'DELEGATE: $delegate';
  }

  @override
  String approvedAmountLabel(Object amount) {
    return 'APPROVED AMOUNT: $amount';
  }

  @override
  String get revoke => 'REVOKE';

  @override
  String get pleaseWait => 'PLEASE WAIT...';

  @override
  String get closeAuthority => '[ CLOSE AUTHORITY ]';

  @override
  String get noCloseAuthorityRisks => 'NO CLOSE AUTHORITY RISKS';

  @override
  String closeAuthorityLabel(Object authority) {
    return 'CLOSE AUTHORITY: $authority';
  }

  @override
  String get closeAuthorityWarning =>
      'The close authority can burn and close this account.';

  @override
  String get tokens => '[ TOKENS ]';

  @override
  String get noTokens => 'NO TOKENS';

  @override
  String get nfts => '[ NFTS ]';

  @override
  String get noNfts => 'NO NFTS';

  @override
  String get unnamed => 'UNNAMED';

  @override
  String moreCount(Object count) {
    return '… +$count more';
  }

  @override
  String spamHidden(Object count) {
    return '$count spam/burnt NFT(s) hidden';
  }

  @override
  String get transactions => '[ TRANSACTIONS ]';

  @override
  String get noTransactions => 'NO TRANSACTIONS';

  @override
  String get statusOk => 'OK';

  @override
  String get statusFailed => 'FAILED';

  @override
  String txStatusSig(Object status, Object sig) {
    return '[$status] $sig';
  }

  @override
  String txSlot(Object slot) {
    return 'slot $slot';
  }

  @override
  String feeSol(Object fee) {
    return 'FEE: $fee SOL';
  }

  @override
  String protoLabel(Object programs) {
    return 'PROTO: $programs';
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
  String get timeJustNow => 'just now';

  @override
  String timeMinutesAgo(Object minutes) {
    return '${minutes}m ago';
  }

  @override
  String timeHoursAgo(Object hours) {
    return '${hours}h ago';
  }

  @override
  String timeDaysAgo(Object days) {
    return '${days}d ago';
  }

  @override
  String get revokeSection => '[ REVOKE ] *';

  @override
  String get revokeClearsHint => '* REVOKE CLEARS A TOKEN ACCOUNT DELEGATE.';

  @override
  String get revokeDisclaimer =>
      'Each delegation listed above has a REVOKE button. Signing happens in Seed Vault (double-tap). The developer is not responsible for any action you take here. Proceed at your own risk.';

  @override
  String revokedOk(Object sig) {
    return 'REVOKED OK — tx: $sig';
  }

  @override
  String revokeError(Object error) {
    return 'REVOKE ERROR: $error';
  }

  @override
  String scanError(Object error) {
    return 'SCAN ERROR: $error';
  }

  @override
  String authError(Object error) {
    return 'AUTH ERROR: $error';
  }

  @override
  String get seedVaultUnavailable => 'SEED VAULT UNAVAILABLE OR CANCELLED';

  @override
  String get domainNotFound => 'DOMAIN NOT FOUND';

  @override
  String get invalidAddress => 'INVALID ADDRESS — must be a base58 pubkey';

  @override
  String get privacy => '[ PRIVACY ]';

  @override
  String get tapToView => 'TAP TO VIEW >';

  @override
  String get privacyPolicy => 'PRIVACY POLICY';

  @override
  String get privacyBody =>
      'Device Stats keeps your data on-device. Usage statistics are stored only in a local database. When you connect a wallet, the app performs read-only queries to public Solana APIs using your public address. Private keys and seed phrases never leave the secure Seed Vault. No personal data is sold or shared. See PRIVACY.md for the full policy.';

  @override
  String get close => 'CLOSE';

  @override
  String get cancel => 'CANCEL';

  @override
  String get reset => 'RESET';

  @override
  String get resetGroup => '[ RESET GROUP ]';

  @override
  String get pullToRefresh => 'PULL TO REFRESH';

  @override
  String get calibrateCapacity => 'CALIBRATE CAPACITY';

  @override
  String get enterKnownCapacityMah => 'ENTER KNOWN CAPACITY IN MAH';

  @override
  String get calibrate => 'CALIBRATE';

  @override
  String get infoTab => 'INFO';

  @override
  String get termsOfService => 'TERMS OF SERVICE';

  @override
  String get aboutApp => 'ABOUT';

  @override
  String appVersion(Object version) {
    return 'Version $version';
  }

  @override
  String get appDescription =>
      'Device Stats tracks app foreground time and launch counts locally. No cloud, no tracking. Built for Solana Mobile.';

  @override
  String get termsBody =>
      'Device Stats (\"the App\") is provided as-is without warranty. Usage data stays on your device. The developer is not liable for any damages. By using the App, you accept these terms. Full terms at https://pipstats.pages.dev/terms';

  @override
  String get tipButton => 'TIP';

  @override
  String get tipTitle => 'SEND TIP (SKR)';

  @override
  String get tipAmountHint => 'AMOUNT (SKR)';

  @override
  String get tipSend => 'SEND';

  @override
  String get tipSending => 'SIGNING...';

  @override
  String tipSuccess(Object sig) {
    return 'TIP SENT! TX: $sig';
  }

  @override
  String tipError(Object error) {
    return 'TIP FAILED: $error';
  }

  @override
  String get tipNoWallet => 'CONNECT WALLET FIRST';

  @override
  String get tipInvalidAmount => 'INVALID AMOUNT';

  @override
  String get tipCancelled => 'TRANSACTION CANCELLED';

  @override
  String get tipNoSkrAccount => 'NO SKR ACCOUNT FOUND FOR THIS WALLET.';

  @override
  String get tipAuthRequired => 'MWA AUTHORIZATION REQUIRED';

  @override
  String get tipIdentityMismatch => 'WALLET IDENTITY MISMATCH';

  @override
  String get tipInsufficientSol => 'INSUFFICIENT SOL BALANCE';

  @override
  String get tipInsufficientSkr => 'INSUFFICIENT SKR BALANCE';

  @override
  String get aboutTitle => 'ABOUT DEVICE STATS';

  @override
  String get website => 'WEBSITE';

  @override
  String get delegationAlertTitle => '! ACTIVE TOKEN APPROVALS';

  @override
  String delegationAlertBody(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString token accounts have active delegates',
      one: '1 token account has an active delegate',
    );
    return '$_temp0 that can spend those tokens without asking again. Revoke any you do not recognise.';
  }

  @override
  String get monitoringTitle => 'MONITORING INTERRUPTED';

  @override
  String get monitoringStopped =>
      'Background collection is not running — usage and battery history will have gaps.';

  @override
  String get monitoringRestart => 'RESTART';

  @override
  String get monitoringBatteryOpt =>
      'Android power management may kill background collection on this device.';

  @override
  String get monitoringAllow => 'ALLOW';

  @override
  String get monitoringNoNotif =>
      'Notifications are blocked, so the monitoring notification cannot be shown.';

  @override
  String get monitoringEnableNotif => 'ENABLE';

  @override
  String get appCharging => 'CHARGING';

  @override
  String appScreenShare(String pct) {
    return '$pct% SCREEN';
  }

  @override
  String appDrainEstimate(String mah) {
    return '~$mah mAh';
  }

  @override
  String get appDrainMeasuring => 'MEASURING';

  @override
  String periodDrainTotal(String mah) {
    return 'DISCHARGED THIS PERIOD: $mah mAh';
  }

  @override
  String exportDone(String name) {
    return 'Saved to Downloads: $name';
  }

  @override
  String get exportFailed => 'Export failed';

  @override
  String get exportNothing => 'Nothing to export';

  @override
  String get searchHint => 'FILTER APPS';

  @override
  String get searchNoMatch => 'NO MATCHES';

  @override
  String get batteryChartTitle => 'BATTERY';

  @override
  String get batteryChartEmpty => 'COLLECTING SAMPLES';

  @override
  String netUsage(String down, String up) {
    return '$down down · $up up';
  }

  @override
  String revokeAll(int count) {
    return 'REVOKE ALL ($count)';
  }

  @override
  String revokeAllConfirm(int count, int txs) {
    return 'Revoke the delegate on all $count token accounts? This is sent as $txs transaction(s) and each must be approved in the wallet.';
  }

  @override
  String revokeAllDone(int count) {
    return 'Revoked $count approvals';
  }

  @override
  String get batteryChartFlat => 'NO CHANGE — ON CHARGER OR IDLE';

  @override
  String get approvalAlarmTitle => '! TOKEN SPENDING APPROVALS';

  @override
  String approvalAlarmBody(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString token accounts have active delegates',
      one: '1 token account has an active delegate',
    );
    return '$_temp0 that can move those tokens without asking again.';
  }

  @override
  String get approvalAlarmAction => 'REVIEW';
}
