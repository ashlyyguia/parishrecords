class BackendConfig {
  // Backend API base URL - update based on environment
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String apiBaseUrl = '$baseUrl/api';
  static const String adminUsersEndpoint = '$apiBaseUrl/admin/users';
}
