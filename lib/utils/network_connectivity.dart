import 'network_connectivity_io.dart'
    if (dart.library.html) 'network_connectivity_web.dart' as connectivity;

Future<bool> isNetworkOnline() => connectivity.checkNetworkConnectivity();
