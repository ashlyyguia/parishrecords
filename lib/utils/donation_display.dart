import '../config/parish_payment_config.dart';

/// Payment method id from a donation document (online or manual).
String donationPaymentMethodId(Map<String, dynamic> d) {
  final raw = (d['payment_method'] ?? d['method'] ?? 'cash').toString().trim();
  return raw.isEmpty ? 'cash' : raw;
}

String formatPaymentMethod(String method) {
  final id = method.trim().toLowerCase();
  final configured = ParishPaymentMethod.byId(id);
  if (configured != null) return configured.label;
  switch (id) {
    case 'gcash':
      return 'GCash';
    case 'maya':
      return 'Maya';
    case 'gotyme':
      return 'GoTyme';
    case 'cash':
      return 'Cash';
    case 'bank':
    case 'bank_transfer':
      return 'Bank Transfer';
    default:
      if (id.isEmpty) return 'Cash';
      return id.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return '${w[0].toUpperCase()}${w.substring(1)}';
      }).join(' ');
  }
}

String donationTypeLabel(Map<String, dynamic> d) {
  final type = (d['donation_type'] ?? d['campaign'] ?? '').toString().trim();
  return formatDonationTypeLabel(type);
}

/// Display label for donation / campaign keys (Projects, Certificate fees, etc.).
String formatDonationTypeLabel(String raw) {
  final id = raw.trim().toLowerCase();
  if (id.isEmpty) return 'General';
  switch (id) {
    case 'certificate':
      return 'Certificate fees';
    case 'tithes':
      return 'Tithes';
    case 'projects':
      return 'Projects';
    case 'outreach':
      return 'Outreach';
    case 'general':
      return 'General';
    default:
      return raw.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
      }).join(' ');
  }
}

bool isOnlineDonation(Map<String, dynamic> d) =>
    d['source']?.toString() == 'online' || d['online'] == true;

/// Admin Donations page: in-person cash only (not landing GCash / e-wallet).
bool isManualCashDonation(Map<String, dynamic> d) {
  if (isOnlineDonation(d)) return false;
  if (d['guest_donation'] == true) return false;
  if (d['amount_pending'] == true) return false;
  final method = donationPaymentMethodId(d).toLowerCase();
  return method == 'cash';
}

/// Admin Donations page: cash and online gifts (certificate fees have their own page).
List<Map<String, dynamic>> filterAdminDonations(
  List<Map<String, dynamic>> all,
) {
  return all.where((d) {
    final campaign = (d['campaign'] ?? '').toString().trim().toLowerCase();
    if (campaign == 'certificate') return false;
    return isManualCashDonation(d) || isOnlineDonation(d);
  }).toList();
}

/// Admin reports: in-person cash only (legacy helper).
List<Map<String, dynamic>> filterAdminCashDonations(
  List<Map<String, dynamic>> all,
) {
  return all.where((d) {
    final campaign = (d['campaign'] ?? '').toString().trim().toLowerCase();
    if (campaign == 'certificate') return false;
    return isManualCashDonation(d);
  }).toList();
}

String donationAmountLabel(Map<String, dynamic> d) {
  if (d['amount_pending'] == true) {
    return 'Pending (GCash)';
  }
  final amt = (d['amount'] as num?)?.toDouble() ?? 0;
  if (amt <= 0) return '—';
  return '₱${amt == amt.roundToDouble() ? amt.toStringAsFixed(0) : amt.toStringAsFixed(2)}';
}

String? donorEmail(Map<String, dynamic> d) {
  final e = d['donor_email']?.toString().trim();
  return (e == null || e.isEmpty) ? null : e;
}

String? donorPhone(Map<String, dynamic> d) {
  final p = d['donor_phone']?.toString().trim();
  return (p == null || p.isEmpty) ? null : p;
}
