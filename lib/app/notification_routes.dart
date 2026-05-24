import '../models/notification.dart';

/// Notification inbox route for each signed-in role.
String notificationsRouteForRole(String? role) {
  switch ((role ?? '').trim().toLowerCase()) {
    case 'admin':
      return '/admin/notifications';
    case 'finance':
      return '/finance/notifications';
    case 'staff':
      return '/staff/notifications';
    case 'parishioner':
    case 'user':
    default:
      return '/user/notifications';
  }
}

/// Default dashboard route for a role (used when a notification has no tap target).
String dashboardRouteForRole(String? role) {
  switch ((role ?? '').trim().toLowerCase()) {
    case 'admin':
      return '/admin/dashboard';
    case 'finance':
      return '/finance/dashboard';
    case 'staff':
      return '/staff/dashboard';
    case 'parishioner':
    case 'user':
    default:
      return '/user/dashboard';
  }
}

/// Donations ledger for finance/admin.
String? donationsRouteForRole(String? role) {
  switch ((role ?? '').trim().toLowerCase()) {
    case 'finance':
      return '/finance/donations';
    case 'admin':
      return '/admin/donations';
    default:
      return null;
  }
}

/// Certificate fee payments for finance/admin.
String? certificateFeesRouteForRole(String? role) {
  switch ((role ?? '').trim().toLowerCase()) {
    case 'finance':
      return '/finance/certificate-fees';
    case 'admin':
      return '/admin/certificate-fees';
    default:
      return null;
  }
}

/// Records list route for staff/admin when a notification references records.
String recordsRouteForRole(String? role) {
  switch ((role ?? '').trim().toLowerCase()) {
    case 'admin':
      return '/admin/records';
    case 'staff':
      return '/staff/records';
    default:
      return '/user/sacraments';
  }
}

/// OCR upload route for staff/admin.
String ocrRouteForRole(String? role) {
  switch ((role ?? '').trim().toLowerCase()) {
    case 'admin':
      return '/admin/ocr/upload';
    case 'staff':
      return '/staff/ocr/upload';
    default:
      return '/user/dashboard';
  }
}

/// Requests inbox for staff/admin vs parishioner.
String requestsRouteForRole(String? role, {String? requestId}) {
  final id = requestId?.trim();
  switch ((role ?? '').trim().toLowerCase()) {
    case 'admin':
      return '/admin/requests';
    case 'staff':
      return '/staff/requests';
    default:
      if (id != null && id.isNotEmpty) return '/user/requests/$id';
      return '/user/requests';
  }
}

bool _isDonationNotification(String type, String combined) {
  return type == 'donation' ||
      type == 'online_donation' ||
      type == 'cash_donation' ||
      combined.contains('donation');
}

String? _mapSharedFinanceAdminRoute(String route, String? role) {
  final normalized = route.toLowerCase();

  if (normalized == '/donations' ||
      normalized == '/admin/donations' ||
      normalized == '/finance/donations') {
    return donationsRouteForRole(role);
  }

  if (normalized == '/admin/certificate-fees' ||
      normalized == '/finance/certificate-fees' ||
      normalized == '/certificate-fees') {
    return certificateFeesRouteForRole(role);
  }

  return null;
}

/// Ensures [route] is allowed for [role]; maps cross-shell paths when possible.
String? sanitizeNotificationRoute(String? route, String? role) {
  final r = route?.trim();
  if (r == null || r.isEmpty || !r.startsWith('/')) return null;

  final normalizedRole = (role ?? '').trim().toLowerCase();

  final shared = _mapSharedFinanceAdminRoute(r, role);
  if (shared != null) return shared;

  // Role-specific shells — block cross-role navigation.
  if (r.startsWith('/admin/')) {
    if (normalizedRole == 'admin') return r;
    if (normalizedRole == 'finance') {
      return donationsRouteForRole(role) ??
          certificateFeesRouteForRole(role) ??
          dashboardRouteForRole(role);
    }
    return notificationsRouteForRole(role);
  }
  if (r.startsWith('/staff/')) {
    return normalizedRole == 'staff' || normalizedRole == 'admin' ? r : null;
  }
  if (r.startsWith('/finance/')) {
    if (normalizedRole == 'finance') return r;
    if (normalizedRole == 'admin') {
      return donationsRouteForRole(role) ??
          certificateFeesRouteForRole(role) ??
          dashboardRouteForRole(role);
    }
    return null;
  }
  if (r.startsWith('/user/')) {
    return normalizedRole == 'parishioner' ||
            normalizedRole == 'user' ||
            normalizedRole.isEmpty
        ? r
        : null;
  }

  // Shared / legacy paths
  if (r == '/notifications') return notificationsRouteForRole(role);
  if (r == '/dashboard') return dashboardRouteForRole(role);
  if (r.startsWith('/records/certificate-request')) {
    return '/records/certificate-request?user=1';
  }

  return r;
}

/// Destination when the user taps a notification row (null = inbox only).
String? resolveNotificationTapRoute({
  required LocalNotification notification,
  required String? userRole,
}) {
  final explicit = sanitizeNotificationRoute(notification.route, userRole);
  if (explicit != null) return explicit;

  final type = (notification.type ?? '').trim().toLowerCase();
  final title = notification.title.toLowerCase();
  final body = notification.body.toLowerCase();
  final resourceId = notification.resourceId?.trim();
  final combined = '$type $title $body';
  final isDonation = _isDonationNotification(type, combined);

  if (type == 'certificate_fee') {
    return certificateFeesRouteForRole(userRole);
  }

  if (isDonation) {
    return donationsRouteForRole(userRole);
  }

  if (type == 'request' ||
      combined.contains('request') ||
      (combined.contains('certificate') && type != 'certificate_fee')) {
    return requestsRouteForRole(userRole, requestId: resourceId);
  }

  if (type == 'appointment' ||
      type == 'booking' ||
      combined.contains('appointment')) {
    return '/user/mass-schedule';
  }

  if (type == 'household' || combined.contains('household')) {
    return '/user/profile';
  }

  if (type == 'announcement' || combined.contains('announcement')) {
    final role = (userRole ?? '').trim().toLowerCase();
    if (role == 'admin') return '/admin/announcements';
    return '/user/announcements';
  }

  if (type == 'ocr' ||
      combined.contains('ocr') ||
      combined.contains('scan')) {
    return ocrRouteForRole(userRole);
  }

  if (type == 'record' ||
      type == 'records' ||
      combined.contains('sacrament') ||
      combined.contains('baptism') ||
      combined.contains('marriage')) {
    return recordsRouteForRole(userRole);
  }

  return null;
}

bool notificationHasTapTarget(LocalNotification notification, String? userRole) {
  return resolveNotificationTapRoute(
        notification: notification,
        userRole: userRole,
      ) !=
      null;
}
