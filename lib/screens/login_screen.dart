import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/keychain_service.dart';
import '../services/quota_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final QuotaService _quotaService = QuotaService();
  final KeychainService _keychainService = KeychainService();

  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _licCtrl = TextEditingController();

  bool _isSigningIn = false;
  String _statusMessage = '';
  String _hardwareClientId = '';
  bool _showManualEntry = false;

  @override
  void initState() {
    super.initState();
    _loadHardwareId();
  }

  Future<void> _loadHardwareId() async {
    final id = await _keychainService.getClientId() ?? '';
    if (mounted) {
      setState(() => _hardwareClientId = id);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _licCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isSigningIn = true;
      _statusMessage = 'Launching Google Sign-In in your browser...';
    });

    try {
      final profile = await _authService.signInWithGoogle(
        hardwareClientId: _hardwareClientId,
      );

      if (profile != null && mounted) {
        _navigateToHome(profile);
      } else {
        if (mounted) {
          setState(() {
            _isSigningIn = false;
            _statusMessage = 'Sign-in cancelled or timed out. Please try again.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
          _statusMessage = 'Browser sign-in issue. You can enter your email directly below.';
        });
      }
    }
  }

  Future<void> _handleDirectEmailSignIn() async {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Google email address'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSigningIn = true;
      _statusMessage = 'Connecting account and checking 10 TB quota...';
    });

    try {
      final profile = await _authService.signInWithGoogle(
        hardwareClientId: _hardwareClientId,
        preferredEmail: email,
      );

      if (profile != null && mounted) {
        _navigateToHome(profile);
      } else {
        if (mounted) {
          setState(() {
            _isSigningIn = false;
            _statusMessage = 'Could not verify account. Please try again.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
          _statusMessage = 'Error connecting: $e';
        });
      }
    }
  }

  Future<void> _handleLicenseKeyRedemption() async {
    final rawKey = _licCtrl.text.trim().toUpperCase();
    if (rawKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your license key (e.g. LIC-XXXXXXXX)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSigningIn = true;
      _statusMessage = 'Verifying license key with cloud...';
    });

    try {
      final success = await _quotaService.redeemLicenseKey(
        licenseKey: rawKey,
        clientId: _hardwareClientId,
      );

      if (success && mounted) {
        // Create authenticated profile for key holder
        final profile = UserProfile(
          uid: 'key_${rawKey.toLowerCase()}',
          email: 'license@${rawKey.toLowerCase()}.studio',
          displayName: 'Studio License ($rawKey)',
          photoUrl: null,
          loggedInAt: DateTime.now(),
        );
        await _keychainService.setGoogleUserProfile(profile);
        await _authService.initialize();
        if (mounted) {
          _navigateToHome(profile);
        }
      } else {
        if (mounted) {
          setState(() {
            _isSigningIn = false;
            _statusMessage = 'Invalid or expired license key. Please check your invoice.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('License key not found or expired'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
          _statusMessage = 'Redemption error: $e';
        });
      }
    }
  }

  void _navigateToHome(UserProfile profile) {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D13),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF30363D)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.04),
                    blurRadius: 80,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // App Brand Header
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.video_collection_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Slim4K Studio',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Professional 10x 4K UHD Video Compressor',
                    style: TextStyle(
                      color: Color(0xFF8B949E),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Required Notice Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_user_rounded, color: Color(0xFF00E5FF), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Sign in with your Google account to unlock your 10 TB Studio quota, activate hardware acceleration, and sync licenses across workstations.',
                            style: TextStyle(
                              color: Color(0xFFC9D1D9),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Primary Google Sign-In Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isSigningIn ? null : _handleGoogleSignIn,
                      child: _isSigningIn
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.black87,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Connecting...',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.network(
                                  'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png',
                                  width: 20,
                                  height: 20,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.login_rounded,
                                    size: 20,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Sign in with Google',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  if (_statusMessage.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _statusMessage.contains('✓')
                            ? const Color(0xFF00E676)
                            : (_statusMessage.contains('Error') || _statusMessage.contains('Invalid')
                                ? Colors.redAccent
                                : const Color(0xFF00E5FF)),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),

                  // Toggle for manual options
                  InkWell(
                    onTap: () => setState(() => _showManualEntry = !_showManualEntry),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _showManualEntry
                                ? 'Hide Direct Entry Options'
                                : 'Or Link by Google Email / License Key',
                            style: const TextStyle(
                              color: Color(0xFF8B949E),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(
                            _showManualEntry ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                            color: const Color(0xFF8B949E),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Collapsible Direct Options
                  if (_showManualEntry) ...[
                    const SizedBox(height: 18),
                    const Row(
                      children: [
                        Expanded(child: Divider(color: Color(0xFF30363D))),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'ENTER GOOGLE EMAIL',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Color(0xFF30363D))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'e.g. jobwithios@gmail.com',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        prefixIcon: const Icon(Icons.email_outlined, color: Colors.white54, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00E5FF),
                          side: const BorderSide(color: Color(0xFF00E5FF)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isSigningIn ? null : _handleDirectEmailSignIn,
                        child: const Text(
                          'Verify Email & Unlock',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Row(
                      children: [
                        Expanded(child: Divider(color: Color(0xFF30363D))),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'OR REDEEM LICENSE KEY',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Color(0xFF30363D))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _licCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        letterSpacing: 1.0,
                      ),
                      decoration: InputDecoration(
                        hintText: 'LIC-XXXXXXXXXXXX',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        prefixIcon: const Icon(Icons.vpn_key_outlined, color: Colors.white54, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF30363D)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF00E676)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00E676),
                          side: const BorderSide(color: Color(0xFF00E676)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isSigningIn ? null : _handleLicenseKeyRedemption,
                        child: const Text(
                          'Redeem Standalone Key',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),
                  const Divider(color: Color(0xFF30363D)),
                  const SizedBox(height: 12),

                  // Machine ID Display
                  if (_hardwareClientId.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Workstation: ${_hardwareClientId.length > 18 ? "${_hardwareClientId.substring(0, 18)}..." : _hardwareClientId}',
                          style: const TextStyle(
                            color: Color(0xFF8B949E),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _hardwareClientId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Workstation ID copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: const Icon(Icons.copy_rounded, color: Color(0xFF8B949E), size: 14),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
