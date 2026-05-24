import 'package:universal_html/html.dart' as html;

Future<bool> checkNetworkConnectivity() async {
  try {
    return html.window.navigator.onLine ?? true;
  } catch (_) {
    return true;
  }
}
