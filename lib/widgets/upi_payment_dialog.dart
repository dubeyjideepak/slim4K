import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/activation_service.dart';
import '../services/auth_service.dart';
import '../services/quota_service.dart';
import 'terms_dialog.dart';

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

  // Default NeerTech Cashfree Details (dynamically synced from license server)
  static const String defaultPayeeName = 'NeerTech Technologies';
  static const String defaultLicenseAmount = '11999';
  static const String defaultOriginalAmount = '19999';
  static const String defaultLicense20tbAmount = '14999';
  static const String defaultLicense20tbOriginalAmount = '29999';
  static const String defaultSupportPhone = '+91 74588 29500';
  static const String defaultCashfreePaymentUrl = 'https://payments.cashfree.com/forms/slim4k';

  String _selectedPlan = '10tb'; // '10tb' or '20tb'
  String _payeeName = defaultPayeeName;
  String _licenseAmount = defaultLicenseAmount;
  String _originalAmount = defaultOriginalAmount;
  String _license20tbAmount = defaultLicense20tbAmount;
  String _license20tbOriginalAmount = defaultLicense20tbOriginalAmount;
  String _supportPhone = defaultSupportPhone;
  String _cashfreePaymentUrl = defaultCashfreePaymentUrl;

  String get _clientId => _activationService.currentActivation?.clientId ?? '';

  bool get _is20TbPlan => _selectedPlan == '20tb';
  String get _currentAmount => _is20TbPlan ? _license20tbAmount : _licenseAmount;
  String get _currentOriginalAmount => _is20TbPlan ? _license20tbOriginalAmount : _originalAmount;
  String get _currentPlanQuota => _is20TbPlan ? '20.0 TB' : '10.0 TB';
  String get _currentPlanValidity => _is20TbPlan ? '2 Years' : '1 Year';

  String _formatAmount(String val) {
    final numVal = int.tryParse(val);
    if (numVal != null) {
      return numVal.toString().replaceAllMapped(
        RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))'),
        (Match m) => '${m[1]},',
      );
    }
    return val;
  }

  String get _formattedAmount => _formatAmount(_currentAmount);
  String get _formattedOriginalAmount => _formatAmount(_currentOriginalAmount);

  String get _currentPaymentUrl {
    var targetUrl = _cashfreePaymentUrl;
    final separator = targetUrl.contains('?') ? '&' : '?';
    final queryParams = <String>[];
    final user = AuthService().currentUser;
    if (user != null && user.email.isNotEmpty) {
      queryParams.add('customer_email=${Uri.encodeComponent(user.email)}');
    }
    if (_clientId.isNotEmpty) {
      queryParams.add('customer_id=${Uri.encodeComponent(_clientId)}');
    }
    queryParams.add('plan=$_selectedPlan');
    queryParams.add('amount=$_currentAmount');
    return '$targetUrl$separator${queryParams.join('&')}';
  }

  @override
  void initState() {
    super.initState();
    // Load dynamic pricing and payment configurations
    _loadDynamicPricingConfig();

    // Start automated 3-second background polling for zero-key auto-activation
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isActivated && !_isChecking) {
        _checkPaymentAndAutoActivate(isBackground: true);
      }
    });
  }

  /// Loads real-time pricing and Cashfree links dynamically from cloud license server
  Future<void> _loadDynamicPricingConfig() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);

      // 1. Fetch global pricing document
      final globalUri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/global_pricing?key=${QuotaService.apiKey}',
      );
      final req = await client.getUrl(globalUri);
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final body = await utf8.decoder.bind(resp).join();
        final doc = jsonDecode(body) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};

        final amt = fields['license_amount']?['stringValue'] ?? fields['license_amount']?['integerValue']?.toString();
        final origAmt = fields['original_amount']?['stringValue'] ?? fields['original_amount']?['integerValue']?.toString();
        final amt20 = fields['license_20tb_amount']?['stringValue'] ?? fields['license_20tb_amount']?['integerValue']?.toString();
        final origAmt20 = fields['license_20tb_original_amount']?['stringValue'] ?? fields['license_20tb_original_amount']?['integerValue']?.toString();
        final cfUrl = fields['cashfree_payment_url']?['stringValue'];
        final payee = fields['payee_name']?['stringValue'];
        final phone = fields['support_phone']?['stringValue'];

        if (mounted) {
          setState(() {
            // Guard against legacy test price of '9'
            if (amt != null && amt.isNotEmpty && amt != '9') {
              _licenseAmount = amt;
            } else if (amt == '9') {
              _licenseAmount = '11999';
            }
            if (origAmt != null && origAmt.isNotEmpty) {
              _originalAmount = origAmt;
            } else {
              _originalAmount = '19999';
            }
            if (amt20 != null && amt20.isNotEmpty) {
              _license20tbAmount = amt20;
            }
            if (origAmt20 != null && origAmt20.isNotEmpty) {
              _license20tbOriginalAmount = origAmt20;
            }
            if (cfUrl != null && cfUrl.isNotEmpty) _cashfreePaymentUrl = cfUrl;
            if (payee != null && payee.isNotEmpty) _payeeName = payee;
            if (phone != null && phone.isNotEmpty) _supportPhone = phone;
          });
        }
      }

      // 2. Also check if client has an individual custom discount or price override
      if (_clientId.isNotEmpty) {
        final clientUri = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/$_clientId?key=${QuotaService.apiKey}',
        );
        final clientReq = await client.getUrl(clientUri);
        final clientResp = await clientReq.close();
        if (clientResp.statusCode == 200) {
          final clientBody = await utf8.decoder.bind(clientResp).join();
          final clientDoc = jsonDecode(clientBody) as Map<String, dynamic>;
          final clientFields = clientDoc['fields'] as Map<String, dynamic>? ?? {};

          final clientAmt = clientFields['license_amount']?['stringValue'] ?? clientFields['license_amount']?['integerValue']?.toString();
          final clientOrigAmt = clientFields['original_amount']?['stringValue'] ?? clientFields['original_amount']?['integerValue']?.toString();
          final clientCfUrl = clientFields['cashfree_payment_url']?['stringValue'];

          if (mounted) {
            setState(() {
              if (clientAmt != null && clientAmt.isNotEmpty && clientAmt != '9') {
                _licenseAmount = clientAmt;
              }
              if (clientOrigAmt != null && clientOrigAmt.isNotEmpty) {
                _originalAmount = clientOrigAmt;
              }
              if (clientCfUrl != null && clientCfUrl.isNotEmpty) _cashfreePaymentUrl = clientCfUrl;
            });
          }
        }
      }

      client.close();
    } catch (e) {
      debugPrint('Dynamic pricing config sync offline/fallback: $e');
    }
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
      bool activated = false;
      String activatedLicenseId = 'UPI-AUTO-$_clientId';
      int quotaBytes = QuotaService.defaultQuotaBytes;
      int validityDays = 365;

      // 1. Check Firestore client document directly: apps/slim4k/clients/{clientId}
      if (_clientId.isNotEmpty) {
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

          if (isLicenseActivated || paymentStatus == 'PAID' || paymentStatus == 'SUCCESS') {
            activated = true;
            quotaBytes = int.tryParse(fields['quota_limit_bytes']?['integerValue']?.toString() ?? '') ??
                QuotaService.defaultQuotaBytes;
            validityDays = int.tryParse(fields['validity_days']?['integerValue']?.toString() ?? '') ?? 365;
            activatedLicenseId = fields['internal_license_id']?['stringValue'] ?? 'UPI-AUTO-$_clientId';
          }
        }
      }

      // 2. Also check logged-in Google User document: apps/slim4k/clients/user_{emailDocId}
      final currentUser = AuthService().currentUser;
      if (!activated && currentUser != null && currentUser.email.isNotEmpty) {
        final emailDocId = AuthService.emailToDocId(currentUser.email);
        final userUri = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/user_$emailDocId?key=${QuotaService.apiKey}',
        );
        final userReq = await client.getUrl(userUri);
        final userResp = await userReq.close();
        final userBody = await utf8.decoder.bind(userResp).join();

        if (userResp.statusCode == 200) {
          final userDoc = jsonDecode(userBody) as Map<String, dynamic>;
          final userFields = userDoc['fields'] as Map<String, dynamic>? ?? {};

          final isUserActivated = userFields['is_license_activated']?['booleanValue'] == true;
          final userPayStatus = userFields['payment_status']?['stringValue']?.toUpperCase();

          if (isUserActivated || userPayStatus == 'PAID' || userPayStatus == 'SUCCESS') {
            activated = true;
            quotaBytes = int.tryParse(userFields['quota_limit_bytes']?['integerValue']?.toString() ?? '') ??
                QuotaService.defaultQuotaBytes;
            validityDays = int.tryParse(userFields['validity_days']?['integerValue']?.toString() ?? '') ?? 365;
            activatedLicenseId = userFields['internal_license_id']?['stringValue'] ?? 'GOOGLE-$emailDocId';
          }
        }
      }

      // 3. Fallback broadcast check: if any payment succeeded within the active session window
      if (!activated) {
        final latestUri = Uri.parse(
          'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/latest_payment?key=${QuotaService.apiKey}',
        );
        final latestReq = await client.getUrl(latestUri);
        final latestResp = await latestReq.close();
        if (latestResp.statusCode == 200) {
          final latestBody = await utf8.decoder.bind(latestResp).join();
          final latestDoc = jsonDecode(latestBody) as Map<String, dynamic>;
          final latestFields = latestDoc['fields'] as Map<String, dynamic>? ?? {};

          final status = latestFields['payment_status']?['stringValue']?.toUpperCase();
          final paidAtStr = latestFields['paid_at']?['stringValue'];
          final paidLicenseId = latestFields['internal_license_id']?['stringValue'] ?? 'UPI-AUTO-$_clientId';

          if (status == 'PAID' && paidAtStr != null) {
            final paidAt = DateTime.tryParse(paidAtStr);
            // Check if payment was confirmed within the last 20 minutes
            if (paidAt != null && DateTime.now().difference(paidAt).inMinutes < 20) {
              activated = true;
              activatedLicenseId = paidLicenseId;
              final amtVal = int.tryParse(latestFields['amount']?['stringValue'] ?? latestFields['amount']?['integerValue']?.toString() ?? '') ?? 0;
              final is20Tb = amtVal >= 14990;
              quotaBytes = is20Tb ? 21990232555520 : QuotaService.defaultQuotaBytes;
              validityDays = is20Tb ? 730 : 365;

              // Immediately write activation back to this Google account in Firestore
              if (currentUser != null && currentUser.email.isNotEmpty) {
                final emailDocId = AuthService.emailToDocId(currentUser.email);
                final activateUserUri = Uri.parse(
                  'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/user_$emailDocId'
                  '?updateMask.fieldPaths=is_license_activated&updateMask.fieldPaths=payment_status&updateMask.fieldPaths=quota_limit_bytes&updateMask.fieldPaths=quota_limit_tb&updateMask.fieldPaths=validity_days&updateMask.fieldPaths=internal_license_id&updateMask.fieldPaths=max_active_devices&key=${QuotaService.apiKey}',
                );
                final patchUserReq = await client.patchUrl(activateUserUri);
                patchUserReq.headers.contentType = ContentType.json;
                patchUserReq.write(jsonEncode({
                  'fields': {
                    'is_license_activated': {'booleanValue': true},
                    'payment_status': {'stringValue': 'PAID'},
                    'quota_limit_bytes': {'integerValue': quotaBytes.toString()},
                    'quota_limit_tb': {'doubleValue': is20Tb ? 20.0 : 10.0},
                    'validity_days': {'integerValue': validityDays.toString()},
                    'max_active_devices': {'integerValue': '1'},
                    'internal_license_id': {'stringValue': activatedLicenseId},
                  }
                }));
                final patchUserResp = await patchUserReq.close();
                await patchUserResp.drain();
              }
            }
          }
        }
      }

      if (activated) {
        _pollingTimer?.cancel();

        // Unlock quota locally on this machine
        await _quotaService.activateLicense(
          licenseKey: activatedLicenseId,
          validityDays: validityDays,
          quotaBytes: quotaBytes,
        );

        // Also register seat with Google account if logged in
        if (currentUser != null && _clientId.isNotEmpty) {
          await _quotaService.syncWithGoogleAccount(user: currentUser, clientId: _clientId);
        }

        final quotaTbDisplay = (quotaBytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(0);
        if (mounted) {
          setState(() {
            _isActivated = true;
            _isChecking = false;
            _statusFeedback = '🎉 Payment Confirmed! $quotaTbDisplay TB Studio License is now ACTIVE.';
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

  void _openCashfreeCheckout() {
    final targetUrl = _currentPaymentUrl;

    Clipboard.setData(ClipboardData(text: targetUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening secure Cashfree checkout in your browser...'),
        backgroundColor: Color(0xFF00E5FF),
        duration: Duration(seconds: 3),
      ),
    );
    try {
      if (!kIsWeb && Platform.isWindows) {
        Process.run('powershell', ['-NoProfile', '-Command', 'Start-Process', '"$targetUrl"']);
      } else if (!kIsWeb && Platform.isMacOS) {
        Process.run('open', [targetUrl]);
      } else if (!kIsWeb && Platform.isLinux) {
        Process.run('xdg-open', [targetUrl]);
      }
    } catch (_) {}
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
                      _isActivated ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
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
                                  ? '${QuotaService.defaultTrialLimitGb.toStringAsFixed(0)} GB Free Trial Finished'
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
                              ? 'Your $_currentPlanQuota Studio 4K License is now permanently bound to this computer.'
                              : 'Secure Online Payment via Cashfree Gateway (Auto-Activates Without Key)',
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

              // Plan Selector: 10 TB (1 Year) vs 20 TB (2 Years)
              if (!_isActivated) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      // Option 1: 10 TB Plan
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (_selectedPlan != '10tb') {
                              setState(() => _selectedPlan = '10tb');
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                            decoration: BoxDecoration(
                              color: _selectedPlan == '10tb'
                                  ? const Color(0xFF00E5FF).withOpacity(0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectedPlan == '10tb'
                                    ? const Color(0xFF00E5FF)
                                    : Colors.transparent,
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '10 TB Studio (1 Year)',
                                  style: TextStyle(
                                    color: _selectedPlan == '10tb' ? Colors.white : Colors.white60,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '₹${_formatAmount(_licenseAmount)}',
                                  style: TextStyle(
                                    color: _selectedPlan == '10tb' ? const Color(0xFF00E676) : Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Option 2: 20 TB Plan
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (_selectedPlan != '20tb') {
                              setState(() => _selectedPlan = '20tb');
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                            decoration: BoxDecoration(
                              color: _selectedPlan == '20tb'
                                  ? const Color(0xFF00E5FF).withOpacity(0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectedPlan == '20tb'
                                    ? const Color(0xFF00E5FF)
                                    : Colors.transparent,
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '20 TB Studio (2 Years)',
                                      style: TextStyle(
                                        color: _selectedPlan == '20tb' ? Colors.white : Colors.white60,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFD700).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFFFD700), width: 0.8),
                                      ),
                                      child: const Text(
                                        'BEST VALUE',
                                        style: TextStyle(
                                          color: Color(0xFFFFD700),
                                          fontSize: 7.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '₹${_formatAmount(_license20tbAmount)}',
                                  style: TextStyle(
                                    color: _selectedPlan == '20tb' ? const Color(0xFF00E676) : Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Two Column Body: Left = Cashfree QR Code, Right = Cashfree Actions & Live Radar
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LEFT: CASHFREE QR CODE & PRICING
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
                                Icon(Icons.shield_outlined, color: Color(0xFF00E5FF), size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'CASHFREE SECURE CHECKOUT',
                                  style: TextStyle(color: Color(0xFF00E5FF), fontSize: 9.5, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // QR Code Container (Encodes Cashfree URL for Mobile Scan)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: QrImageView(
                              data: _currentPaymentUrl,
                              version: QrVersions.auto,
                              size: 190.0,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Price Badge with Strikethrough Original Price
                          Column(
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '₹$_formattedOriginalAmount',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: Colors.redAccent,
                                      decorationThickness: 2.0,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '₹$_formattedAmount',
                                    style: const TextStyle(
                                      color: Color(0xFF00E676),
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _is20TbPlan ? '/ 2 Years' : '/ Year',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00E676).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3)),
                                ),
                                child: Text(
                                  _is20TbPlan
                                      ? '50% OFF • 2 YEARS EXTENDED VALIDITY'
                                      : '40% OFF • LIMITED STUDIO OFFER',
                                  style: const TextStyle(
                                    color: Color(0xFF00E676),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Full $_currentPlanQuota 4K Video Slimming Quota',
                            style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                          ),
                          const SizedBox(height: 8),

                          const Text(
                            'Scan with phone camera to open Cashfree on mobile',
                            style: TextStyle(color: Colors.white70, fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'UPI • Cards • NetBanking • Wallets',
                            style: TextStyle(color: Colors.white38, fontSize: 9),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 18),

                  // RIGHT: CASHFREE ACTION & 100% KEYLESS AUTO-ACTIVATION FLOW
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
                                    ? 'Your payment was verified. $_currentPlanQuota ($_currentPlanValidity) Studio License has been automatically bound to this machine.'
                                    : 'Once you complete payment via Cashfree in your browser or on phone, this screen automatically unlocks itself. No key required!',
                                style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
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

                        // PRIMARY BUTTON: Open Cashfree Checkout
                        if (!_isActivated) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E5FF),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _openCashfreeCheckout,
                              icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                              label: Text(
                                'Pay ₹$_formattedAmount via Cashfree Checkout',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Terms of Service & License Policy consent link
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                'By proceeding, you agree to the ',
                                style: TextStyle(color: Colors.white38, fontSize: 10),
                              ),
                              InkWell(
                                onTap: () => showSlim4KTermsDialog(context),
                                child: const Text(
                                  'Slim4K Terms & License Policy',
                                  style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // SECONDARY ROW: Check Status & Copy Link
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 36,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                      foregroundColor: Colors.white70,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: _isChecking ? null : () => _checkPaymentAndAutoActivate(isBackground: false),
                                    icon: _isChecking
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.refresh_rounded, size: 15),
                                    label: const Text(
                                      'Check Status',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SizedBox(
                                  height: 36,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                      foregroundColor: Colors.white70,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: _currentPaymentUrl));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Cashfree Payment Link copied!'),
                                          backgroundColor: Color(0xFF00E5FF),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.copy_rounded, size: 14),
                                    label: const Text(
                                      'Copy Link',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
                                'Send payment screenshot or transaction ID to WhatsApp for instant confirmation:',
                                style: TextStyle(color: Colors.white60, fontSize: 10),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                '📱 $_supportPhone  •  $_payeeName',
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
