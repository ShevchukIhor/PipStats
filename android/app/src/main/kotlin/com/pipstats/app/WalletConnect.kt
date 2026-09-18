package com.pipstats.app

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.activity.ComponentActivity
import com.solana.mobilewalletadapter.clientlib.ActivityResultSender
import com.solana.mobilewalletadapter.clientlib.ConnectionIdentity
import com.solana.mobilewalletadapter.clientlib.MobileWalletAdapter
import com.solana.mobilewalletadapter.clientlib.TransactionResult
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
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
      identityUri = Uri.parse("https://pipboy.skr"),
      iconUri = Uri.parse("icon.png"),
      identityName = "Pip-Boy Device Stats",
    ),
  )

  @Volatile
  private var sender: ActivityResultSender? = null

  /** Called from configureFlutterEngine — before the activity is STARTED. */
  fun attach(activity: ComponentActivity) {
    if (sender == null) {
      sender = ActivityResultSender(activity)
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
    val s = sender ?: ActivityResultSender(activity).also { sender = it }
    CoroutineScope(Dispatchers.Main).launch {
      try {
        val txResult = walletAdapter.transact(s) { authResult ->
          authResult.accounts.firstOrNull()?.publicKey
        }
        when (txResult) {
          is TransactionResult.Success -> {
            val pubkey: ByteArray? = txResult.payload
            if (pubkey == null) {
              Log.w(TAG, "auth success but null account")
              result.success(null)
              return@launch
            }
            val acct = txResult.authResult.accounts.firstOrNull()
            persist(activity, pubkey, acct?.accountLabel)
            val map = mutableMapOf<String, Any?>()
            map["pubkey_bytes"] = pubkey.map { it.toInt() and 0xFF }
            map["label"] = acct?.accountLabel
            result.success(map)
          }
          is TransactionResult.NoWalletFound -> {
            Log.w(TAG, "no wallet: ${txResult.message}")
            result.error("NO_WALLET", txResult.message, null)
          }
          is TransactionResult.Failure -> {
            Log.w(TAG, "failure: ${txResult.message}", txResult.e)
            result.error("AUTH_FAILED", "${txResult.message}: ${txResult.e.message}", null)
          }
        }
      } catch (e: Exception) {
        Log.e(TAG, "exception", e)
        result.error("AUTH_EXCEPTION", e.message ?: e.toString(), null)
      }
    }
  }

  /** Revoke authorization and clear any persisted session. */
  fun deauthorize(activity: ComponentActivity, result: MethodChannel.Result) {
    val s = sender ?: ActivityResultSender(activity).also { sender = it }
    CoroutineScope(Dispatchers.Main).launch {
      try {
        walletAdapter.disconnect(s)
      } catch (_: Exception) {
        // ignore — clear local state regardless
      } finally {
        clear(activity)
        result.success(true)
      }
    }
  }

  /**
   * Sign and send a serialized (unsigned) transaction message via Seed Vault.
   * Params: byte arrays of message bytes. Returns the transaction signature.
   */
  fun signAndSend(activity: ComponentActivity, messageBytes: List<Int>, result: MethodChannel.Result) {
    val s = sender ?: ActivityResultSender(activity).also { sender = it }
    CoroutineScope(Dispatchers.Main).launch {
      try {
        val txBytes = ByteArray(messageBytes.size) { i -> messageBytes[i].toByte() }
        val payload = walletAdapter.transact(s) {
          signAndSendTransactions(arrayOf(txBytes))
        }
        when (payload) {
          is TransactionResult.Success -> {
            val sr = payload.payload
            val sig = sr.signatures.firstOrNull()
            val map = mutableMapOf<String, Any?>()
            map["signature"] = sig?.let { android.util.Base64.encodeToString(it, android.util.Base64.NO_WRAP) }
            result.success(map)
          }
          is TransactionResult.NoWalletFound -> {
            result.error("NO_WALLET", payload.message, null)
          }
          is TransactionResult.Failure -> {
            Log.w(TAG, "send failure: ${payload.message}", payload.e)
            result.error("SEND_FAILED", "${payload.message}: ${payload.e.message}", null)
          }
        }
      } catch (e: Exception) {
        Log.e(TAG, "send exception", e)
        result.error("SEND_EXCEPTION", e.message ?: e.toString(), null)
      }
    }
  }

  /** Sign and send a serialized SPL token transfer transaction via Seed Vault. */
  fun sendTip(activity: ComponentActivity, messageBytes: List<Int>, result: MethodChannel.Result) {
    val s = sender ?: ActivityResultSender(activity).also { sender = it }
    CoroutineScope(Dispatchers.Main).launch {
      try {
        val txBytes = ByteArray(messageBytes.size) { i -> messageBytes[i].toByte() }
        val payload = walletAdapter.transact(s) {
          signAndSendTransactions(arrayOf(txBytes))
        }
        when (payload) {
          is TransactionResult.Success -> {
            val sr = payload.payload
            val sig = sr.signatures.firstOrNull()
            val map = mutableMapOf<String, Any?>()
            map["signature"] = sig?.let { android.util.Base64.encodeToString(it, android.util.Base64.NO_WRAP) }
            result.success(map)
          }
          is TransactionResult.NoWalletFound -> {
            result.error("NO_WALLET", payload.message, null)
          }
          is TransactionResult.Failure -> {
            Log.w(TAG, "tip send failure: ${payload.message}", payload.e)
            result.error("SEND_FAILED", "${payload.message}: ${payload.e.message}", null)
          }
        }
      } catch (e: Exception) {
        Log.e(TAG, "tip send exception", e)
        result.error("SEND_EXCEPTION", e.message ?: e.toString(), null)
      }
    }
  }
}