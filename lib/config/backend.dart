/// Backend API configuration.
class BackendConfig {
  BackendConfig._();

  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://parishrecord-backend.onrender.com',
  );
}
