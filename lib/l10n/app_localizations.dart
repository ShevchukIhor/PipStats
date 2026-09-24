import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_uk.dart';

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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('en'),
    Locale('uk'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'PIPSTATS'**
  String get appTitle;

  /// No description provided for @headerTitle.
  ///
  /// In en, this message translates to:
  /// **'PIPSTATS'**
  String get headerTitle;

  /// No description provided for @systemTab.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM'**
  String get systemTab;

  /// No description provided for @vaultTab.
  ///
  /// In en, this message translates to:
  /// **'VAULT'**
  String get vaultTab;

  /// No description provided for @sysInfoTab.
  ///
  /// In en, this message translates to:
  /// **'SYSINFO'**
  String get sysInfoTab;

  /// No description provided for @charge.
  ///
  /// In en, this message translates to:
  /// **'CHARGE'**
  String get charge;

  /// No description provided for @uptime.
  ///
  /// In en, this message translates to:
  /// **'UPTIME'**
  String get uptime;

  /// No description provided for @batteryCapacity.
  ///
  /// In en, this message translates to:
  /// **'CAPACITY'**
  String get batteryCapacity;

  /// No description provided for @screenTime.
  ///
  /// In en, this message translates to:
  /// **'SCREEN TIME'**
  String get screenTime;

  /// No description provided for @refreshIn.
  ///
  /// In en, this message translates to:
  /// **'NEXT REFRESH {seconds}s'**
  String refreshIn(Object seconds);

  /// No description provided for @deviceInfoLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'FAILED TO LOAD DEVICE INFO'**
  String get deviceInfoLoadFailed;

  /// No description provided for @periodDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get periodDay;

  /// No description provided for @periodWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get periodWeek;

  /// No description provided for @periodMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get periodMonth;

  /// No description provided for @periodAll.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get periodAll;

  /// No description provided for @applicationsHeader.
  ///
  /// In en, this message translates to:
  /// **'[ APPLICATIONS ]'**
  String get applicationsHeader;

  /// No description provided for @sortTime.
  ///
  /// In en, this message translates to:
  /// **'TIME'**
  String get sortTime;

  /// No description provided for @sortLaunch.
  ///
  /// In en, this message translates to:
  /// **'LAUNCH'**
  String get sortLaunch;

  /// No description provided for @noDataYet.
  ///
  /// In en, this message translates to:
  /// **'NO DATA YET'**
  String get noDataYet;

  /// Hint shown when a period predates the locally accumulated usage history
  ///
  /// In en, this message translates to:
  /// **'NO ACCUMULATED HISTORY BEFORE THIS PERIOD — data builds up over time'**
  String get shortHistory;

  /// No description provided for @appInfo.
  ///
  /// In en, this message translates to:
  /// **'APP INFO'**
  String get appInfo;

  /// No description provided for @resetStats.
  ///
  /// In en, this message translates to:
  /// **'RESET STATS'**
  String get resetStats;

  /// No description provided for @usageAccessRequired.
  ///
  /// In en, this message translates to:
  /// **'USAGE ACCESS REQUIRED'**
  String get usageAccessRequired;

  /// No description provided for @grantAccessHint.
  ///
  /// In en, this message translates to:
  /// **'Grant it in:\nSettings > Special access > Usage statistics'**
  String get grantAccessHint;

  /// No description provided for @grantAccess.
  ///
  /// In en, this message translates to:
  /// **'GRANT ACCESS'**
  String get grantAccess;

  /// No description provided for @seedVault.
  ///
  /// In en, this message translates to:
  /// **'[ SEED VAULT ]'**
  String get seedVault;

  /// No description provided for @connectSeedVault.
  ///
  /// In en, this message translates to:
  /// **'CONNECT SEED VAULT OR ENTER ADDRESS'**
  String get connectSeedVault;

  /// No description provided for @connectSeedVaultBtn.
  ///
  /// In en, this message translates to:
  /// **'CONNECT (SEED VAULT)'**
  String get connectSeedVaultBtn;

  /// No description provided for @addressHint.
  ///
  /// In en, this message translates to:
  /// **'base58 address or name.skr'**
  String get addressHint;

  /// No description provided for @scanWallet.
  ///
  /// In en, this message translates to:
  /// **'SCAN WALLET'**
  String get scanWallet;

  /// No description provided for @rescan.
  ///
  /// In en, this message translates to:
  /// **'RESCAN'**
  String get rescan;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'REMOVE'**
  String get remove;

  /// No description provided for @addrLabel.
  ///
  /// In en, this message translates to:
  /// **'ADDR: {address}'**
  String addrLabel(Object address);

  /// No description provided for @walletLabel.
  ///
  /// In en, this message translates to:
  /// **'LABEL: {label}'**
  String walletLabel(Object label);

  /// No description provided for @solBalance.
  ///
  /// In en, this message translates to:
  /// **'SOL BALANCE: {balance}'**
  String solBalance(Object balance);

  /// No description provided for @estValue.
  ///
  /// In en, this message translates to:
  /// **'EST. VALUE: ~\${amount}'**
  String estValue(Object amount);

  /// No description provided for @pricesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'PRICES UNAVAILABLE'**
  String get pricesUnavailable;

  /// No description provided for @metadataUnavailable.
  ///
  /// In en, this message translates to:
  /// **'TOKEN/NFT METADATA UNAVAILABLE (NO HELIUS KEY)'**
  String get metadataUnavailable;

  /// No description provided for @delegations.
  ///
  /// In en, this message translates to:
  /// **'[ DELEGATIONS ]'**
  String get delegations;

  /// No description provided for @tabDelegations.
  ///
  /// In en, this message translates to:
  /// **'DELEG'**
  String get tabDelegations;

  /// No description provided for @tabTokens.
  ///
  /// In en, this message translates to:
  /// **'TOKENS'**
  String get tabTokens;

  /// No description provided for @tabNfts.
  ///
  /// In en, this message translates to:
  /// **'NFT'**
  String get tabNfts;

  /// No description provided for @tabTx.
  ///
  /// In en, this message translates to:
  /// **'TX'**
  String get tabTx;

  /// No description provided for @connectWalletToScan.
  ///
  /// In en, this message translates to:
  /// **'CONNECT WALLET TO SCAN'**
  String get connectWalletToScan;

  /// No description provided for @scanning.
  ///
  /// In en, this message translates to:
  /// **'SCANNING...'**
  String get scanning;

  /// No description provided for @noActiveDelegations.
  ///
  /// In en, this message translates to:
  /// **'NO ACTIVE DELEGATIONS FOUND'**
  String get noActiveDelegations;

  /// No description provided for @accountLabel.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT: {account}'**
  String accountLabel(Object account);

  /// No description provided for @mintLabel.
  ///
  /// In en, this message translates to:
  /// **'MINT: {mint}'**
  String mintLabel(Object mint);

  /// No description provided for @delegateLabel.
  ///
  /// In en, this message translates to:
  /// **'DELEGATE: {delegate}'**
  String delegateLabel(Object delegate);

  /// No description provided for @approvedAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'APPROVED AMOUNT: {amount}'**
  String approvedAmountLabel(Object amount);

  /// No description provided for @revoke.
  ///
  /// In en, this message translates to:
  /// **'REVOKE'**
  String get revoke;

  /// No description provided for @pleaseWait.
  ///
  /// In en, this message translates to:
  /// **'PLEASE WAIT...'**
  String get pleaseWait;

  /// No description provided for @closeAuthority.
  ///
  /// In en, this message translates to:
  /// **'[ CLOSE AUTHORITY ]'**
  String get closeAuthority;

  /// No description provided for @noCloseAuthorityRisks.
  ///
  /// In en, this message translates to:
  /// **'NO CLOSE AUTHORITY RISKS'**
  String get noCloseAuthorityRisks;

  /// No description provided for @closeAuthorityLabel.
  ///
  /// In en, this message translates to:
  /// **'CLOSE AUTHORITY: {authority}'**
  String closeAuthorityLabel(Object authority);

  /// No description provided for @closeAuthorityWarning.
  ///
  /// In en, this message translates to:
  /// **'The close authority can burn and close this account.'**
  String get closeAuthorityWarning;

  /// No description provided for @tokens.
  ///
  /// In en, this message translates to:
  /// **'[ TOKENS ]'**
  String get tokens;

  /// No description provided for @noTokens.
  ///
  /// In en, this message translates to:
  /// **'NO TOKENS'**
  String get noTokens;

  /// No description provided for @nfts.
  ///
  /// In en, this message translates to:
  /// **'[ NFTS ]'**
  String get nfts;

  /// No description provided for @noNfts.
  ///
  /// In en, this message translates to:
  /// **'NO NFTS'**
  String get noNfts;

  /// No description provided for @unnamed.
  ///
  /// In en, this message translates to:
  /// **'UNNAMED'**
  String get unnamed;

  /// No description provided for @moreCount.
  ///
  /// In en, this message translates to:
  /// **'… +{count} more'**
  String moreCount(Object count);

  /// No description provided for @spamHidden.
  ///
  /// In en, this message translates to:
  /// **'{count} spam/burnt NFT(s) hidden'**
  String spamHidden(Object count);

  /// No description provided for @transactions.
  ///
  /// In en, this message translates to:
  /// **'[ TRANSACTIONS ]'**
  String get transactions;

  /// No description provided for @noTransactions.
  ///
  /// In en, this message translates to:
  /// **'NO TRANSACTIONS'**
  String get noTransactions;

  /// No description provided for @statusOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get statusOk;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'FAILED'**
  String get statusFailed;

  /// No description provided for @txStatusSig.
  ///
  /// In en, this message translates to:
  /// **'[{status}] {sig}'**
  String txStatusSig(Object status, Object sig);

  /// No description provided for @txSlot.
  ///
  /// In en, this message translates to:
  /// **'slot {slot}'**
  String txSlot(Object slot);

  /// No description provided for @feeSol.
  ///
  /// In en, this message translates to:
  /// **'FEE: {fee} SOL'**
  String feeSol(Object fee);

  /// No description provided for @protoLabel.
  ///
  /// In en, this message translates to:
  /// **'PROTO: {programs}'**
  String protoLabel(Object programs);

  /// No description provided for @solTransfer.
  ///
  /// In en, this message translates to:
  /// **'-> {dest}  ({sol} SOL)'**
  String solTransfer(Object dest, Object sol);

  /// No description provided for @tokenTransfer.
  ///
  /// In en, this message translates to:
  /// **'-> {dest}  ({amount} raw)'**
  String tokenTransfer(Object dest, Object amount);

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String timeMinutesAgo(Object minutes);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String timeHoursAgo(Object hours);

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String timeDaysAgo(Object days);

  /// No description provided for @revokeSection.
  ///
  /// In en, this message translates to:
  /// **'[ REVOKE ] *'**
  String get revokeSection;

  /// No description provided for @revokeClearsHint.
  ///
  /// In en, this message translates to:
  /// **'* REVOKE CLEARS A TOKEN ACCOUNT DELEGATE.'**
  String get revokeClearsHint;

  /// No description provided for @revokeDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Each delegation listed above has a REVOKE button. Signing happens in Seed Vault (double-tap). The developer is not responsible for any action you take here. Proceed at your own risk.'**
  String get revokeDisclaimer;

  /// No description provided for @revokedOk.
  ///
  /// In en, this message translates to:
  /// **'REVOKED OK — tx: {sig}'**
  String revokedOk(Object sig);

  /// No description provided for @revokeError.
  ///
  /// In en, this message translates to:
  /// **'REVOKE ERROR: {error}'**
  String revokeError(Object error);

  /// No description provided for @scanError.
  ///
  /// In en, this message translates to:
  /// **'SCAN ERROR: {error}'**
  String scanError(Object error);

  /// No description provided for @authError.
  ///
  /// In en, this message translates to:
  /// **'AUTH ERROR: {error}'**
  String authError(Object error);

  /// No description provided for @seedVaultUnavailable.
  ///
  /// In en, this message translates to:
  /// **'SEED VAULT UNAVAILABLE OR CANCELLED'**
  String get seedVaultUnavailable;

  /// No description provided for @domainNotFound.
  ///
  /// In en, this message translates to:
  /// **'DOMAIN NOT FOUND'**
  String get domainNotFound;

  /// No description provided for @invalidAddress.
  ///
  /// In en, this message translates to:
  /// **'INVALID ADDRESS — must be a base58 pubkey'**
  String get invalidAddress;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'[ PRIVACY ]'**
  String get privacy;

  /// No description provided for @tapToView.
  ///
  /// In en, this message translates to:
  /// **'TAP TO VIEW >'**
  String get tapToView;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'PRIVACY POLICY'**
  String get privacyPolicy;

  /// No description provided for @privacyBody.
  ///
  /// In en, this message translates to:
  /// **'Device Stats keeps your data on-device. Usage statistics are stored only in a local database. When you connect a wallet, the app performs read-only queries to public Solana APIs using your public address. Private keys and seed phrases never leave the secure Seed Vault. No personal data is sold or shared. See PRIVACY.md for the full policy.'**
  String get privacyBody;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'CLOSE'**
  String get close;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get cancel;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'RESET'**
  String get reset;

  /// No description provided for @resetGroup.
  ///
  /// In en, this message translates to:
  /// **'[ RESET GROUP ]'**
  String get resetGroup;

  /// No description provided for @pullToRefresh.
  ///
  /// In en, this message translates to:
  /// **'PULL TO REFRESH'**
  String get pullToRefresh;

  /// No description provided for @calibrateCapacity.
  ///
  /// In en, this message translates to:
  /// **'CALIBRATE CAPACITY'**
  String get calibrateCapacity;

  /// No description provided for @enterKnownCapacityMah.
  ///
  /// In en, this message translates to:
  /// **'ENTER KNOWN CAPACITY IN MAH'**
  String get enterKnownCapacityMah;

  /// No description provided for @calibrate.
  ///
  /// In en, this message translates to:
  /// **'CALIBRATE'**
  String get calibrate;

  /// No description provided for @infoTab.
  ///
  /// In en, this message translates to:
  /// **'INFO'**
  String get infoTab;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'TERMS OF SERVICE'**
  String get termsOfService;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get aboutApp;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String appVersion(Object version);

  /// No description provided for @appDescription.
  ///
  /// In en, this message translates to:
  /// **'Device Stats tracks app foreground time and launch counts locally. No cloud, no tracking. Built for Solana Mobile.'**
  String get appDescription;

  /// No description provided for @termsBody.
  ///
  /// In en, this message translates to:
  /// **'Device Stats (\"the App\") is provided as-is without warranty. Usage data stays on your device. The developer is not liable for any damages. By using the App, you accept these terms. Full terms at https://pipstats.pages.dev/terms'**
  String get termsBody;

  /// No description provided for @tipButton.
  ///
  /// In en, this message translates to:
  /// **'TIP'**
  String get tipButton;

  /// No description provided for @tipTitle.
  ///
  /// In en, this message translates to:
  /// **'SEND TIP (SKR)'**
  String get tipTitle;

  /// No description provided for @tipAmountHint.
  ///
  /// In en, this message translates to:
  /// **'AMOUNT (SKR)'**
  String get tipAmountHint;

  /// No description provided for @tipSend.
  ///
  /// In en, this message translates to:
  /// **'SEND'**
  String get tipSend;

  /// No description provided for @tipSending.
  ///
  /// In en, this message translates to:
  /// **'SIGNING...'**
  String get tipSending;

  /// No description provided for @tipSuccess.
  ///
  /// In en, this message translates to:
  /// **'TIP SENT! TX: {sig}'**
  String tipSuccess(Object sig);

  /// No description provided for @tipError.
  ///
  /// In en, this message translates to:
  /// **'TIP FAILED: {error}'**
  String tipError(Object error);

  /// No description provided for @tipNoWallet.
  ///
  /// In en, this message translates to:
  /// **'CONNECT WALLET FIRST'**
  String get tipNoWallet;

  /// No description provided for @tipInvalidAmount.
  ///
  /// In en, this message translates to:
  /// **'INVALID AMOUNT'**
  String get tipInvalidAmount;

  /// No description provided for @tipCancelled.
  ///
  /// In en, this message translates to:
  /// **'TRANSACTION CANCELLED'**
  String get tipCancelled;

  /// No description provided for @tipNoSkrAccount.
  ///
  /// In en, this message translates to:
  /// **'NO SKR ACCOUNT FOUND FOR THIS WALLET.'**
  String get tipNoSkrAccount;

  /// No description provided for @tipAuthRequired.
  ///
  /// In en, this message translates to:
  /// **'MWA AUTHORIZATION REQUIRED'**
  String get tipAuthRequired;

  /// No description provided for @tipIdentityMismatch.
  ///
  /// In en, this message translates to:
  /// **'WALLET IDENTITY MISMATCH'**
  String get tipIdentityMismatch;

  /// No description provided for @tipInsufficientSol.
  ///
  /// In en, this message translates to:
  /// **'INSUFFICIENT SOL BALANCE'**
  String get tipInsufficientSol;

  /// No description provided for @tipInsufficientSkr.
  ///
  /// In en, this message translates to:
  /// **'INSUFFICIENT SKR BALANCE'**
  String get tipInsufficientSkr;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'ABOUT DEVICE STATS'**
  String get aboutTitle;

  /// No description provided for @website.
  ///
  /// In en, this message translates to:
  /// **'WEBSITE'**
  String get website;

  /// No description provided for @delegationAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'! ACTIVE TOKEN APPROVALS'**
  String get delegationAlertTitle;

  /// No description provided for @delegationAlertBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 token account has an active delegate} other{{count} token accounts have active delegates}} that can spend those tokens without asking again. Revoke any you do not recognise.'**
  String delegationAlertBody(num count);

  /// No description provided for @monitoringTitle.
  ///
  /// In en, this message translates to:
  /// **'MONITORING INTERRUPTED'**
  String get monitoringTitle;

  /// No description provided for @monitoringStopped.
  ///
  /// In en, this message translates to:
  /// **'Background collection is not running — usage and battery history will have gaps.'**
  String get monitoringStopped;

  /// No description provided for @monitoringRestart.
  ///
  /// In en, this message translates to:
  /// **'RESTART'**
  String get monitoringRestart;

  /// No description provided for @monitoringBatteryOpt.
  ///
  /// In en, this message translates to:
  /// **'Android power management may kill background collection on this device.'**
  String get monitoringBatteryOpt;

  /// No description provided for @monitoringAllow.
  ///
  /// In en, this message translates to:
  /// **'ALLOW'**
  String get monitoringAllow;

  /// No description provided for @monitoringNoNotif.
  ///
  /// In en, this message translates to:
  /// **'Notifications are blocked, so the monitoring notification cannot be shown.'**
  String get monitoringNoNotif;

  /// No description provided for @monitoringEnableNotif.
  ///
  /// In en, this message translates to:
  /// **'ENABLE'**
  String get monitoringEnableNotif;

  /// No description provided for @appCharging.
  ///
  /// In en, this message translates to:
  /// **'CHARGING'**
  String get appCharging;

  /// No description provided for @appScreenShare.
  ///
  /// In en, this message translates to:
  /// **'{pct}% SCREEN'**
  String appScreenShare(String pct);

  /// No description provided for @appDrainEstimate.
  ///
  /// In en, this message translates to:
  /// **'~{mah} mAh'**
  String appDrainEstimate(String mah);

  /// No description provided for @appDrainMeasuring.
  ///
  /// In en, this message translates to:
  /// **'MEASURING'**
  String get appDrainMeasuring;

  /// No description provided for @periodDrainTotal.
  ///
  /// In en, this message translates to:
  /// **'DISCHARGED THIS PERIOD: {mah} mAh'**
  String periodDrainTotal(String mah);

  /// No description provided for @exportDone.
  ///
  /// In en, this message translates to:
  /// **'Saved to Downloads: {name}'**
  String exportDone(String name);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailed;

  /// No description provided for @exportNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to export'**
  String get exportNothing;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'FILTER APPS'**
  String get searchHint;

  /// No description provided for @searchNoMatch.
  ///
  /// In en, this message translates to:
  /// **'NO MATCHES'**
  String get searchNoMatch;
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
      <String>['en', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
