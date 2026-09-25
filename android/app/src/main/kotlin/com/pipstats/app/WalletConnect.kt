package com.pipstats.app

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.activity.ComponentActivity
import com.solana.mobilewalletadapter.clientlib.ActivityResultSender
import com.solana.mobilewalletadapter.clientlib.ConnectionIdentity
import com.solana.mobilewalletadapter.clientlib.MobileWalletAdapter
import com.solana.mobilewalletadapter.clientlib.Solana
import com.solana.mobilewalletadapter.clientlib.TransactionResult
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Seed Vault (Mobile Wallet Adapter) connect via the official Kotlin clientlib.
 *
 * IMPORTANT: ActivityResultSender must be created (registerForActivityResult)
 * before the activity reaches STARTED/RESUMED. We attach it in
 * configureFlutterEngine (pre-STARTED) so the launcher registration is legal.
 */
object WalletConnect {

  private const val TAG = "WalletConnect"
  private const val PREFS = "wallet_auth"
  private const val KEY_PUBKEY = "pubkey"
  private const val KEY_LABEL = "label"

  private val walletAdapter = MobileWalletAdapter(
    connectionIdentity = ConnectionIdentity(
      // Must be an origin the wallet can actually fetch: it reads
      // /.well-known/assetlinks.json there to verify this dApp, and shows it
      // as unverified otherwise.
      //
      // pip-boy.skr is the project's AllDomains name and resolves on-chain to
      // the tip recipient, but .skr is a Solana name service TLD rather than
      // DNS, so it answers nothing over HTTPS and cannot serve that file.
      identityUri = Uri.parse("https://pipstats.pages.dev"),
      // Resolved relative to identityUri. /icon.png does not exist on that
      // host — the Pages SPA fallback answers 200 with HTML for any missing
      // path, which is why a wrong value here fails silently.
      iconUri = Uri.parse("assets/icon-192.png"),
      identityName = "PipStats",
    ),
  ).apply {
    // MobileWalletAdapter defaults to Solana.Devnet (verified in the 2.2.0
    // clientlib bytecode: the constructor stores Solana$Devnet.INSTANCE).
    // The session must be authorized on mainnet or the wallet rejects every
    // mainnet transaction as "Invalid Transaction" — this applies to both the
    // tip and the revoke path, since each goes through `transact`.
    blockchain = Solana.Mainnet
  }

  @Volatile
  private var sender: ActivityResultSender? = null

  @Volatile
  private var host: ComponentActivity? = null

  /** Cancelled in [detach], so no wallet call outlives its activity. */
  @Volatile
  private var scope: CoroutineScope? = null

  /**
   * Called from configureFlutterEngine — before the activity is STARTED.
   *
   * The sender is rebuilt for every activity instance. Keeping the first one
   * (the previous `if (sender == null)`) leaked the activity across
   * recreation — rotation, theme/locale change, process death with restore —
   * and left a dead `registerForActivityResult` launcher, so the wallet either
   * never opened or its result never came back.
   */
  fun attach(activity: ComponentActivity) {
    if (host === activity && sender != null) return
    scope?.cancel()
    host = activity
    sender = ActivityResultSender(activity)
    scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
  }

  /**
   * Drop the activity reference and cancel any in-flight wallet call.
   *
   * Without this the coroutines outlived the activity and could reply into a
   * detached Flutter engine.
   */
  fun detach(activity: ComponentActivity) {
    if (host === activity) {
      scope?.cancel()
      scope = null
      host = null
      sender = null
    }
  }

  /**
   * Runs [block] on the attached activity's scope so the coroutine is
   * cancelled with the activity instead of outliving it, and reports failures
   * through [result] exactly once.
   */
  private fun launchOnActivity(
    activity: ComponentActivity,
    result: MethodChannel.Result,
    errorCode: String,
    block: suspend (ActivityResultSender) -> Unit,
  ) {
    if (host !== activity || sender == null || scope == null) attach(activity)
    val s = sender ?: return runCatching {
      result.error(errorCode, "wallet launcher unavailable", null)
    }.let {}
    scope!!.launch {
      try {
        block(s)
      } catch (e: Exception) {
        Log.e(TAG, "$errorCode", e)
        // The engine may already be gone; replying twice throws.
        runCatching { result.error(errorCode, e.message ?: e.toString(), null) }
      }
    }
  }

  private fun prefs(context: Context) =
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

