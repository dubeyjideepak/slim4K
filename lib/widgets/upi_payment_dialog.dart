import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/activation_service.dart';
import '../services/quota_service.dart';

class UpiPaymentDialog extends StatefulWidget {
  final bool isTrialExpired;

  const UpiPaymentDialog({
    super.key,
    this.isTrialExpired = false,
  });

  @override
  State<UpiPaymentDialog> createState() => _UpiPaymentDialogState();
}

class _UpiPaymentDialogState extends State<UpiPaymentDialog> {
  final QuotaService _quotaService = QuotaService();
  final ActivationService _activationService = ActivationService();

  Timer? _pollingTimer;
  bool _isChecking = false;
  bool _isActivated = false;
  String? _statusFeedback;

  // Official NeerTech UPI Details
  static const String upiId = '7458829500@okaxis';
  static const String payeeName = 'NeerTech Technologies';
  static const String licenseAmount = '8999';
  static const String supportPhone = '+91 74588 29500';
  static const String cashfreePaymentUrl = 'https://payments.cashfree.com/links?code=Nb7rbehn28jg_AAAAAAAWrHQ';

  String get _clientId => _activationService.currentActivation?.clientId ?? '';

  String get _upiPayload {
    final note = 'SLIM-$_clientId';
    return 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(payeeName)}&am=$licenseAmount&cu=INR&tn=${Uri.encodeComponent(note)}';
  }

  @override
  void initState() {
    super.initState();
    // Start automated 3-second background polling for zero-key auto-activation
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isActivated && !_isChecking) {
        _checkPaymentAndAutoActivate(isBackground: true);
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPaymentAndAutoActivate({bool isBackground = false}) async {
    if (_isActivated) return;

    if (!isBackground) {
      setState(() {
        _isChecking = true;
        _statusFeedback = 'Checking payment status with server...';
      });
    }

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);

      // Check Firestore client document directly: apps/slim4k/clients/{clientId}
      final uri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/$_clientId?key=${QuotaService.apiKey}',
      );

      final req = await client.getUrl(uri);
      final resp = await req.close();
      final body = await utf8.decoder.bind(resp).join();

      if (resp.statusCode == 200) {
        final doc = jsonDecode(body) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};

        final isLicenseActivated = fields['is_license_activated']?['booleanValue'] == true;
        final paymentStatus = fields['payment_status']?['stringValue']?.toUpperCase();
        final quotaBytes = int.tryParse(fields['quota_limit_bytes']?['integerValue']?.toString() ?? '') ??
            QuotaService.defaultQuotaBytes;
        final validityDays = int.tryParse(fields['validity_days']?['integerValue']?.toString() ?? '') ?? 365;
        final internalLicenseId = fields['internal_license_id']?['stringValue'] ?? 'UPI-AUTO-$_clientId';

        if (isLicenseActivated || paymentStatus == 'PAID' || paymentStatus == 'SUCCESS') {
          _pollingTimer?.cancel();

          // Unlock 10 TB quota locally on this machine
          await _quotaService.activateLicense(
            licenseKey: internalLicenseId,
            validityDays: validityDays,
            quotaBytes: quotaBytes,
          );

          if (mounted) {
            setState(() {
              _isActivated = true;
              _isChecking = false;
              _statusFeedback = '🎉 Payment Confirmed! 10 TB Studio License is now ACTIVE.';
            });
          }

          client.close();

          // Smoothly close dialog after 1.8 seconds so user sees confirmation
          await Future.delayed(const Duration(milliseconds: 1800));
          if (mounted) {
            Navigator.of(context).pop(true);
          }
          return;
        }
      }

      client.close();
      if (!isBackground && mounted) {
        setState(() {
          _isChecking = false;
          _statusFeedback = 'Payment not detected yet. If you have completed payment, it activates within seconds.';
        });
      }
    } catch (e) {
      if (!isBackground && mounted) {
        setState(() {
          _isChecking = false;
          _statusFeedback = 'Connection check failed. Please check internet connection.';
        });
      }
    }
  }

  void _copyUpiId() {
    Clipboard.setData(const ClipboardData(text: upiId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('UPI ID copied: 7458829500@okaxis'),
        backgroundColor: Color(0xFF00E5FF),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _copyClientId() {
    Clipboard.setData(ClipboardData(text: _clientId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Machine ID copied to clipboard!'),
        backgroundColor: Color(0xFF00E5FF),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F141C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: _isActivated ? const Color(0xFF25D366) : const Color(0xFF00E5FF),
          width: 1.4,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (_isActivated ? const Color(0xFF25D366) : const Color(0xFF00E5FF)).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isActivated ? Icons.check_circle_rounded : Icons.qr_code_2_rounded,
                      color: _isActivated ? const Color(0xFF25D366) : const Color(0xFF00E5FF),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isActivated
                              ? 'License Activated Successfully!'
                              : (widget.isTrialExpired
                                  ? '2.0 GB Free Trial Finished'
                                  : 'NeerTech Slim4K Studio License'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isActivated
                              ? 'Your 10.0 TB Annual 4K License is now permanently bound to this computer.'
                              : 'Scan UPI QR to Unlock 10.0 TB Annual License (Auto-Activates Without Key)',
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Divider(color: Color(0xFF21262D), height: 1),
              const SizedBox(height: 18),

              // Two Column Body: Left = QR Code, Right = Auto-Activation Radar
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LEFT: UPI QR CODE
                  Expanded(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.flash_on_rounded, color: Color(0xFF00E5FF), size: 14),
                                SizedBox(width: 4),
                                Text(
                                  '0% EXTRA CHARGES • DIRECT UPI',
                                  style: TextStyle(color: Color(0xFF00E5FF), fontSize: 9.5, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // QR Code Container
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: QrImageView(
                              data: _upiPayload,
                              version: QrVersions.auto,
                              size: 190.0,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Price Badge
                          const Text(
                            '₹8,999 / Year',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'Full 10.0 TB 4K Video Slimming Quota',
                            style: TextStyle(color: Colors.white54, fontSize: 10.5),
                          ),
                          const SizedBox(height: 10),

                          // UPI ID Copy Row
                          InkWell(
                            onTap: _copyUpiId,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy_rounded, color: Color(0xFF00E5FF), size: 13),
                                  SizedBox(width: 6),
                                  Text(
                                    upiId,
                                    style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Pay via PhonePe • GPay • Paytm • BHIM • Cred',
                            style: TextStyle(color: Colors.white38, fontSize: 9),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 18),

                  // RIGHT: 100% KEYLESS AUTO-ACTIVATION FLOW
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Live Auto-Listening Status Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _isActivated
                                ? const Color(0xFF25D366).withOpacity(0.12)
                                : const Color(0xFF00E5FF).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isActivated
                                  ? const Color(0xFF25D366).withOpacity(0.4)
                                  : const Color(0xFF00E5FF).withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (_isActivated)
                                    const Icon(Icons.check_circle, color: Color(0xFF25D366), size: 18)
                                  else
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                                    ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isActivated ? 'ACTIVATION COMPLETE' : 'AUTO-DETECTION ACTIVE',
                                    style: TextStyle(
                                      color: _isActivated ? const Color(0xFF25D366) : const Color(0xFF00E5FF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isActivated
                                    ? 'Your payment was verified. 10 TB Annual License has been automatically bound to this machine.'
                                    : 'Once you scan and complete the UPI payment on your phone, this screen will automatically unlock itself. No key required!',
                                style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Machine Hardware ID Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hardware Machine ID (Locked to this PC):',
                                style: TextStyle(color: Colors.white54, fontSize: 10.5),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      _clientId,
                                      style: const TextStyle(
                                        color: Color(0xFF00E5FF),
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: _copyClientId,
                                    child: const Icon(Icons.copy_rounded, color: Color(0xFF00E5FF), size: 15),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        if (_statusFeedback != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _statusFeedback!,
                            style: TextStyle(
                              color: _isActivated ? const Color(0xFF25D366) : const Color(0xFF00E5FF),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // Manual Check Button
                        if (!_isActivated)
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E5FF),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _isChecking ? null : () => _checkPaymentAndAutoActivate(isBackground: false),
                              icon: _isChecking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                    )
                                  : const Icon(Icons.refresh_rounded, size: 18),
                              label: Text(
                                _isChecking ? 'Checking Server...' : 'I Have Paid — Check Status Now',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ),

                        if (!_isActivated) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 38,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
                                foregroundColor: const Color(0xFF00E5FF),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () {
                                Clipboard.setData(const ClipboardData(text: cashfreePaymentUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Cashfree Payment Link copied! Open in your browser.'),
                                    backgroundColor: Color(0xFF00E5FF),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                              label: const Text(
                                'Copy / Open Cashfree Online Checkout',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        // Instant WhatsApp Verification Box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161B22),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF25D366), size: 15),
                                  SizedBox(width: 6),
                                  Text(
                                    'Need Help / Instant Support?',
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Send payment screenshot or UTR number to WhatsApp for instant confirmation:',
                                style: TextStyle(color: Colors.white60, fontSize: 10),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                '📱 $supportPhone  •  NeerTech Technologies',
                                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
