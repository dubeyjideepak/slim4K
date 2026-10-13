import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/app_activation.dart';
import '../services/activation_service.dart';

class ActivationLockWidget extends StatefulWidget {
  final ClientActivation activation;
  final VoidCallback onReactivated;

  const ActivationLockWidget({
    super.key,
    required this.activation,
    required this.onReactivated,
  });

  @override
  State<ActivationLockWidget> createState() => _ActivationLockWidgetState();
}

class _ActivationLockWidgetState extends State<ActivationLockWidget> {
  final ActivationService _activationService = ActivationService();
  bool _isChecking = false;
  String? _statusFeedback;

  Future<void> _checkStatus() async {
    setState(() {
      _isChecking = true;
      _statusFeedback = null;
    });

    try {
      final updated = await _activationService.verifyAndSync(forceOnline: true);
      if (updated.isActive &&
          (updated.status == ActivationStatus.active ||
              updated.status == ActivationStatus.offlineGrace)) {
        widget.onReactivated();
      } else {
        setState(() {
          _statusFeedback = updated.status == ActivationStatus.deactivatedExpired
              ? 'Still disconnected or expired (>15 days). Please activate "is_active: true" on Firebase.'
              : 'Still marked inactive (is_active: false) on Firebase Console.';
        });
      }
    } catch (e) {
      setState(() {
        _statusFeedback = 'Connection failed: Please check internet connection.';
      });
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  void _copyClientId() {
    Clipboard.setData(ClipboardData(text: widget.activation.clientId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Client ID copied to clipboard!'),
        backgroundColor: Color(0xFF00E5FF),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final is15DayExpiry = widget.activation.status == ActivationStatus.deactivatedExpired;
    final primaryColor = is15DayExpiry ? Colors.amber : Colors.redAccent;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    return Scaffold(
      backgroundColor: const Color(0xFF090D13),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: primaryColor.withValues(alpha: 0.4), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.1),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: primaryColor.withValues(alpha: 0.4), width: 2),
                    ),
                    child: Icon(
                      is15DayExpiry ? Icons.timer_off_rounded : Icons.lock_outline_rounded,
                      color: primaryColor,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    is15DayExpiry ? '15-Day Offline Limit Exceeded' : 'App Deactivated',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),

                  // Subtitle explanation
                  Text(
                    is15DayExpiry
                        ? 'This client remained disconnected from Firestore for more than 15 days. As per security policy, access is locked until reactivated from Firebase.'
                        : 'Access for this client has been deactivated by administrator in Firebase Console.',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Metadata Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: Column(
                      children: [
                        _infoRow('App ID', widget.activation.appId),
                        const Divider(color: Color(0xFF21262D), height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Client ID',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            const Spacer(),
                            Flexible(
                              child: SelectableText(
                                widget.activation.clientId,
                                style: const TextStyle(
                                  color: Color(0xFF00E5FF),
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _copyClientId,
                              child: const Icon(Icons.copy_rounded, color: Color(0xFF00E5FF), size: 16),
                            ),
                          ],
                        ),
                        const Divider(color: Color(0xFF21262D), height: 18),
                        _infoRow('Platform', widget.activation.platform.toUpperCase()),
                        const Divider(color: Color(0xFF21262D), height: 18),
                        _infoRow('Last Heartbeat', dateFormat.format(widget.activation.lastHeartbeat.toLocal())),
                      ],
                    ),
                  ),

                  if (_statusFeedback != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _statusFeedback!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Reactivate Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isChecking ? null : _checkStatus,
                      icon: _isChecking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20),
                      label: Text(
                        _isChecking ? 'Checking Firestore...' : 'Check Status & Re-activate',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Firebase Console Admin Hint
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F242C),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.admin_panel_settings_outlined, color: Colors.white54, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Admin Step: Open Firebase Console > Firestore > apps/slim4k/clients > [client_id] and set is_active: true, then click Re-activate above.',
                            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
