# mTLS Authentication Flutter Project

A standalone Flutter project demonstrating mutual TLS (mTLS) authentication with Android certificate picker integration.

## Overview

This project provides a complete implementation of:
- Android native certificate picker plugin
- OkHttp client with mTLS support
- Flutter/Dart service layer for certificate management
- State management with Riverpod
- Example UI demonstrating the functionality

## Project Structure

```
mTLS_auth/
├── android/
│   ├── app/
│   │   ├── build.gradle
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       └── kotlin/com/testapp/mtls_auth/
│   │           ├── MainActivity.kt
│   │           └── certificate_picker/
│   │               └── CertificatePickerPlugin.kt
│   ├── build.gradle
│   └── settings.gradle
├── lib/
│   ├── main.dart
│   ├── example_screen.dart
│   └── services/
│       └── certificate_handling/
│           ├── certificate_handling.dart
│           ├── certificate_picker_service.dart
│           ├── certificate_state_provider.dart
│           ├── http_method_enum.dart
│           └── native_certificate_request_service.dart
├── pubspec.yaml
└── README.md
```

## Setup

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Android Studio or Android SDK
- Android device or emulator (Android 4.0+)

### Installation

1. Navigate to the project directory:
```bash
cd mTLS_auth
```

2. Get Flutter dependencies:
```bash
flutter pub get
```

3. Ensure you have a `local.properties` file in the `android` directory with:
```properties
sdk.dir=/path/to/your/android/sdk
flutter.sdk=/path/to/your/flutter/sdk
```

4. Run the app:
```bash
flutter run
```

## Usage

### 1. Install Certificate

Before using the app, you need to install a client certificate on your Android device:

1. Transfer your `.p12` or `.pfx` certificate file to your device
2. Open the file on your device
3. Follow the system prompts to install the certificate
4. Set a password/pin for the certificate if prompted

### 2. Select Certificate in App

1. Launch the app
2. Tap "Select Certificate" button
3. Choose your certificate from the system dialog
4. The app will verify the certificate and show its status

### 3. Make API Requests

Once a certificate is selected and verified:

1. Update the `baseUrl` in `lib/example_screen.dart` to match your API endpoint
2. Tap "Make GET Request" or "Make POST Request"
3. The request will use mTLS authentication automatically

## Configuration

### Update API Base URL

In `lib/example_screen.dart`, update the `baseUrl` constant:

```dart
const baseUrl = 'https://your-api-url.com';
```

### Customize Certificate Common Names

In `CertificatePickerPlugin.kt`, you can modify the list of common certificate names to check:

```kotlin
val commonNames = listOf(
    "your-cert-name",
    "another-cert-name",
    // Add your certificate names here
)
```

## Features

- ✅ Automatic certificate selection from Android KeyChain
- ✅ Persistent certificate storage
- ✅ Certificate availability checking
- ✅ Custom OkHttp client with mTLS
- ✅ State management with Riverpod
- ✅ Error handling and certificate revocation detection
- ✅ Support for GET and POST requests
- ✅ Example UI demonstrating all functionality

## API Reference

### CertificatePickerService

- `pickCertificate()` - Automatically picks stored certificate
- `setupClientAuth(String alias)` - Sets up client authentication
- `isCertificateAvailable(String alias)` - Checks certificate availability
- `getSelectedAlias()` - Gets currently selected alias
- `clearCertificate()` - Clears selected certificate
- `listAvailableCertificates()` - Lists all available certificates
- `requestCertificateAccess()` - Requests certificate access permission
- `selectCertificate()` - Shows certificate picker dialog

### NativeCertificateRequestService

- `makeRequest({url, method, headers?, body?})` - Low-level request method
- `makeApiRequest({method, endpoint, baseUrl, body?, additionalHeaders?})` - High-level API request
- `makeTypedApiRequest<TRequest, TResponse>({...})` - Type-safe API request

### CertificateStateProvider

- `selectCertificate()` - Automatic certificate selection
- `selectCertificateManually()` - Manual certificate selection
- `clearCertificate()` - Clear certificate and reset state

## Troubleshooting

### Certificate Not Found

- Ensure the certificate is installed on the device
- Check that the certificate name matches one in the common names list
- Try selecting the certificate manually

### API Requests Failing

- Verify the certificate is selected and verified
- Check that the API endpoint supports mTLS
- Ensure the certificate matches the server's requirements
- Check network connectivity

### Build Errors

- Ensure `local.properties` is configured correctly
- Run `flutter clean` and `flutter pub get`
- Check that Android SDK and Flutter SDK paths are correct

## Documentation

For detailed documentation, see `CERTIFICATE_PICKER_DOCUMENTATION.md` in the parent directory.

## License

This project is provided as-is for demonstration purposes.

