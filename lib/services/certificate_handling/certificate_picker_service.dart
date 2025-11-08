import 'package:flutter/services.dart';

class CertificatePickerService {
  static const MethodChannel _channel =
      MethodChannel('mtls_certificate_picker');

  static Future<String?> pickCertificate() async {
    try {
      final result = await _channel.invokeMethod('pickCertificate');
      return result as String?;
    } catch (e) {
      throw Exception('Failed to pick certificate: $e');
    }
  }

  static Future<bool> setupClientAuth(String alias) async {
    try {
      final result =
          await _channel.invokeMethod('setupClientAuth', {'alias': alias});
      return result as bool;
    } catch (e) {
      throw Exception('Failed to setup client authentication: $e');
    }
  }

  static Future<bool> isCertificateAvailable(String alias) async {
    try {
      final result = await _channel
          .invokeMethod('isCertificateAvailable', {'alias': alias});
      return result as bool;
    } catch (e) {
      throw Exception('Failed to check certificate availability: $e');
    }
  }

  static Future<String?> getSelectedAlias() async {
    try {
      final result = await _channel.invokeMethod('getSelectedAlias');
      return result as String?;
    } catch (e) {
      throw Exception('Failed to get selected alias: $e');
    }
  }

  static Future<void> clearCertificate() async {
    try {
      await _channel.invokeMethod('clearCertificate');
    } catch (e) {
      throw Exception('Failed to clear certificate: $e');
    }
  }

  static Future<List<String>> listAvailableCertificates() async {
    try {
      final result = await _channel.invokeMethod('listAvailableCertificates');
      return List<String>.from(result);
    } catch (e) {
      throw Exception('Failed to list certificates: $e');
    }
  }

  static Future<String?> requestCertificateAccess() async {
    try {
      final result = await _channel.invokeMethod('requestCertificateAccess');
      return result as String?;
    } catch (e) {
      throw Exception('Failed to request certificate access: $e');
    }
  }

  static Future<String?> selectCertificate() async {
    try {
      final result = await _channel.invokeMethod('selectCertificate');
      return result as String?;
    } catch (e) {
      throw Exception('Failed to select certificate: $e');
    }
  }
}

