# Certificate Picker & OkHttp mTLS Implementation Documentation

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Android Native Implementation](#android-native-implementation)
4. [Flutter/Dart Implementation](#flutterdart-implementation)
5. [Certificate Selection Flow](#certificate-selection-flow)
6. [OkHttp Client Setup with mTLS](#okhttp-client-setup-with-mtls)
7. [Making Requests](#making-requests)
8. [Error Handling & Certificate Revocation](#error-handling--certificate-revocation)
9. [Usage Examples](#usage-examples)
10. [Troubleshooting](#troubleshooting)

---

## Overview

This implementation provides **mutual TLS (mTLS) authentication** for Flutter applications on Android, enabling secure API communication using client certificates stored in the Android KeyChain. The system consists of:

- **Android Native Plugin** (`CertificatePickerPlugin.kt`): Handles certificate selection, SSL context creation, and OkHttp client configuration
- **Flutter Service Layer** (`CertificatePickerService`, `NativeCertificateRequestService`): Provides Dart interfaces to the native functionality
- **State Management** (`CertificateStateProvider`): Manages certificate selection state using Riverpod

### Key Features

- ✅ Automatic certificate selection from Android KeyChain
- ✅ Persistent certificate storage using SharedPreferences
- ✅ Custom OkHttp client with mTLS support
- ✅ Certificate availability checking
- ✅ Automatic certificate revocation handling
- ✅ Support for RSA and EC certificate types
- ✅ Thread-safe certificate access

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Application                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐      ┌──────────────────────────┐  │
│  │ CertificateState │      │ NativeCertificateRequest  │  │
│  │    Provider      │◄─────┤        Service            │  │
│  └──────────────────┘      └──────────────────────────┘  │
│           │                           │                     │
│           │                           │                     │
│           ▼                           ▼                     │
│  ┌──────────────────┐      ┌──────────────────────────┐  │
│  │CertificatePicker │      │  MethodChannel           │  │
│  │     Service       │──────┤  (Platform Channel)     │  │
│  └──────────────────┘      └──────────────────────────┘  │
│                                                              │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            │ MethodChannel
                            │
┌───────────────────────────▼─────────────────────────────────┐
│              Android Native Layer                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         CertificatePickerPlugin                      │  │
│  │  ┌────────────────────────────────────────────────┐ │  │
│  │  │  Certificate Selection & Management            │ │  │
│  │  │  - pickCertificate()                           │ │  │
│  │  │  - selectCertificate()                         │ │  │
│  │  │  - requestCertificateAccess()                  │ │  │
│  │  │  - isCertificateAvailable()                     │ │  │
│  │  └────────────────────────────────────────────────┘ │  │
│  │                                                      │  │
│  │  ┌────────────────────────────────────────────────┐ │  │
│  │  │  SSL Context & OkHttp Setup                   │ │  │
│  │  │  - setupClientAuth()                           │ │  │
│  │  │  - createSSLContext()                          │ │  │
│  │  │  - getTrustManager()                            │ │  │
│  │  └────────────────────────────────────────────────┘ │  │
│  │                                                      │  │
│  │  ┌────────────────────────────────────────────────┐ │  │
│  │  │  HTTP Request Execution                        │ │  │
│  │  │  - makeRequestWithCertificate()                 │ │  │
│  │  └────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────┘  │
│                            │                                │
│                            │                                │
│  ┌─────────────────────────▼────────────────────────────┐  │
│  │              Android KeyChain                         │  │
│  │  - Private Key Storage                                 │  │
│  │  - Certificate Chain Storage                          │  │
│  │  - User Permission Management                         │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              OkHttp Client                             │  │
│  │  - Custom SSL Socket Factory                           │  │
│  │  - Client Certificate Authentication                  │  │
│  │  - Trust Manager Configuration                        │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Android Native Implementation

### CertificatePickerPlugin.kt

The plugin implements three key interfaces:
- `FlutterPlugin`: For plugin lifecycle management
- `MethodCallHandler`: For handling method calls from Flutter
- `ActivityAware`: For accessing Android Activity (required for certificate picker UI)

#### Key Components

**1. State Management**
```kotlin
private var selectedAlias: String? = null
private var sslContext: SSLContext? = null
private var okHttpClient: OkHttpClient? = null
```

**2. Persistent Storage**
- Uses `SharedPreferences` to store the selected certificate alias
- Persists across app restarts
- Key: `certificate_picker_prefs` → `certificate_alias`

**3. Method Channel**
- Channel name: `mtls_certificate_picker`
- Handles 9 different method calls (see [Method Reference](#method-reference))

### Certificate Selection Methods

#### `pickCertificate()`
Automatically selects the stored certificate alias.

**Flow:**
1. Retrieves stored alias from SharedPreferences
2. Attempts to access certificate via `KeyChain.getPrivateKey()` and `KeyChain.getCertificateChain()`
3. If accessible, returns the alias
4. If not accessible, checks if certificate needs installation
5. Returns error if certificate is not found or not accessible

**Key Implementation:**
```kotlin
val privateKey = KeyChain.getPrivateKey(currentContext, storedAlias)
val certificateChain = KeyChain.getCertificateChain(currentContext, storedAlias)

if (privateKey != null && certificateChain != null && certificateChain.isNotEmpty()) {
    selectedAlias = storedAlias
    result.success(storedAlias)
}
```

#### `selectCertificate()`
Shows the Android system certificate picker dialog.

**Flow:**
1. Uses `KeyChain.choosePrivateKeyAlias()` to show system picker
2. User selects certificate from available certificates
3. Selected alias is stored in SharedPreferences
4. Returns selected alias or null if cancelled

**Key Implementation:**
```kotlin
KeyChain.choosePrivateKeyAlias(
    currentActivity,
    object : KeyChainAliasCallback {
        override fun alias(alias: String?) {
            if (alias != null) {
                selectedAlias = alias
                storeCertificateAlias(alias)
                result.success(alias)
            }
        }
    },
    arrayOf("RSA", "EC"),  // Supported key types
    null, null, -1, null
)
```

#### `requestCertificateAccess()`
Requests permission to access a specific stored certificate.

**Flow:**
1. Retrieves stored alias
2. Shows certificate picker pre-filtered to the stored alias
3. User grants permission via system dialog
4. Returns alias if permission granted

### SSL Context Creation

#### `setupClientAuth(alias: String)`
Sets up client authentication with the selected certificate.

**Flow:**
1. Retrieves private key and certificate chain from KeyChain
2. Creates SSL context with certificate
3. Configures OkHttp client with custom SSL socket factory
4. Stores alias for future use

**Key Implementation:**
```kotlin
val privateKey = KeyChain.getPrivateKey(currentContext, alias)
val certificateChain = KeyChain.getCertificateChain(currentContext, alias)

sslContext = createSSLContext(privateKey, certificateChain)
selectedAlias = alias
storeCertificateAlias(alias)

okHttpClient = OkHttpClient.Builder()
    .sslSocketFactory(sslContext!!.socketFactory, getTrustManager())
    .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
    .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
    .writeTimeout(WRITE_TIMEOUT_SECONDS, TimeUnit.SECONDS)
    .build()
```

#### `createSSLContext()`
Creates a TLS SSL context with client certificate authentication.

**Process:**
1. Creates a PKCS12 KeyStore
2. Adds private key and certificate chain to KeyStore
3. Initializes KeyManagerFactory with the KeyStore
4. Initializes TrustManagerFactory with default trust store
5. Creates SSLContext with TLS protocol
6. Initializes SSLContext with key and trust managers

**Key Implementation:**
```kotlin
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
```

### OkHttp Client Configuration

The OkHttp client is configured with:
- **Custom SSL Socket Factory**: Uses the SSL context with client certificate
- **Trust Manager**: Uses default system trust store
- **Timeouts**:
  - Connect: 120 seconds
  - Read: 120 seconds
  - Write: 120 seconds

### HTTP Request Execution

#### `makeRequestWithCertificate()`
Executes HTTP requests using the configured OkHttp client.

**Supported Methods:**
- `GET`: Simple GET request
- `POST`: POST request with JSON body

**Request Flow:**
1. Validates OkHttp client is available
2. Builds request with URL, method, headers, and body
3. Executes request synchronously (on background thread)
4. Extracts response body, headers, and status code
5. Returns structured response map

**Response Format:**
```kotlin
mapOf(
    "statusCode" to response.code,
    "data" to responseBody,
    "headers" to responseHeaders,
    "success" to response.isSuccessful
)
```

**Key Implementation:**
```kotlin
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
}

val response = okHttpClient!!.newCall(request).execute()
```

---

## Flutter/Dart Implementation

### CertificatePickerService

A static service class that provides a Dart interface to the native certificate picker functionality.

**Methods:**
- `pickCertificate()`: Automatically picks stored certificate
- `setupClientAuth(String alias)`: Sets up client authentication
- `isCertificateAvailable(String alias)`: Checks certificate availability
- `getSelectedAlias()`: Gets currently selected alias
- `clearCertificate()`: Clears selected certificate
- `listAvailableCertificates()`: Lists all available certificates
- `requestCertificateAccess()`: Requests certificate access permission
- `selectCertificate()`: Shows certificate picker dialog

**Example:**
```dart
final alias = await CertificatePickerService.pickCertificate();
if (alias != null) {
  await CertificatePickerService.setupClientAuth(alias);
}
```

### NativeCertificateRequestService

A singleton service that handles HTTP requests using the native OkHttp client with mTLS.

**Key Features:**
- Singleton pattern for global access
- Automatic certificate revocation detection
- User ID tracking for requests
- Response parsing and error handling
- Connectivity checking

**Main Methods:**

#### `makeRequest()`
Low-level request method that calls the native `makeRequestWithCertificate`.

```dart
Future<Map<String, dynamic>> makeRequest({
  required String url,
  required HttpMethod method,
  Map<String, String>? headers,
  Map<String, dynamic>? body,
})
```

**Features:**
- Automatically adds `X-LoggedInUserId` header if user is logged in
- Detects certificate revocation errors
- Handles certificate revocation automatically

#### `makeApiRequest()`
High-level API request method with base URL handling.

```dart
Future<Map<String, dynamic>> makeApiRequest({
  required HttpMethod method,
  required String endpoint,
  Map<String, dynamic>? body,
  Map<String, String>? additionalHeaders,
})
```

**Features:**
- Checks connectivity before making request
- Adds default headers (Content-Type, Accept)
- Constructs full URL from base URL and endpoint

#### `makeTypedApiRequest()`
Type-safe API request method with automatic response parsing.

```dart
Future<TResponse> makeTypedApiRequest<TRequest, TResponse>({
  required HttpMethod method,
  required String endpoint,
  TRequest? requestData,
  Map<String, String>? additionalHeaders,
  required TResponse Function(Map<String, dynamic>) fromMap,
})
```

**Features:**
- Type-safe request/response handling
- Automatic JSON parsing
- Error handling with status codes
- Certificate revocation detection

### CertificateStateProvider

Riverpod state notifier that manages certificate selection state.

**State Model:**
```dart
class CertificateState {
  final String? selectedAlias;
  final bool isCertificateSelected;
  final bool isCertificateVerified;
  final String? error;
}
```

**Methods:**
- `selectCertificate()`: Automatic certificate selection with fallback logic
- `selectCertificateManually()`: Manual certificate selection
- `clearCertificate()`: Clears certificate and resets state
- `syncWithNativeState()`: Syncs state with native side

**Selection Flow:**
1. Attempts to pick stored certificate
2. If no certificate stored, shows picker dialog
3. If certificate not installed, requests access
4. Sets up client authentication
5. Verifies certificate availability
6. Updates state accordingly

---

## Certificate Selection Flow

### Initial Certificate Selection

```
┌─────────────────┐
│  App Starts     │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│ selectCertificate() called │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ pickCertificate()           │
│ - Check SharedPreferences   │
└────────┬────────────────────┘
         │
         ├─── Certificate Found ───┐
         │                          │
         │                          ▼
         │              ┌──────────────────────────┐
         │              │ Access Certificate       │
         │              │ via KeyChain             │
         │              └────────┬─────────────────┘
         │                       │
         │                       ├─── Accessible ───┐
         │                       │                   │
         │                       │                   ▼
         │                       │      ┌──────────────────────┐
         │                       │      │ setupClientAuth()     │
         │                       │      │ - Create SSL Context │
         │                       │      │ - Configure OkHttp   │
         │                       │      └──────────────────────┘
         │                       │
         │                       └─── Not Accessible ───┐
         │                                               │
         └─── No Certificate Stored ─────────────────────┤
                                                         │
                                                         ▼
                                            ┌──────────────────────────┐
                                            │ selectCertificate()     │
                                            │ - Show System Picker     │
                                            └────────┬─────────────────┘
                                                     │
                                                     ├─── User Selects ───┐
                                                     │                     │
                                                     │                     ▼
                                                     │         ┌──────────────────────┐
                                                     │         │ setupClientAuth()     │
                                                     │         └──────────────────────┘
                                                     │
                                                     └─── User Cancels ───┐
                                                                          │
                                                                          ▼
                                                             ┌──────────────────────┐
                                                             │ Error State          │
                                                             └──────────────────────┘
```

### Certificate Access Permission Flow

```
┌─────────────────────────────┐
│ Certificate Not Accessible   │
└────────┬─────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ requestCertificateAccess()  │
│ - Get stored alias           │
└────────┬─────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ KeyChain.choosePrivateKey   │
│ Alias() with stored alias   │
│ - Shows permission dialog   │
└────────┬─────────────────────┘
         │
         ├─── Permission Granted ───┐
         │                            │
         │                            ▼
         │                ┌────────────────────────┐
         │                │ setupClientAuth()      │
         │                │ - Create SSL Context  │
         │                │ - Configure OkHttp    │
         │                └────────────────────────┘
         │
         └─── Permission Denied ───┐
                                    │
                                    ▼
                       ┌────────────────────────┐
                       │ Error: Permission      │
                       │ Denied                 │
                       └────────────────────────┘
```

---

## OkHttp Client Setup with mTLS

### SSL Context Creation Process

```
┌─────────────────────────────────────────────────────────┐
│ 1. Retrieve Certificate from KeyChain                   │
│    - PrivateKey via KeyChain.getPrivateKey()             │
│    - CertificateChain via KeyChain.getCertificateChain() │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 2. Create PKCS12 KeyStore                                 │
│    - Initialize empty KeyStore                          │
│    - Add private key and certificate chain               │
│    - Alias: "client"                                      │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 3. Initialize KeyManagerFactory                          │
│    - Algorithm: Default (usually PKIX)                   │
│    - Initialize with KeyStore containing client cert    │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 4. Initialize TrustManagerFactory                       │
│    - Algorithm: Default (usually PKIX)                  │
│    - Initialize with null (uses system trust store)     │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 5. Create SSLContext                                     │
│    - Protocol: TLS                                       │
│    - Initialize with:                                   │
│      • KeyManagers (from KeyManagerFactory)             │
│      • TrustManagers (from TrustManagerFactory)          │
│      • SecureRandom                                     │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 6. Configure OkHttp Client                               │
│    - SSL Socket Factory: sslContext.socketFactory        │
│    - Trust Manager: X509TrustManager                    │
│    - Timeouts: 120s (connect, read, write)               │
└─────────────────────────────────────────────────────────┘
```

### mTLS Handshake Process

When a request is made:

1. **Client Hello**: OkHttp sends TLS handshake with supported cipher suites
2. **Server Hello**: Server responds with selected cipher suite
3. **Certificate Exchange**:
   - Server sends its certificate (standard TLS)
   - **Client sends its certificate** (mTLS - mutual authentication)
4. **Key Exchange**: Both parties exchange keys
5. **Verification**:
   - Client verifies server certificate (via TrustManager)
   - **Server verifies client certificate** (mTLS requirement)
6. **Encrypted Communication**: Secure channel established

---

## Making Requests

### Request Flow

```
┌─────────────────────────────────────────────────────────┐
│ Flutter/Dart Layer                                       │
│                                                           │
│  NativeCertificateRequestService.makeApiRequest()         │
│  └─► Checks connectivity                                 │
│  └─► Constructs full URL                                │
│  └─► Adds default headers                               │
│  └─► Calls makeRequest()                                 │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ MethodChannel.invokeMethod()
                     │ 'makeRequestWithCertificate'
                     │
┌────────────────────▼────────────────────────────────────┐
│ Android Native Layer                                     │
│                                                           │
│  CertificatePickerPlugin.makeRequestWithCertificate()    │
│  └─► Validates OkHttp client available                  │
│  └─► Builds OkHttp Request                               │
│      • URL                                                │
│      • Method (GET/POST)                                  │
│      • Headers                                            │
│      • Body (if POST)                                     │
│  └─► Executes request on background thread              │
│  └─► OkHttp uses SSL context with client certificate     │
│  └─► mTLS handshake occurs                               │
│  └─► Receives response                                   │
│  └─► Parses response (status, body, headers)            │
│  └─► Returns Map to Flutter                             │
└────────────────────┬────────────────────────────────────┘
                     │
                     │ Response Map
                     │
┌────────────────────▼────────────────────────────────────┐
│ Flutter/Dart Layer                                       │
│                                                           │
│  NativeCertificateRequestService                         │
│  └─► Parses response map                                 │
│  └─► Checks for certificate errors                       │
│  └─► Handles certificate revocation if needed            │
│  └─► Returns parsed response                              │
└──────────────────────────────────────────────────────────┘
```

### Example Request

**Dart Side:**
```dart
final service = NativeCertificateRequestService();
final response = await service.makeApiRequest(
  method: HttpMethod.post,
  endpoint: '/api/users',
  body: {
    'name': 'John Doe',
    'email': 'john@example.com',
  },
);
```

**Native Side (Kotlin):**
```kotlin
// Request is built
val requestBuilder = okhttp3.Request.Builder()
    .url("https://api.example.com/api/users")
    .addHeader("Content-Type", "application/json")
    .addHeader("Accept", "application/json")
    .addHeader("X-LoggedInUserId", "user123")
    .post(jsonBody)

// Executed with mTLS
val response = okHttpClient.newCall(request).execute()

// Response parsed
val responseData = mapOf(
    "statusCode" to response.code,
    "data" to response.body?.string(),
    "headers" to response.headers.toMultimap(),
    "success" to response.isSuccessful
)
```

---

## Error Handling & Certificate Revocation

### Certificate Revocation Detection

The system automatically detects certificate-related errors:

**Error Patterns Detected:**
- Contains "certificate"
- Contains "ssl"
- Contains "tls"
- Contains "handshake"
- Contains "certificate revoked"
- Contains "certificate invalid"

**Revocation Handling:**
```dart
bool _isCertificateRevocationError(dynamic error) {
  final errorString = error.toString().toLowerCase();
  return errorString.contains('certificate') ||
         errorString.contains('ssl') ||
         errorString.contains('tls') ||
         errorString.contains('handshake') ||
         errorString.contains('certificate revoked') ||
         errorString.contains('certificate invalid');
}
```

### Revocation Flow

```
┌─────────────────────────────────────┐
│ Request Fails                       │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ Check Error Type                    │
└────────────┬────────────────────────┘
             │
             ├─── Certificate Error ───┐
             │                          │
             │                          ▼
             │              ┌──────────────────────────┐
             │              │ _handleCertificate      │
             │              │ Revocation()             │
             │              │                          │
             │              │ 1. Clear logged in user  │
             │              │ 2. Clear certificate      │
             │              │ 3. Sync state            │
             │              │ 4. Navigate to login     │
             │              └──────────────────────────┘
             │
             └─── Other Error ───┐
                                 │
                                 ▼
                    ┌──────────────────────────┐
                    │ Throw Exception          │
                    │ with error message       │
                    └──────────────────────────┘
```

### HTTP Status Code Handling

**401 Unauthorized / 403 Forbidden:**
- Checks if error contains certificate-related keywords
- If yes, triggers certificate revocation
- If no, throws standard error message

**404 Not Found:**
- Returns: "API is not available/offline"

**Other Errors:**
- Returns: "Server error: {error details}"

---

## Usage Examples

### Example 1: Initial Certificate Selection

```dart
import 'package:com_steer73_mccann/infrastructure/services/certificate_handling/certificate_handling.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Using the state provider
final certificateNotifier = ref.read(certificateStateProvider.notifier);
final success = await certificateNotifier.selectCertificate();

if (success) {
  print('Certificate selected and verified');
} else {
  print('Certificate selection failed');
}
```

### Example 2: Making API Requests

```dart
import 'package:com_steer73_mccann/infrastructure/services/certificate_handling/certificate_handling.dart';

final service = NativeCertificateRequestService();

// Simple API request
try {
  final response = await service.makeApiRequest(
    method: HttpMethod.get,
    endpoint: '/api/users',
  );
  
  print('Status: ${response['statusCode']}');
  print('Data: ${response['data']}');
} catch (e) {
  print('Error: $e');
}

// POST request with body
try {
  final response = await service.makeApiRequest(
    method: HttpMethod.post,
    endpoint: '/api/users',
    body: {
      'name': 'John Doe',
      'email': 'john@example.com',
    },
  );
  
  print('User created: ${response['data']}');
} catch (e) {
  print('Error: $e');
}
```

### Example 3: Type-Safe API Request

```dart
// Define response model
class User {
  final int id;
  final String name;
  final String email;
  
  User({required this.id, required this.name, required this.email});
  
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      name: map['name'],
      email: map['email'],
    );
  }
}

// Make typed request
final service = NativeCertificateRequestService();
final user = await service.makeTypedApiRequest<Map<String, dynamic>, User>(
  method: HttpMethod.get,
  endpoint: '/api/users/123',
  fromMap: User.fromMap,
);

print('User: ${user.name}');
```

### Example 4: Manual Certificate Selection

```dart
final certificateNotifier = ref.read(certificateStateProvider.notifier);

// Show certificate picker dialog
final success = await certificateNotifier.selectCertificateManually();

if (success) {
  final state = ref.read(certificateStateProvider);
  print('Selected alias: ${state.selectedAlias}');
  print('Verified: ${state.isCertificateVerified}');
}
```

### Example 5: Checking Certificate Availability

```dart
final alias = await CertificatePickerService.getSelectedAlias();

if (alias != null) {
  final isAvailable = await CertificatePickerService.isCertificateAvailable(alias);
  
  if (isAvailable) {
    print('Certificate is available and accessible');
  } else {
    print('Certificate is not accessible');
  }
}
```

### Example 6: Listing Available Certificates

```dart
final certificates = await CertificatePickerService.listAvailableCertificates();

for (final cert in certificates) {
  print('Certificate: $cert');
}
```

### Example 7: Clearing Certificate

```dart
// Clear certificate and reset state
final certificateNotifier = ref.read(certificateStateProvider.notifier);
await certificateNotifier.clearCertificate();

// Or directly via service
await CertificatePickerService.clearCertificate();
```

---

## Troubleshooting

### Common Issues

#### 1. "NO_CERTIFICATE_STORED" Error

**Cause:** No certificate has been selected and stored yet.

**Solution:**
```dart
// Show certificate picker to select a certificate
final alias = await CertificatePickerService.selectCertificate();
if (alias != null) {
  await CertificatePickerService.setupClientAuth(alias);
}
```

#### 2. "CERTIFICATE_NOT_INSTALLED" Error

**Cause:** The stored certificate alias references a certificate that is not installed.

**Solution:**
- Install the certificate on the device
- Or select a different certificate

#### 3. "CERTIFICATE_NOT_FOUND" Error

**Cause:** The certificate exists but is not accessible (permission issue).

**Solution:**
```dart
// Request certificate access permission
final alias = await CertificatePickerService.requestCertificateAccess();
if (alias != null) {
  await CertificatePickerService.setupClientAuth(alias);
}
```

#### 4. "NO_HTTP_CLIENT" Error

**Cause:** `setupClientAuth()` has not been called before making a request.

**Solution:**
```dart
// Ensure certificate is set up before making requests
final alias = await CertificatePickerService.pickCertificate();
if (alias != null) {
  await CertificatePickerService.setupClientAuth(alias);
  // Now you can make requests
}
```

#### 5. "KEYCHAIN_ERROR" Error

**Cause:** Android KeyChain service error.

**Possible Solutions:**
- Check if device supports KeyChain (Android 4.0+)
- Verify certificate is properly installed
- Check device security settings
- Try clearing and re-selecting certificate

#### 6. Certificate Revocation Loop

**Cause:** Certificate keeps getting revoked, causing logout loop.

**Solution:**
- Verify certificate is valid and not expired
- Check server certificate validation
- Ensure certificate matches server requirements
- Contact server administrator

### Debugging Tips

1. **List Available Certificates:**
```dart
final certificates = await CertificatePickerService.listAvailableCertificates();
print('Available certificates:');
certificates.forEach(print);
```

2. **Check Certificate State:**
```dart
final state = ref.read(certificateStateProvider);
print('Selected: ${state.selectedAlias}');
print('Verified: ${state.isCertificateVerified}');
print('Error: ${state.error}');
```

3. **Verify Certificate Setup:**
```dart
final alias = await CertificatePickerService.getSelectedAlias();
if (alias != null) {
  final isAvailable = await CertificatePickerService.isCertificateAvailable(alias);
  print('Certificate available: $isAvailable');
}
```

4. **Monitor Request Errors:**
```dart
try {
  final response = await service.makeApiRequest(...);
} catch (e) {
  print('Error type: ${e.runtimeType}');
  print('Error message: $e');
  // Check if it's a certificate error
  if (e.toString().toLowerCase().contains('certificate')) {
    // Handle certificate error
  }
}
```

---

## Method Reference

### Android Native Methods

| Method | Description | Parameters | Returns |
|--------|-------------|------------|---------|
| `pickCertificate` | Automatically picks stored certificate | None | String? (alias) |
| `setupClientAuth` | Sets up client authentication | `alias: String` | Boolean |
| `getSelectedAlias` | Gets currently selected alias | None | String? |
| `clearCertificate` | Clears selected certificate | None | Boolean |
| `isCertificateAvailable` | Checks certificate availability | `alias: String` | Boolean |
| `listAvailableCertificates` | Lists available certificates | None | List<String> |
| `requestCertificateAccess` | Requests certificate access | None | String? (alias) |
| `selectCertificate` | Shows certificate picker | None | String? (alias) |
| `makeRequestWithCertificate` | Makes HTTP request | `url`, `method`, `headers?`, `bodyJson?` | Map<String, dynamic> |

### Flutter/Dart Methods

#### CertificatePickerService
- `pickCertificate()` → `Future<String?>`
- `setupClientAuth(String alias)` → `Future<bool>`
- `isCertificateAvailable(String alias)` → `Future<bool>`
- `getSelectedAlias()` → `Future<String?>`
- `clearCertificate()` → `Future<void>`
- `listAvailableCertificates()` → `Future<List<String>>`
- `requestCertificateAccess()` → `Future<String?>`
- `selectCertificate()` → `Future<String?>`

#### NativeCertificateRequestService
- `makeRequest({url, method, headers?, body?})` → `Future<Map<String, dynamic>>`
- `makeApiRequest({method, endpoint, body?, additionalHeaders?})` → `Future<Map<String, dynamic>>`
- `makeTypedApiRequest<TRequest, TResponse>({method, endpoint, requestData?, additionalHeaders?, fromMap})` → `Future<TResponse>`

---

## Security Considerations

1. **Certificate Storage**: Certificates are stored in Android KeyChain, which is hardware-backed on supported devices
2. **Private Key Protection**: Private keys never leave the Android KeyChain
3. **Permission Model**: Users must explicitly grant permission to access certificates
4. **Certificate Validation**: Server validates client certificate during mTLS handshake
5. **Revocation Handling**: Automatic detection and handling of revoked certificates
6. **Timeout Configuration**: 120-second timeouts prevent hanging requests

---

## Best Practices

1. **Always check connectivity** before making requests
2. **Handle certificate errors gracefully** with user-friendly messages
3. **Store certificate alias** for automatic selection on app restart
4. **Verify certificate availability** before making requests
5. **Clear certificate on logout** to prevent unauthorized access
6. **Monitor certificate state** using the state provider
7. **Use typed requests** for better type safety and error handling
8. **Log certificate operations** for debugging (in debug mode only)

---

## Conclusion

This implementation provides a robust, secure solution for mTLS authentication in Flutter Android applications. The architecture separates concerns between native Android code and Flutter/Dart code, providing a clean interface for certificate management and secure API communication.

For questions or issues, refer to the troubleshooting section or consult the Android KeyChain documentation.

