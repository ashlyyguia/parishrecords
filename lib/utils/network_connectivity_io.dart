import 'dart:io';

Future<bool> checkNetworkConnectivity() async {
  try {
    final result = await InternetAddress.lookup('firestore.googleapis.com')
        .timeout(const Duration(seconds: 4));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
