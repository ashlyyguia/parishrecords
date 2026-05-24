import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/parish_payment_config.dart';

/// Displays a payment QR (static image if available, otherwise generated).
class PaymentQrCard extends StatelessWidget {
  const PaymentQrCard({
    super.key,
    required this.method,
    this.qrSize = 240,
    this.compact = false,
  });

  final ParishPaymentMethod method;
  final double qrSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 20),
      decoration: BoxDecoration(
        color: method.brandColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: method.brandColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            method.label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: method.brandColor,
            ),
          ),
          if (method.instructions != null && !compact) ...[
            const SizedBox(height: 4),
            Text(
              method.instructions!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          SizedBox(height: compact ? 8 : 16),
          _QrDisplay(method: method, size: qrSize),
          SizedBox(height: compact ? 8 : 12),
          Text(
            method.accountName,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: method.accountNumber));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${method.label} number copied')),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    method.accountNumber,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.copy, size: 16, color: method.brandColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrDisplay extends StatelessWidget {
  const _QrDisplay({required this.method, required this.size});

  final ParishPaymentMethod method;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = method.qrAssetPath;
    if (asset != null && asset.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          asset,
          width: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => _generatedQr(),
        ),
      );
    }
    return _generatedQr();
  }

  Widget _generatedQr() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: QrImageView(
        data: method.qrPayload,
        version: QrVersions.auto,
        size: size,
        gapless: true,
        backgroundColor: Colors.white,
      ),
    );
  }
}
