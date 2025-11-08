import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'services/certificate_handling/certificate_handling.dart';

class ExampleScreen extends ConsumerWidget {
  const ExampleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final certificateState = ref.watch(certificateStateProvider);
    final certificateNotifier = ref.read(certificateStateProvider.notifier);
    final service = NativeCertificateRequestService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('mTLS Authentication Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Certificate Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Certificate Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Selected: ${certificateState.selectedAlias ?? "None"}'),
                    Text('Verified: ${certificateState.isCertificateVerified ? "Yes" : "No"}'),
                    if (certificateState.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Error: ${certificateState.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Certificate Actions
            ElevatedButton.icon(
              onPressed: () async {
                final success = await certificateNotifier.selectCertificate();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? 'Certificate selected successfully'
                          : 'Certificate selection failed'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.security),
              label: const Text('Select Certificate'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () async {
                final success =
                    await certificateNotifier.selectCertificateManually();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? 'Certificate selected successfully'
                          : 'Certificate selection failed'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.perm_device_information),
              label: const Text('Select Certificate Manually'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () async {
                await certificateNotifier.clearCertificate();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Certificate cleared'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear Certificate'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  final certificates =
                      await CertificatePickerService.listAvailableCertificates();
                  if (context.mounted) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Available Certificates'),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: certificates
                                .map((cert) => Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Text(cert),
                                    ))
                                .toList(),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.list),
              label: const Text('List Available Certificates'),
            ),
            const SizedBox(height: 24),

            // API Request Section
            const Text(
              'API Requests',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: certificateState.isCertificateVerified
                  ? () async {
                      try {
                        // Replace with your API base URL
                        const baseUrl = 'https://your-api-url.com';
                        final response = await service.makeApiRequest(
                          method: HttpMethod.get,
                          endpoint: '/api/test',
                          baseUrl: baseUrl,
                        );
                        if (context.mounted) {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('API Response'),
                              content: Text(
                                'Status: ${response['statusCode']}\n'
                                'Success: ${response['success']}\n'
                                'Data: ${response['data']}',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  : null,
              icon: const Icon(Icons.http),
              label: const Text('Make GET Request'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: certificateState.isCertificateVerified
                  ? () async {
                      try {
                        // Replace with your API base URL
                        const baseUrl = 'https://your-api-url.com';
                        final response = await service.makeApiRequest(
                          method: HttpMethod.post,
                          endpoint: '/api/test',
                          baseUrl: baseUrl,
                          body: {
                            'test': 'data',
                            'timestamp': DateTime.now().toIso8601String(),
                          },
                        );
                        if (context.mounted) {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('API Response'),
                              content: Text(
                                'Status: ${response['statusCode']}\n'
                                'Success: ${response['success']}\n'
                                'Data: ${response['data']}',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  : null,
              icon: const Icon(Icons.send),
              label: const Text('Make POST Request'),
            ),
            const SizedBox(height: 24),

            // Instructions
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Instructions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Install a client certificate on your Android device\n'
                      '2. Click "Select Certificate" to choose your certificate\n'
                      '3. Once verified, you can make API requests\n'
                      '4. Update the baseUrl in the code to match your API',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

