package certificate_picker

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.security.KeyChain
import android.security.KeyChainAliasCallback
import android.security.KeyChainException
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.security.PrivateKey
import java.security.cert.X509Certificate
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager
import okhttp3.OkHttpClient
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import java.security.KeyStore
import java.security.SecureRandom
import java.util.concurrent.TimeUnit

/**
 * Native Android plugin for Flutter that enables automatic certificate selection
 * for mutual TLS (mTLS) authentication using certificates.
 */
class CertificatePickerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var context: Context? = null
    
    private var selectedAlias: String? = null
    private var sslContext: SSLContext? = null
    private var okHttpClient: OkHttpClient? = null

    companion object {
        private const val CHANNEL_NAME = "mtls_certificate_picker"
        private const val PREFS_NAME = "certificate_picker_prefs"
        private const val PREF_CERTIFICATE_ALIAS = "certificate_alias"
        private const val CONNECT_TIMEOUT_SECONDS = 120L
        private const val READ_TIMEOUT_SECONDS = 120L
        private const val WRITE_TIMEOUT_SECONDS = 120L
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        loadStoredCertificateAlias()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "pickCertificate" -> {
                pickCertificate(result)
            }
            "setupClientAuth" -> {
                val alias = call.argument<String>("alias")
                if (alias != null) {
                    setupClientAuth(alias, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Alias parameter is required", null)
                }
            }
            "getSelectedAlias" -> {
                result.success(selectedAlias)
            }
            "clearCertificate" -> {
                clearCertificate(result)
            }
            "isCertificateAvailable" -> {
                val alias = call.argument<String>("alias")
                if (alias != null) {
                    isCertificateAvailable(alias, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Alias parameter is required", null)
                }
            }
            "listAvailableCertificates" -> {
                listAvailableCertificates(result)
            }
            "requestCertificateAccess" -> {
                requestCertificateAccess(result)
            }
            "selectCertificate" -> {
                selectCertificate(result)
            }
            "makeRequestWithCertificate" -> {
                val url = call.argument<String>("url")
                val method = call.argument<String>("method")
                val headers = call.argument<Map<String, String>>("headers")
                val bodyJson = call.argument<String>("bodyJson") 
                
                if (url != null && method != null) {
                    makeRequestWithCertificate(url, method, headers, bodyJson, result)
                } else {
                    result.error("INVALID_ARGUMENT", "URL and method are required", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Automatically selects the stored certificate
     */
    private fun pickCertificate(result: Result) {
        val currentContext = context ?: activity
        if (currentContext == null) {
            result.error("NO_CONTEXT", "No context available", null)
            return
        }

        val storedAlias = getStoredCertificateAlias()
        if (storedAlias == null) {
            result.error("NO_CERTIFICATE_STORED", "No certificate alias stored. Please select a certificate first.", null)
            return
        }

        Thread {
            try {
                val privateKey = KeyChain.getPrivateKey(currentContext, storedAlias)
                val certificateChain = KeyChain.getCertificateChain(currentContext, storedAlias)
                
                if (privateKey != null && certificateChain != null && certificateChain.isNotEmpty()) {
                    selectedAlias = storedAlias
                    result.success(storedAlias)
                    return@Thread
                }
                
                val currentActivity = activity
                if (currentActivity == null) {
                    result.error("NO_ACTIVITY", "No activity available", null)
                    return@Thread
                }
                
                try {
                    val installIntent = KeyChain.createInstallIntent()
                    installIntent.putExtra(KeyChain.EXTRA_NAME, storedAlias)
                    
                    if (installIntent.resolveActivity(currentContext.packageManager) != null) {
                        result.error("CERTIFICATE_NOT_INSTALLED", "Certificate '$storedAlias' is not installed", null)
                        return@Thread
                    }
                } catch (e: Exception) {
                }
                
                result.error("CERTIFICATE_NOT_FOUND", "Certificate '$storedAlias' is not accessible", null)
                
            } catch (e: KeyChainException) {
                result.error("KEYCHAIN_ERROR", "KeyChain error: ${e.message}", null)
            } catch (e: Exception) {
                result.error("CERTIFICATE_ERROR", "Failed to access certificate: ${e.message}", null)
            }
        }.start()
    }

    /**
     * Sets up client authentication with the selected certificate
     */
    private fun setupClientAuth(alias: String, result: Result) {
        val currentContext = context ?: activity
        if (currentContext == null) {
            result.error("NO_CONTEXT", "No context available", null)
            return
        }

        Thread {
            try {
                val privateKey = KeyChain.getPrivateKey(currentContext, alias)
                val certificateChain = KeyChain.getCertificateChain(currentContext, alias)

                if (privateKey == null || certificateChain == null || certificateChain.isEmpty()) {
                    result.error("CERTIFICATE_ERROR", "Failed to retrieve certificate or private key", null)
                    return@Thread
                }

                sslContext = createSSLContext(privateKey, certificateChain)
                selectedAlias = alias
                
                storeCertificateAlias(alias)

                okHttpClient = OkHttpClient.Builder()
                    .sslSocketFactory(sslContext!!.socketFactory, getTrustManager())
                    .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                    .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                    .writeTimeout(WRITE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                    .build()

                result.success(true)

            } catch (e: KeyChainException) {
                result.error("KEYCHAIN_ERROR", "KeyChain error: ${e.message}", null)
            } catch (e: Exception) {
                result.error("SETUP_ERROR", "Failed to setup client authentication: ${e.message}", null)
            }
        }.start()
    }

    /**
     * Creates SSL context with client certificate and private key
     */
    private fun createSSLContext(privateKey: PrivateKey, certificateChain: Array<X509Certificate>): SSLContext {
        try {
            val keyStore = KeyStore.getInstance("PKCS12")
            keyStore.load(null, null)
            
            keyStore.setKeyEntry("client", privateKey, null, certificateChain)

            val keyManagerFactory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
            keyManagerFactory.init(keyStore, null)

            val trustManagerFactory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
            trustManagerFactory.init(null as KeyStore?)

            val sslContext = SSLContext.getInstance("TLS")
            sslContext.init(
                keyManagerFactory.keyManagers,
                trustManagerFactory.trustManagers,
                SecureRandom()
            )

            return sslContext
        } catch (e: Exception) {
            throw e
        }
    }

    /**
     * Checks if certificate is available for the given alias
     */
    private fun isCertificateAvailable(alias: String, result: Result) {
        val currentContext = context ?: activity
        if (currentContext == null) {
            result.error("NO_CONTEXT", "No context available", null)
            return
        }

        Thread {
            try {
                val privateKey = KeyChain.getPrivateKey(currentContext, alias)
                val certificateChain = KeyChain.getCertificateChain(currentContext, alias)
                
                val isAvailable = privateKey != null && certificateChain != null && certificateChain.isNotEmpty()
                result.success(isAvailable)

            } catch (e: KeyChainException) {
                result.error("KEYCHAIN_ERROR", "KeyChain error: ${e.message}", null)
            } catch (e: Exception) {
                result.error("CHECK_ERROR", "Failed to check certificate availability: ${e.message}", null)
            }
        }.start()
    }

    /**
     * Clears the selected certificate
     */
    private fun clearCertificate(result: Result) {
        selectedAlias = null
        sslContext = null
        okHttpClient = null
        
        clearStoredCertificateAlias()
        
        result.success(true)
    }

    /**
     * Makes a request using the OkHttp client with the configured certificate
     */
    private fun makeRequestWithCertificate(
        url: String,
        method: String,
        headers: Map<String, String>?,
        bodyJson: String?,
        result: Result
    ) {
        if (okHttpClient == null) {
            result.error("NO_HTTP_CLIENT", "HTTP client not available. Call setupClientAuth first.", null)
            return
        }

        Thread {
            try {
                val requestBuilder = okhttp3.Request.Builder().url(url)
                
                headers?.forEach { (key, value) ->
                    requestBuilder.addHeader(key, value)
                }
                
                when (method.uppercase()) {
                    "POST" -> {
                        val media = "application/json; charset=utf-8".toMediaTypeOrNull()
                        val body = (bodyJson ?: "{}").toRequestBody(media)
                        requestBuilder.post(body)
                    }
                    "GET" -> {
                        requestBuilder.get()
                    }
                    else -> {
                        result.error("UNSUPPORTED_METHOD", "Method $method not supported", null)
                        return@Thread
                    }
                }
                
                val request = requestBuilder.build()
                
                val response = okHttpClient!!.newCall(request).execute()
                
                val responseBody = response.body?.string() ?: ""
                val responseHeaders = response.headers.toMultimap()
                
                val responseData = mapOf(
                    "statusCode" to response.code,
                    "data" to responseBody,
                    "headers" to responseHeaders,
                    "success" to response.isSuccessful
                )
                
                result.success(responseData)
                
            } catch (e: Exception) {
                result.error("REQUEST_FAILED", "Request failed: ${e.message}", null)
            }
        }.start()
    }

    /**
     * Gets the default trust manager
     */
    private fun getTrustManager(): X509TrustManager {
        val trustManagerFactory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        trustManagerFactory.init(null as KeyStore?)
        return trustManagerFactory.trustManagers.first { it is X509TrustManager } as X509TrustManager
    }

    /**
     * Shows the certificate picker dialog for initial certificate selection
     */
    private fun selectCertificate(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "No activity available for certificate selection", null)
            return
        }

        try {
            KeyChain.choosePrivateKeyAlias(
                currentActivity,
                object : KeyChainAliasCallback {
                    override fun alias(alias: String?) {
                        if (alias != null) {
                            selectedAlias = alias
                            storeCertificateAlias(alias)
                            result.success(alias)
                        } else {
                            result.success(null)
                        }
                    }
                },
                arrayOf("RSA", "EC"),
                null,
                null,
                -1,
                null
            )
        } catch (e: Exception) {
            result.error("PICKER_ERROR", "Failed to show certificate picker: ${e.message}", null)
        }
    }

    /**
     * Requests access to the certificate using system permission dialog
     */
    private fun requestCertificateAccess(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("NO_ACTIVITY", "No activity available for permission request", null)
            return
        }

        val storedAlias = getStoredCertificateAlias()
        if (storedAlias == null) {
            result.error("NO_CERTIFICATE_STORED", "No certificate alias stored. Please select a certificate first.", null)
            return
        }

        try {
            KeyChain.choosePrivateKeyAlias(
                currentActivity,
                object : KeyChainAliasCallback {
                    override fun alias(alias: String?) {
                        if (alias != null && alias == storedAlias) {
                            selectedAlias = alias
                            result.success(alias)
                        } else {
                            result.success(null)
                        }
                    }
                },
                arrayOf("RSA", "EC"),
                null,
                null,
                -1,
                storedAlias
            )
        } catch (e: Exception) {
            result.error("PERMISSION_ERROR", "Failed to request certificate access: ${e.message}", null)
        }
    }

    /**
     * Lists available certificates for debugging
     */
    private fun listAvailableCertificates(result: Result) {
        val currentContext = context ?: activity
        if (currentContext == null) {
            result.error("NO_CONTEXT", "No context available", null)
            return
        }

        Thread {
            try {
                val availableCertificates = mutableListOf<String>()
                
                val keyStore = KeyStore.getInstance("AndroidKeyStore")
                keyStore.load(null)
                
                val aliases = keyStore.aliases()
                while (aliases.hasMoreElements()) {
                    val alias = aliases.nextElement()
                    availableCertificates.add("AndroidKeyStore: $alias")
                }
                
                val commonNames = listOf(
                    "api-auth-cert",
                    "auth-cert",
                    "client-cert",
                    "user-cert"
                )
                
                for (name in commonNames) {
                    try {
                        val privateKey = KeyChain.getPrivateKey(currentContext, name)
                        val certificateChain = KeyChain.getCertificateChain(currentContext, name)
                        
                        if (privateKey != null && certificateChain != null && certificateChain.isNotEmpty()) {
                            availableCertificates.add("KeyChain: $name (accessible)")
                        } else {
                            availableCertificates.add("KeyChain: $name (not accessible)")
                        }
                    } catch (e: Exception) {
                        availableCertificates.add("KeyChain: $name (error: ${e.message})")
                    }
                }
                
                result.success(availableCertificates)
                
            } catch (e: Exception) {
                result.error("LIST_ERROR", "Failed to list certificates: ${e.message}", null)
            }
        }.start()
    }

    /**
     * Loads the stored certificate alias from SharedPreferences
     */
    private fun loadStoredCertificateAlias() {
        val currentContext = context ?: activity
        if (currentContext == null) return

        val prefs = currentContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val storedAlias = prefs.getString(PREF_CERTIFICATE_ALIAS, null)
        if (storedAlias != null) {
            selectedAlias = storedAlias
        }
    }

    /**
     * Stores the certificate alias in SharedPreferences
     */
    private fun storeCertificateAlias(alias: String) {
        val currentContext = context ?: activity
        if (currentContext == null) return

        val prefs = currentContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(PREF_CERTIFICATE_ALIAS, alias).apply()
    }

    /**
     * Gets the stored certificate alias from SharedPreferences
     */
    private fun getStoredCertificateAlias(): String? {
        val currentContext = context ?: activity
        if (currentContext == null) return null

        val prefs = currentContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(PREF_CERTIFICATE_ALIAS, null)
    }

    /**
     * Clears the stored certificate alias from SharedPreferences
     */
    private fun clearStoredCertificateAlias() {
        val currentContext = context ?: activity
        if (currentContext == null) return

        val prefs = currentContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().remove(PREF_CERTIFICATE_ALIAS).apply()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}

