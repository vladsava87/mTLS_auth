import 'dart:convert';
import 'package:flutter/services.dart';
import 'http_method_enum.dart';

class NativeCertificateRequestService {
  static const MethodChannel _channel =
      MethodChannel('mtls_certificate_picker');

  static final NativeCertificateRequestService _instance =
      NativeCertificateRequestService._internal();
  factory NativeCertificateRequestService() => _instance;
  NativeCertificateRequestService._internal();

  String? _loggedInUserId;

  String? get loggedInUserId => _loggedInUserId;

  void setLoggedInUserId(String userId) {
    _loggedInUserId = userId;
  }

  void clearLoggedInUserId() {
    _loggedInUserId = null;
  }

  void _handleCertificateRevocation() {
    clearLoggedInUserId();

    try {
      _channel.invokeMethod('clearCertificate');
    } catch (e) {
      // Ignore errors during cleanup
    }
  }

  bool _isCertificateRevocationError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('certificate') ||
        errorString.contains('ssl') ||
        errorString.contains('tls') ||
        errorString.contains('handshake') ||
        errorString.contains('certificate revoked') ||
        errorString.contains('certificate invalid');
  }

  void triggerCertificateRevocation() {
    _handleCertificateRevocation();
  }

  Future<Map<String, dynamic>> makeRequest({
    required String url,
    required HttpMethod method,
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    try {
      final requestHeaders = <String, String>{
        ...?headers,
      };

      if (_loggedInUserId != null) {
        requestHeaders['X-LoggedInUserId'] = _loggedInUserId!;
      }

      final result = await _channel.invokeMethod('makeRequestWithCertificate', {
        'url': url,
        'method': method.value,
        'headers': requestHeaders,
        'bodyJson': body == null ? null : jsonEncode(body),
      });

      if (result is Map) {
        final Map<String, dynamic> resultMap = {};
        result.forEach((key, value) {
          resultMap[key.toString()] = value;
        });
        return resultMap;
      }

      throw Exception('Invalid response format: $result');
    } catch (e) {
      if (_isCertificateRevocationError(e)) {
        _handleCertificateRevocation();
        throw Exception('Certificate revoked or invalid. Please log in again.');
      }
      throw Exception('Native certificate request failed: $e');
    }
  }

  Future<Map<String, dynamic>> makeApiRequest({
    required HttpMethod method,
    required String endpoint,
    required String baseUrl,
    Map<String, dynamic>? body,
    Map<String, String>? additionalHeaders,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?additionalHeaders,
    };

    return makeRequest(
      url: '$baseUrl$endpoint',
      method: method,
      headers: headers,
      body: body,
    );
  }

  Future<TResponse> makeTypedApiRequest<TRequest, TResponse>({
    required HttpMethod method,
    required String endpoint,
    required String baseUrl,
    TRequest? requestData,
    Map<String, String>? additionalHeaders,
    required TResponse Function(Map<String, dynamic>) fromMap,
  }) async {
    Map<String, dynamic>? body;
    if (requestData != null) {
      if (requestData is Map<String, dynamic>) {
        body = requestData;
      } else {
        try {
          body = (requestData as dynamic).toMap();
        } catch (e) {
          throw Exception(
              'Request data must have a toMap() method or be a Map<String, dynamic>');
        }
      }
    }

    final response = await makeRequest(
      url: '$baseUrl$endpoint',
      method: method,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...?additionalHeaders,
      },
      body: body,
    );

    if (isSuccessResponse(response)) {
      final responseData = getResponseData(response);
      final parsedData = parseResponseData(responseData);

      return fromMap(parsedData);
    } else {
      final statusCode = getStatusCode(response);
      final errorData = getResponseData(response);
      final errorMessage = getErrorMessage(statusCode, errorData);

      if (statusCode == 401 || statusCode == 403) {
        final errorDataString = errorData?.toString().toLowerCase() ?? '';
        if (errorDataString.contains('certificate') ||
            errorDataString.contains('ssl') ||
            errorDataString.contains('tls')) {
          _handleCertificateRevocation();
          throw Exception(
              'Certificate revoked or invalid. Please log in again.');
        }
        throw Exception(errorMessage);
      }

      throw Exception(errorMessage);
    }
  }

  Map<String, dynamic> parseResponseData(dynamic responseData) {
    if (responseData == null || responseData == '') {
      return {'success': true, 'message': 'Operation completed successfully'};
    }

    if (responseData is String) {
      if (responseData.isEmpty) {
        return {'success': true, 'message': 'Operation completed successfully'};
      }

      try {
        return Map<String, dynamic>.from(
            jsonDecode(responseData) as Map<Object?, Object?>);
      } catch (e) {
        throw Exception("Failed to parse JSON response: $e");
      }
    } else if (responseData is Map<String, dynamic>) {
      return responseData;
    } else if (responseData is Map) {
      final Map<String, dynamic> parsedData = {};
      responseData.forEach((key, value) {
        parsedData[key.toString()] = value;
      });
      return parsedData;
    } else {
      throw Exception("Invalid response format: ${responseData.runtimeType}");
    }
  }

  bool isSuccessResponse(Map<String, dynamic> response) {
    final statusCode = response['statusCode'] ?? 500;
    final success = response['success'];

    if (statusCode == 200) {
      return success == true || success == null;
    }

    return success == true && statusCode == 200;
  }

  int getStatusCode(Map<String, dynamic> response) {
    return response['statusCode'] ?? 500;
  }

  dynamic getResponseData(Map<String, dynamic> response) {
    return response['data'];
  }

  String getErrorMessage(int statusCode, dynamic errorData) {
    switch (statusCode) {
      case 404:
        return "API is not available/offline";
      case 403:
        return "Access forbidden - check certificate";
      case 401:
        return "Incorrect or invalid username";
      default:
        return "Server error: ${errorData ?? 'Unknown error'}";
    }
  }
}