  /**
   * A previously-persisted wallet (address + label) if any, else null.
   * This is used only to display the last connected address on app start.
   * It never feeds an auth token back into the adapter, so an explicit
   * CONNECT always triggers a fresh authorize (never a stale reauthorize).
   */
  fun saved(context: Context): Map<String, Any?>? {
    val sp = prefs(context)
    val pubkey = sp.getString(KEY_PUBKEY, null) ?: return null
    val bytes = pubkey.split(",").mapNotNull { it.toIntOrNull() }
    if (bytes.size < 32) return null
    return mapOf(
      "pubkey_bytes" to bytes,
      "label" to sp.getString(KEY_LABEL, null),
    )
  }

  private fun persist(context: Context, pubkey: ByteArray?, label: String?) {
    if (pubkey == null) return
    prefs(context).edit()
        .putString(KEY_PUBKEY, pubkey.joinToString(",") { (it.toInt() and 0xFF).toString() })
        .putString(KEY_LABEL, label ?: "")
        .apply()
  }

  private fun clear(context: Context) {
    prefs(context).edit().clear().apply()
  }

  fun authorize(activity: ComponentActivity, result: MethodChannel.Result) {
    launchOnActivity(activity, result, "AUTH_EXCEPTION") { s ->
      when (val txResult = walletAdapter.transact(s) { it.accounts.firstOrNull()?.publicKey }) {
        is TransactionResult.Success -> {
          val pubkey: ByteArray? = txResult.payload
          if (pubkey == null) {
            Log.w(TAG, "auth success but null account")
            runCatching { result.success(null) }
          } else {
            val acct = txResult.authResult.accounts.firstOrNull()
            persist(activity, pubkey, acct?.accountLabel)
            runCatching {
              result.success(
                mapOf(
                  "pubkey_bytes" to pubkey.map { it.toInt() and 0xFF },
                  "label" to acct?.accountLabel,
                ),
              )
            }
          }
        }
        is TransactionResult.NoWalletFound -> {
          Log.w(TAG, "no wallet: ${txResult.message}")
          runCatching { result.error("NO_WALLET", txResult.message, null) }
        }
        is TransactionResult.Failure -> {
          Log.w(TAG, "auth failure: ${txResult.message}", txResult.e)
          runCatching {
            result.error("AUTH_FAILED", "${txResult.message}: ${txResult.e.message}", null)
          }
        }
      }
    }
  }

  /** Persist a wallet address (used after Dart-side plugin authorize). */
  fun persistWallet(context: Context, pubkey: ByteArray, label: String?) {
    persist(context, pubkey, label)
  }

  /** Clear the persisted wallet address. */
  fun clearWallet(context: Context) {
    clear(context)
  }

  /** Revoke authorization and clear any persisted session. */
  fun deauthorize(activity: ComponentActivity, result: MethodChannel.Result) {
    launchOnActivity(activity, result, "DEAUTH_EXCEPTION") { s ->
      try {
        walletAdapter.disconnect(s)
      } catch (_: Exception) {
        // ignore — local state is cleared regardless
      } finally {
        clear(activity)
        runCatching { result.success(true) }
      }
    }
  }

  /**
   * Sign and submit a serialized transaction via Seed Vault.
   *
   * [transactionBytes] is a full transaction in wire format: a compact-u16
   * signature count, that many zeroed signature slots, then the message. The
   * wallet fills the signatures in. A bare message is rejected as
   * "Invalid transaction - not properly formed".
   *
   * Used by both the tip and the revoke path; they were byte-identical copies
   * of this function before.
   */
  fun signAndSend(
    activity: ComponentActivity,
    transactionBytes: List<Int>,
    result: MethodChannel.Result,
  ) {
    launchOnActivity(activity, result, "SEND_EXCEPTION") { s ->
      val txBytes = ByteArray(transactionBytes.size) { i -> transactionBytes[i].toByte() }
      when (val payload = walletAdapter.transact(s) { signAndSendTransactions(arrayOf(txBytes)) }) {
        is TransactionResult.Success -> {
          val sig = payload.payload.signatures.firstOrNull()
          runCatching {
            result.success(
              mapOf(
                "signature" to sig?.let {
                  android.util.Base64.encodeToString(it, android.util.Base64.NO_WRAP)
                },
              ),
            )
          }
        }
        is TransactionResult.NoWalletFound -> {
          runCatching { result.error("NO_WALLET", payload.message, null) }
        }
        is TransactionResult.Failure -> {
          Log.w(TAG, "send failure: ${payload.message}", payload.e)
          runCatching {
            result.error("SEND_FAILED", "${payload.message}: ${payload.e.message}", null)
          }
        }
      }
    }
  }
}
