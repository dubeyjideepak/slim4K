import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../models/app_activation.dart';
import '../models/user_profile.dart';
import '../models/video_task.dart';
import '../services/activation_service.dart';
import '../services/app_update_service.dart';
import '../services/auth_service.dart';
import '../services/compression_engine.dart';
import '../services/keychain_service.dart';
import '../services/quota_service.dart';
import '../widgets/activation_lock_widget.dart';
import '../widgets/comparison_player.dart';
import '../widgets/upi_payment_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CompressionEngine _engine = CompressionEngine();
  final ActivationService _activationService = ActivationService();
  final QuotaService _quotaService = QuotaService();
  final AuthService _authService = AuthService();
  final List<VideoTask> _tasks = [];
  String _activeEncoder = 'Detecting...';
  bool _isProcessingBatch = false;
  CompressionPreset _selectedPreset = CompressionPreset.slim10x;
  int _customBitrateKbps = 10000;

  // Activation & License State
  ClientActivation? _activation;
  bool _isActivationChecking = true;

  // Professional Videographer Options
  bool _isFolderArchiveMode = false;
  bool _saveFilesInPlace = true;
  ProjectScanResult? _projectScanResult;
  bool _generateProxies = false;
  bool _preserveOriginalAudio = true;
  bool _preserveTimecodes = true;
  final double _hddCostPerTbInr = 2500.0; // Standard external hard drive price (₹2,500/TB)

  @override
  void initState() {
    super.initState();
    _quotaService.addListener(_onQuotaUpdated);
    _authService.addListener(_onQuotaUpdated);
    _authService.initialize();
    _checkActivation();
    _detectEncoder();
    _checkInitialFile();
    _checkAppUpdates();
  }

  @override
  void dispose() {
    _quotaService.removeListener(_onQuotaUpdated);
    _authService.removeListener(_onQuotaUpdated);
    super.dispose();
  }

  void _onQuotaUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _checkActivation() async {
    setState(() => _isActivationChecking = true);
    final act = await _activationService.verifyAndSync();
    if (mounted) {
      setState(() {
        _activation = act;
        _isActivationChecking = false;
      });
    }
  }

  Future<void> _checkAppUpdates() async {
    try {
      final update = await AppUpdateService().checkForUpdates();
      if (mounted && update != null && update.isUpdateAvailable) {
        _showUpdateDialog(update);
      }
    } catch (_) {}
  }

  void _showUpdateDialog(AppUpdateInfo update) {
    showDialog(
      context: context,
      barrierDismissible: !update.isMandatory,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.system_update_alt, color: Color(0xFF00E5FF), size: 22),
            const SizedBox(width: 8),
            Text('Update Available (v${update.latestVersion})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A new version of Slim4K (v${update.latestVersion}) is available. Current version: v${update.currentVersion}.',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Text(
                update.releaseNotes,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          if (!update.isMandatory)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Remind Me Later', style: TextStyle(color: Colors.white54)),
            ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              AppUpdateService().launchUpdateDownload(update.downloadUrl);
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download Update', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkInitialFile() async {
    const defaultPath = '/Users/deepakdubey/Documents/4kVid.mp4';
    final file = File(defaultPath);
    if (await file.exists()) {
      final size = await file.length();
      final task = VideoTask(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        inputPath: defaultPath,
        fileName: '4kVid.mp4',
        inputFileSize: size,
        preset: _selectedPreset,
        targetBitrateKbps: _getBitrateForPreset(_selectedPreset),
        generateProxy: _generateProxies,
        preserveOriginalAudio: _preserveOriginalAudio,
      );
      if (mounted) {
        setState(() {
          _tasks.add(task);
        });
        _probeTask(task);
      }
    }
  }

  Future<void> _detectEncoder() async {
    final enc = await _engine.getAvailableHardwareEncoder();
    if (mounted) {
      setState(() {
        _activeEncoder = enc;
      });
    }
  }

  int _getBitrateForPreset(CompressionPreset preset) {
    switch (preset) {
      case CompressionPreset.slim10x:
        return 10000;
      case CompressionPreset.ultra15x:
        return 6500;
      case CompressionPreset.extreme20x:
        return 4500;
      case CompressionPreset.custom:
        return _customBitrateKbps;
    }
  }

  // Pick individual files
  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.video,
    );

    if (files.isNotEmpty) {
      for (final f in files) {
        if (f.path != null) {
          final file = File(f.path!);
          final size = await file.length();
          final task = VideoTask(
            id: DateTime.now().microsecondsSinceEpoch.toString() + f.path.hashCode.toString(),
            inputPath: f.path!,
            fileName: f.name,
            inputFileSize: size,
            preset: _selectedPreset,
            targetBitrateKbps: _getBitrateForPreset(_selectedPreset),
            generateProxy: _generateProxies,
            preserveOriginalAudio: _preserveOriginalAudio,
          );

          setState(() {
            _tasks.add(task);
          });

          _probeTask(task);
        }
      }
    }
  }

  // Pick entire project folder for mirroring
  Future<void> _pickProjectFolder() async {
    final selectedDir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Client Shoot / Project Folder to Archive',
    );

    if (selectedDir != null && selectedDir.isNotEmpty) {
      setState(() {
        _isFolderArchiveMode = true;
      });

      try {
        final result = await _engine.scanProjectFolder(selectedDir);
        setState(() {
          _projectScanResult = result;
          _tasks.clear();
          for (final t in result.videoTasks) {
            t.preset = _selectedPreset;
            t.targetBitrateKbps = _getBitrateForPreset(_selectedPreset);
            t.generateProxy = _generateProxies;
            t.preserveOriginalAudio = _preserveOriginalAudio;
            _tasks.add(t);
            _probeTask(t);
          }
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error scanning folder: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _probeTask(VideoTask task) async {
    setState(() => task.status = TaskStatus.analyzing);
    final meta = await _engine.probeVideo(task.inputPath);
    if (mounted) {
      setState(() {
        task.durationMs = meta['durationMs'] as int;
        task.width = meta['width'] as int;
        task.height = meta['height'] as int;
        task.fps = meta['fps'] as double;
        task.originalBitrateKbps = meta['bitrateKbps'] as int;
        task.status = TaskStatus.idle;
      });
    }
  }

  Future<void> _startCompression(VideoTask task) async {
    // Enforce 10 TB Annual Limit
    if (_quotaService.isQuotaExceeded) {
      _showQuotaExceededDialog();
      return;
    }

    setState(() {
      task.status = TaskStatus.compressing;
      task.progress = 0.0;
      task.errorMessage = null;
      task.generateProxy = _generateProxies;
      task.preserveOriginalAudio = _preserveOriginalAudio;
    });

    try {
      // Determine target output path
      String? customTarget = task.customOutputPath;
      if (customTarget == null && _projectScanResult != null && task.relativeSubPath != null) {
        if (!_saveFilesInPlace) {
          final ext = p.extension(task.inputPath);
          final baseWithoutExt = p.withoutExtension(task.relativeSubPath!);
          customTarget = p.join(_projectScanResult!.targetDir, '${baseWithoutExt}_slim$ext');
        }
      }

      final outPath = await _engine.compressVideo(
        task: task,
        customOutputPath: customTarget,
        onLiveProgressCheck: (progress) {
          if (_quotaService.isTrialMode) {
            final currentProcessed = (task.inputFileSize * progress).round();
            if (_quotaService.isHardLimitExceeded(additionalBytes: currentProcessed)) {
              return false; // Stop slimming immediately if it surpasses 2.5 GB trial ceiling!
            }
          }
          return true;
        },
        onProgress: (progress, fps, speed, eta) {
          if (mounted) {
            setState(() {
              task.progress = progress;
              task.currentFps = fps;
              task.speedMultiplier = speed;
              task.estimatedTimeRemaining = eta;
            });
          }
        },
      );

      final outFile = File(outPath);
      final outSize = await outFile.length();

      // Feature 5: Generate 1080p proxy if requested
      if (_generateProxies) {
        try {
          String? proxyTarget;
          if (_projectScanResult != null && task.relativeSubPath != null) {
            final baseWithoutExt = p.withoutExtension(task.relativeSubPath!);
            proxyTarget = p.join(_projectScanResult!.targetDir, '${baseWithoutExt}_proxy.mp4');
          }
          final pPath = await _engine.generateProxyVideo(task: task, customProxyPath: proxyTarget);
          task.proxyPath = pPath;
          task.proxyFileSize = await File(pPath).length();
        } catch (e) {
          debugPrint('Proxy generation warning: $e');
        }
      }

      // Feature 4: Safety Verification Check
      final isValid = await _engine.verifyVideo(outPath);

      if (mounted) {
        setState(() {
          task.status = TaskStatus.completed;
          task.progress = 1.0;
          task.outputPath = outPath;
          task.outputFileSize = outSize;
          task.isVerified = isValid;
        });
      }

      // Track slimmed data in Keychain & Firestore!
      final clientId = _activation?.clientId ?? await KeychainService().getClientId() ?? '';
      await _quotaService.recordSlimmedVideo(
        inputBytes: task.inputFileSize,
        outputBytes: outSize,
        clientId: clientId,
      );
    } on QuotaHardLimitExceededException catch (_) {
      if (mounted) {
        setState(() {
          task.status = TaskStatus.idle;
          task.progress = 0.0;
          task.errorMessage = 'Trial limit of 2.5 GB reached during processing. Upgrade to continue.';
        });

        // Prompt payment dialog
        await _showQuotaExceededDialog();

        // If license was activated, automatically continue / restart slimming!
        if (_quotaService.isLicenseActivated && mounted) {
          _startCompression(task);
        }
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          task.status = TaskStatus.error;
          task.errorMessage = e.toString();
        });
      }
    }
  }

  Future<bool?> _showQuotaExceededDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => UpiPaymentDialog(
        isTrialExpired: _quotaService.isTrialMode,
      ),
    );
  }

  Future<void> _startAllPending() async {
    if (_quotaService.isQuotaExceeded) {
      _showQuotaExceededDialog();
      return;
    }
    setState(() => _isProcessingBatch = true);

    // If mirroring into a separate folder, copy non-video files to destination tree first
    if (!_saveFilesInPlace && _projectScanResult != null && _projectScanResult!.nonVideoFiles.isNotEmpty) {
      for (final nonVid in _projectScanResult!.nonVideoFiles) {
        await _engine.copyNonVideoFile(
          sourceFile: nonVid,
          sourceRoot: _projectScanResult!.sourceDir,
          targetRoot: _projectScanResult!.targetDir,
        );
      }
    }

    for (final task in _tasks) {
      if (task.status == TaskStatus.idle || task.status == TaskStatus.error) {
        await _startCompression(task);
      }
    }

    if (mounted) {
      setState(() => _isProcessingBatch = false);
    }
  }

  // Feature 4: Safe Trash with confirmation dialog
  Future<void> _confirmAndTrash(VideoTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.security, color: Color(0xFF00E676)),
            SizedBox(width: 8),
            Text('Safety Check: Move to Trash', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Original File:\n${task.fileName} (${task.formattedInputSize})',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00E676).withOpacity(0.3)),
              ),
              child: const Text(
                '✅ The 4K compressed archive has been verified 100% intact.\n\nThis will safely move the raw original to your system Trash bin (NOT permanently deleted). You can recover it anytime.',
                style: TextStyle(color: Color(0xFF00E676), fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Move to Trash'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final trashed = await _engine.moveToTrash(task.inputPath);
      if (mounted) {
        setState(() {
          task.isOriginalTrashed = trashed;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trashed
                ? 'Original file moved to Trash safely.'
                : 'Could not move file to Trash automatically.'),
            backgroundColor: trashed ? const Color(0xFF00E676) : Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _saveAsFile(VideoTask task) async {
    final sourcePath = task.outputPath;
    if (sourcePath == null || !File(sourcePath).existsSync()) return;

    final baseName = p.basenameWithoutExtension(task.inputPath);
    final ext = p.extension(sourcePath).isNotEmpty ? p.extension(sourcePath) : '.mp4';
    final suggestedName = '${baseName}_slim$ext';

    final targetDir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Folder to Save $suggestedName',
    );

    if (targetDir != null && mounted) {
      final destinationPath = p.join(targetDir, suggestedName);
      if (destinationPath != sourcePath) {
        await File(sourcePath).copy(destinationPath);
        setState(() {
          task.outputPath = destinationPath;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to: $destinationPath'),
            backgroundColor: const Color(0xFF00E676),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _chooseCustomOutputDestination(VideoTask task) async {
    final baseName = p.basenameWithoutExtension(task.inputPath);
    final selectedDir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Output Folder for ${baseName}_slim.mp4',
    );

    if (selectedDir != null && mounted) {
      setState(() {
        task.customOutputPath = p.join(selectedDir, '${baseName}_slim.mp4');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Destination: ${task.customOutputPath}'),
          backgroundColor: const Color(0xFF00E676),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _revealInFolder(String filePath) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [p.dirname(filePath)]);
      }
    } catch (e) {
      debugPrint('Error revealing in folder: $e');
    }
  }

  String _getDestinationDisplay(VideoTask task) {
    if (task.customOutputPath != null) {
      return task.customOutputPath!;
    }
    if (_projectScanResult != null && !_saveFilesInPlace && task.relativeSubPath != null) {
      final ext = p.extension(task.inputPath);
      final baseWithoutExt = p.withoutExtension(task.relativeSubPath!);
      return p.join(_projectScanResult!.targetDir, '${baseWithoutExt}_slim$ext');
    }
    final baseName = p.basenameWithoutExtension(task.inputPath);
    final inputDir = p.dirname(task.inputPath);
    return p.join(inputDir, '${baseName}_slim.mp4');
  }

  // Feature 3: ROI Calculations
  int get _totalRawBytesProcessed => _tasks
      .where((t) => t.status == TaskStatus.completed)
      .fold(0, (sum, t) => sum + t.inputFileSize);

  int get _totalCompressedBytes => _tasks
      .where((t) => t.status == TaskStatus.completed)
      .fold(0, (sum, t) => sum + (t.outputFileSize ?? 0));

  int get _totalBytesSaved => _totalRawBytesProcessed > _totalCompressedBytes
      ? _totalRawBytesProcessed - _totalCompressedBytes
      : 0;

  double get _totalGbSaved => _totalBytesSaved / (1024 * 1024 * 1024);

  double get _estimatedCashSavedInr => (_totalGbSaved / 1024) * _hddCostPerTbInr;

  double get _hardDrivesSaved => _totalGbSaved / 2048.0; // Based on 2TB drives

  void _showLicenseDialog() {
    if (_activation == null) return;
    final act = _activation!;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.verified_user_rounded, color: Color(0xFF00E676)),
            SizedBox(width: 8),
            Text('App License & Activation', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogInfoRow('Product', 'Slim4K Studio Edition'),
            const Divider(color: Color(0xFF21262D)),
            _dialogInfoRow('Edition', act.isActive ? 'Pro Studio (Licensed)' : 'Free Trial'),
            const Divider(color: Color(0xFF21262D)),
            _dialogInfoRow('Platform', act.platform.toUpperCase()),
            const Divider(color: Color(0xFF21262D)),
            _dialogInfoRow('Status', act.isActive ? 'Active ✅' : 'Inactive ❌'),
            const Divider(color: Color(0xFF21262D)),
            _dialogInfoRow('Last Verified', dateFormat.format(act.lastHeartbeat.toLocal())),
            const Divider(color: Color(0xFF21262D)),
            _dialogInfoRow('Offline Status', '${act.daysSinceLastHeartbeat} / 15 days grace'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _checkActivation();
            },
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Sync Heartbeat'),
          ),
        ],
      ),
    );
  }

  Widget _dialogInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _licenseStatusBadge(ClientActivation act) {
    final bool isOfflineGrace = act.status == ActivationStatus.offlineGrace;
    final color = isOfflineGrace ? Colors.amber : const Color(0xFF00E676);

    return InkWell(
      onTap: _showLicenseDialog,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOfflineGrace ? Icons.warning_amber_rounded : Icons.shield_rounded,
              color: color,
              size: 13,
            ),
            const SizedBox(width: 4),
            Text(
              isOfflineGrace ? 'Offline (${act.daysRemainingBeforeExpiry}d)' : 'Active',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quotaStatusBadge() {
    final isTrial = _quotaService.isTrialMode;
    final isExceeded = _quotaService.isQuotaExceeded;
    final isNearLimit = _quotaService.usedPercentage > 85;
    final color = isExceeded
        ? Colors.redAccent
        : (isTrial ? const Color(0xFFFFB300) : (isNearLimit ? Colors.amberAccent : const Color(0xFF00E5FF)));

    return Tooltip(
      message: isTrial
          ? 'Free Trial: ${_quotaService.formattedUsage} (Click to Scan UPI QR & Activate 10 TB)'
          : '10 TB Annual License: ${_quotaService.formattedUsage} (${_quotaService.formattedRemaining})',
      child: InkWell(
        onTap: () {
          _showQuotaExceededDialog();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.5), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isExceeded
                    ? Icons.lock_clock
                    : (isTrial ? Icons.star_border_rounded : Icons.pie_chart_outline),
                size: 13,
                color: color,
              ),
              const SizedBox(width: 5),
              Text(
                isTrial
                    ? '${_quotaService.trialUsedGb.toStringAsFixed(2)} / 2.0 GB (Trial)'
                    : '${_quotaService.totalTbSlimmed.toStringAsFixed(2)} / ${_quotaService.quotaLimitTb.toStringAsFixed(0)} TB',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
              if (isTrial) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'BUY 10 TB',
                    style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _googleAuthButtonOrProfile() {
    final user = _authService.currentUser;
    if (user == null || !user.isValid) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            backgroundColor: const Color(0xFF161B22),
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          ),
          onPressed: _showGoogleSignInModal,
          icon: Image.network(
            'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png',
            width: 14,
            height: 14,
            errorBuilder: (_, __, ___) => const Icon(Icons.account_circle_outlined, size: 14, color: Color(0xFF00E5FF)),
          ),
          label: const Text(
            'Sign in with Google',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Signed in as ${user.email}\nClick to view cross-device sync & account',
      child: InkWell(
        onTap: () => _showAccountProfileModal(user),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 9,
                backgroundColor: const Color(0xFF00E5FF),
                backgroundImage: user.photoUrl != null && user.photoUrl!.isNotEmpty ? NetworkImage(user.photoUrl!) : null,
                child: user.photoUrl == null || user.photoUrl!.isEmpty
                    ? Text(
                        user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'G',
                        style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  user.displayName.isNotEmpty ? user.displayName : user.email,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGoogleSignInModal() {
    final emailCtrl = TextEditingController();
    final licCtrl = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: Color(0xFF00E5FF), size: 22),
              SizedBox(width: 8),
              Text(
                'Connect Google Account',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connecting your Google account links your quota and 10 TB license across all your PCs (office workstation, field laptop, or new PC).',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 18),

                // Browser OAuth Button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            setModalState(() => isSubmitting = true);
                            final clientId = _activation?.clientId ?? await KeychainService().getClientId() ?? '';
                            try {
                              final profile = await _authService.signInWithGoogle(hardwareClientId: clientId);
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (profile != null && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Signed in as ${profile.email}. Quota synced across PCs!'),
                                    backgroundColor: const Color(0xFF00E676),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                setModalState(() => isSubmitting = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Sign-in cancelled or failed: $e'), backgroundColor: Colors.redAccent),
                                );
                              }
                            }
                          },
                    icon: Image.network(
                      'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png',
                      width: 18,
                      height: 18,
                      errorBuilder: (_, __, ___) => const Icon(Icons.login, size: 18, color: Colors.black87),
                    ),
                    label: Text(
                      isSubmitting ? 'Waiting for browser sign-in...' : 'Sign in with Google in Browser',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider(color: Color(0xFF30363D))),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('OR LINK BY EMAIL', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(child: Divider(color: Color(0xFF30363D))),
                  ],
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: emailCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'name@gmail.com',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF0D1117),
                    prefixIcon: const Icon(Icons.email_outlined, color: Colors.white54, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF30363D))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF30363D))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF00E5FF))),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final email = emailCtrl.text.trim();
                            if (!email.contains('@')) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enter a valid Google email address'), backgroundColor: Colors.orange),
                              );
                              return;
                            }
                            setModalState(() => isSubmitting = true);
                            final clientId = _activation?.clientId ?? await KeychainService().getClientId() ?? '';
                            final profile = await _authService.signInWithGoogle(
                              hardwareClientId: clientId,
                              preferredEmail: email,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (profile != null && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Connected to ${profile.email}! Quota linked.'),
                                  backgroundColor: const Color(0xFF00E676),
                                ),
                              );
                            }
                          },
                    child: const Text('Link Google Email & Restore License', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),

                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider(color: Color(0xFF30363D))),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('OR REDEEM LICENSE KEY', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(child: Divider(color: Color(0xFF30363D))),
                  ],
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: licCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 1.0, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'LIC-XXXXXXXXXXXX',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF0D1117),
                    prefixIcon: const Icon(Icons.vpn_key_outlined, color: Colors.white54, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF30363D))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF30363D))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF00E676))),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E676),
                      side: const BorderSide(color: Color(0xFF00E676)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final rawKey = licCtrl.text.trim();
                            if (rawKey.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enter your license key from invoice/receipt'), backgroundColor: Colors.orange),
                              );
                              return;
                            }
                            setModalState(() => isSubmitting = true);
                            final clientId = _activation?.clientId ?? await KeychainService().getClientId() ?? '';
                            final success = await _quotaService.redeemLicenseKey(
                              licenseKey: rawKey,
                              clientId: clientId,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              if (success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('License $rawKey redeemed! 10 TB unlocked.'),
                                    backgroundColor: const Color(0xFF00E676),
                                  ),
                                );
                                _checkActivation();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Invalid or inactive license key. Please check your invoice.'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            }
                          },
                    child: const Text('Redeem License Key (10 TB)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountProfileModal(UserProfile user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.account_circle, color: Color(0xFF00E5FF), size: 22),
            SizedBox(width: 8),
            Text('Account & Multi-Device Sync', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF00E5FF),
                      backgroundImage: user.photoUrl != null && user.photoUrl!.isNotEmpty ? NetworkImage(user.photoUrl!) : null,
                      child: user.photoUrl == null || user.photoUrl!.isEmpty
                          ? Text(user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : 'G', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(user.email, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _dialogInfoRow('Account Plan', _quotaService.isLicenseActivated ? 'Pro Studio 10 TB (Active ✅)' : 'Free Trial (2.0 GB)'),
              const Divider(color: Color(0xFF21262D)),
              _dialogInfoRow('Active Seats', '${_quotaService.activeSeats.length} / ${_quotaService.maxSeats} Workstations (Cap: 2 PCs)'),
              const Divider(color: Color(0xFF21262D)),
              _dialogInfoRow('Total Slimmed', _quotaService.isTrialMode ? '${_quotaService.trialUsedGb.toStringAsFixed(2)} GB / 2.0 GB' : '${_quotaService.totalTbSlimmed.toStringAsFixed(2)} TB / ${_quotaService.quotaLimitTb.toStringAsFixed(0)} TB'),
              const Divider(color: Color(0xFF21262D)),
              _dialogInfoRow('Total Saved', '${_quotaService.totalTbSaved.toStringAsFixed(2)} TB'),
              const Divider(color: Color(0xFF21262D)),
              _dialogInfoRow('Files Slimmed', '${_quotaService.totalFilesSlimmed} videos'),
              const Divider(color: Color(0xFF21262D)),
              _dialogInfoRow('Cross-PC Sync', 'Active (All PCs linked to this Google account share this quota)'),
              if (_quotaService.isSeatLimitReached) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '2/2 PCs already active. You can transfer a seat to this computer.',
                          style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showSeatLimitModal(user);
                        },
                        child: const Text('Transfer Seat', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
              if (_quotaService.isLicenseActivated || _quotaService.accountInvoiceId != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final invoiceId = _quotaService.accountInvoiceId ?? _quotaService.licenseKey ?? _activation?.clientId ?? '';
                      final receiptUrl = invoiceId.isNotEmpty
                          ? 'https://us-central1-neertech-technologies.cloudfunctions.net/viewInvoice?id=$invoiceId'
                          : 'https://neertechtechnologies.in';
                      AppUpdateService().launchUpdateDownload(receiptUrl);
                    },
                    icon: const Icon(Icons.receipt_long, size: 16),
                    label: const Text('View Official Payment Receipt & Invoice', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (_quotaService.isSeatLimitReached)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showSeatLimitModal(user);
              },
              child: const Text('Manage Seats', style: TextStyle(color: Colors.amber)),
            ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final clientId = _activation?.clientId ?? await KeychainService().getClientId() ?? '';
              await _quotaService.syncWithGoogleAccount(user: user, clientId: clientId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Account quota synced with cloud!'), backgroundColor: Color(0xFF00E676)),
                );
              }
            },
            child: const Text('Sync Now', style: TextStyle(color: Color(0xFF00E5FF))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _authService.signOut();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Signed out of Google account.')),
                );
              }
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _showSeatLimitModal(UserProfile user) {
    final activeDevices = _quotaService.activeSeats;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.devices, color: Colors.amber, size: 22),
            SizedBox(width: 8),
            Text('Device Seat Limit (2 of 2 PCs Active)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your Slim4K 10 TB Studio license is currently active on 2 other workstations. To activate this computer, select an existing PC to replace:',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              if (activeDevices.isEmpty)
                const Text('No registered devices found.', style: TextStyle(color: Colors.white54, fontSize: 12))
              else
                ...activeDevices.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final dev = entry.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.computer, color: Color(0xFF00E5FF), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Workstation $idx', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                              Text(dev.length > 16 ? '${dev.substring(0, 16)}...' : dev, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                            foregroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                              side: const BorderSide(color: Colors.redAccent),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final currentClientId = _activation?.clientId ?? await KeychainService().getClientId() ?? '';
                            final success = await _authService.transferDeviceSeat(
                              user: user,
                              oldHardwareClientId: dev,
                              newHardwareClientId: currentClientId,
                            );
                            if (success) {
                              await _quotaService.syncWithGoogleAccount(user: user, clientId: currentClientId);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Seat transferred successfully! License is now active on this PC.'),
                                    backgroundColor: Color(0xFF00E676),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Replace & Activate Here', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep as Free Trial', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineGraceBanner() {
    if (_activation == null || _activation!.status != ActivationStatus.offlineGrace) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline Notice: App disconnected for ${_activation!.daysSinceLastHeartbeat} days. Please connect to internet within ${_activation!.daysRemainingBeforeExpiry} days to maintain activation.',
              style: const TextStyle(color: Colors.amber, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _checkActivation,
            child: const Text('Sync Now', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isActivationChecking) {
      return const Scaffold(
        backgroundColor: Color(0xFF090D13),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF00E5FF)),
              SizedBox(height: 16),
              Text(
                'Connecting to License Server & Verifying License...',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_activation != null &&
        (!_activation!.isActive ||
            _activation!.status == ActivationStatus.deactivatedAdmin ||
            _activation!.status == ActivationStatus.deactivatedExpired)) {
      return ActivationLockWidget(
        activation: _activation!,
        onReactivated: _checkActivation,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF090D13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/icon/app_icon_1024.png',
                width: 24,
                height: 24,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'SLIM 4K',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Cameraman Archive & Storage Saver',
                style: TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Google Sign-In / User Profile
          _googleAuthButtonOrProfile(),
          // License pill
          if (_activation != null)
            _licenseStatusBadge(_activation!),
          // 10 TB Annual Quota pill
          _quotaStatusBadge(),
          // Mode switch pill
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _modeButton(
                  title: 'Files',
                  icon: Icons.movie_outlined,
                  isSelected: !_isFolderArchiveMode,
                  onTap: () => setState(() => _isFolderArchiveMode = false),
                ),
                _modeButton(
                  title: 'Project Folder',
                  icon: Icons.folder_special_outlined,
                  isSelected: _isFolderArchiveMode,
                  onTap: () => setState(() => _isFolderArchiveMode = true),
                ),
              ],
            ),
          ),
          // Encoder badge
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _activeEncoder.contains('videotoolbox') ||
                        _activeEncoder.contains('mediacodec') ||
                        _activeEncoder.contains('nvenc')
                    ? const Color(0xFF00E676)
                    : Colors.amber,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bolt,
                  color: _activeEncoder.contains('videotoolbox') ||
                          _activeEncoder.contains('mediacodec') ||
                          _activeEncoder.contains('nvenc')
                      ? const Color(0xFF00E676)
                      : Colors.amber,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  _activeEncoder,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 750;

          if (isDesktop) {
            return Row(
              children: [
                Container(
                  width: 310,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0D1117),
                    border: Border(right: BorderSide(color: Color(0xFF21262D))),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: _buildPresetPanel(),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildMainContent(),
                  ),
                ),
              ],
            );
          } else {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildOfflineGraceBanner(),
                  _buildMobilePresetSection(),
                  const SizedBox(height: 14),
                  _buildRoiDashboardCard(),
                  const SizedBox(height: 14),
                  _buildHeroPickCard(),
                  const SizedBox(height: 18),
                  _buildQueueHeader(),
                  const SizedBox(height: 10),
                  _buildMobileTaskList(),
                  const SizedBox(height: 16),
                  if (_tasks.isNotEmpty)
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isProcessingBatch ? null : _startAllPending,
                        icon: _isProcessingBatch
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(Icons.flash_on),
                        label: Text(
                          _isProcessingBatch ? 'Compressing Batch...' : 'Archive All (${_tasks.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _modeButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: const Color(0xFF00E5FF), width: 1) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? const Color(0xFF00E5FF) : Colors.white60),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'COMPRESSION PRESET',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        _presetTile(
          title: '10x Slim (Recommended)',
          subtitle: '10 Mbps 4K • Visually Lossless',
          preset: CompressionPreset.slim10x,
          badge: '90% SAVED',
          badgeColor: const Color(0xFF00E676),
        ),
        _presetTile(
          title: '15x Ultra Slim',
          subtitle: '6.5 Mbps 4K • Compact Master',
          preset: CompressionPreset.ultra15x,
          badge: '93% SAVED',
          badgeColor: const Color(0xFF00E5FF),
        ),
        _presetTile(
          title: '20x Extreme Slim',
          subtitle: '4.5 Mbps 4K • Web & Stream',
          preset: CompressionPreset.extreme20x,
          badge: '95% SAVED',
          badgeColor: const Color(0xFF7C4DFF),
        ),
        _presetTile(
          title: 'Custom Bitrate',
          subtitle: '${(_customBitrateKbps / 1000).toStringAsFixed(1)} Mbps Target',
          preset: CompressionPreset.custom,
          badge: 'MANUAL',
          badgeColor: Colors.orange,
        ),
        if (_selectedPreset == CompressionPreset.custom) ...[
          const SizedBox(height: 8),
          Slider(
            value: _customBitrateKbps.toDouble(),
            min: 2000,
            max: 30000,
            divisions: 28,
            activeColor: const Color(0xFF00E5FF),
            onChanged: (val) {
              setState(() {
                _customBitrateKbps = val.round();
              });
            },
          ),
        ],
        const SizedBox(height: 18),
        const Divider(color: Color(0xFF21262D)),
        const SizedBox(height: 12),

        // VIDEOGRAPHER / STUDIO WORKFLOW CONTROLS
        const Text(
          'CAMERAMAN STUDIO FEATURES',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        _featureSwitch(
          title: 'Preserve SMPTE Timecodes',
          subtitle: 'Preserves camera time for Premiere/Resolve',
          value: _preserveTimecodes,
          onChanged: (val) => setState(() => _preserveTimecodes = val),
        ),
        _featureSwitch(
          title: 'Studio Audio Passthrough',
          subtitle: 'Retains multi-channel camera audio tracks',
          value: _preserveOriginalAudio,
          onChanged: (val) => setState(() => _preserveOriginalAudio = val),
        ),
        _featureSwitch(
          title: 'Generate 1080p Proxies',
          subtitle: '2-in-1: fast proxy for laptop editing',
          value: _generateProxies,
          onChanged: (val) => setState(() => _generateProxies = val),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _tasks.isEmpty || _isProcessingBatch ? null : _startAllPending,
            icon: _isProcessingBatch
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.flash_on),
            label: Text(
              _isProcessingBatch ? 'Archiving Batch...' : 'Archive All (${_tasks.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _featureSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: const Color(0xFF00E5FF),
            activeTrackColor: const Color(0xFF00E5FF).withOpacity(0.3),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildMobilePresetSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF21262D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TARGET PRESET',
                style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Text(
                '${(_getBitrateForPreset(_selectedPreset) / 1000).toStringAsFixed(1)} Mbps',
                style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _mobilePresetChip('10x Slim', CompressionPreset.slim10x),
                const SizedBox(width: 6),
                _mobilePresetChip('15x Ultra', CompressionPreset.ultra15x),
                const SizedBox(width: 6),
                _mobilePresetChip('20x Extreme', CompressionPreset.extreme20x),
                const SizedBox(width: 6),
                _mobilePresetChip('Custom', CompressionPreset.custom),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('1080p Proxies', style: TextStyle(fontSize: 11)),
                selected: _generateProxies,
                onSelected: (val) => setState(() => _generateProxies = val),
                selectedColor: const Color(0xFF00E5FF).withOpacity(0.25),
                checkmarkColor: const Color(0xFF00E5FF),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Preserve Audio', style: TextStyle(fontSize: 11)),
                selected: _preserveOriginalAudio,
                onSelected: (val) => setState(() => _preserveOriginalAudio = val),
                selectedColor: const Color(0xFF00E676).withOpacity(0.25),
                checkmarkColor: const Color(0xFF00E676),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mobilePresetChip(String label, CompressionPreset preset) {
    final isSelected = _selectedPreset == preset;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedPreset = preset;
          for (final t in _tasks) {
            if (t.status == TaskStatus.idle) {
              t.preset = preset;
              t.targetBitrateKbps = _getBitrateForPreset(preset);
            }
          }
        });
      },
      selectedColor: const Color(0xFF00E5FF).withOpacity(0.2),
      backgroundColor: const Color(0xFF161B22),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF30363D),
      ),
    );
  }

  // Feature 3: ROI Dashboard Widget
  Widget _buildRoiDashboardCard() {
    final hasSavings = _totalBytesSaved > 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF161B22),
            const Color(0xFF0D1B2A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasSavings ? const Color(0xFF00E676).withOpacity(0.4) : const Color(0xFF21262D),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: const [
                    Icon(Icons.savings_outlined, color: Color(0xFF00E676), size: 18),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'HARD DISK STORAGE & ROI DASHBOARD',
                        style: TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '₹2,500/TB Est.',
                  style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _roiStatBlock(
                  label: 'Space Saved',
                  value: hasSavings ? '${_totalGbSaved.toStringAsFixed(1)} GB' : '0.0 GB',
                  highlightColor: const Color(0xFF00E676),
                  subText: hasSavings
                      ? '${((_totalBytesSaved / _totalRawBytesProcessed) * 100).toStringAsFixed(0)}% Reduction'
                      : 'Compress to see',
                ),
              ),
              Container(width: 1, height: 40, color: const Color(0xFF21262D)),
              Expanded(
                child: _roiStatBlock(
                  label: 'Money Saved on HDDs',
                  value: hasSavings ? '₹ ${_estimatedCashSavedInr.toStringAsFixed(0)}' : '₹ 0',
                  highlightColor: const Color(0xFF00E5FF),
                  subText: 'Direct cash retention',
                ),
              ),
              Container(width: 1, height: 40, color: const Color(0xFF21262D)),
              Expanded(
                child: _roiStatBlock(
                  label: 'Hard Drives Saved',
                  value: hasSavings ? '${_hardDrivesSaved.toStringAsFixed(1)} Drives' : '0.0 Drives',
                  highlightColor: const Color(0xFF7C4DFF),
                  subText: 'Based on 2TB drives',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 10 TB Annual Video Slimming Quota Tracker
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.28),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _quotaService.isQuotaExceeded
                    ? Colors.redAccent.withOpacity(0.4)
                    : const Color(0xFF00E5FF).withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.speed,
                          color: _quotaService.isQuotaExceeded ? Colors.redAccent : const Color(0xFF00E5FF),
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'ANNUAL SLIMMER QUOTA (10 TB LICENSE)',
                          style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${_quotaService.totalTbSlimmed.toStringAsFixed(2)} TB / ${_quotaService.quotaLimitTb.toStringAsFixed(1)} TB (${_quotaService.formattedPercentage})',
                      style: TextStyle(
                        color: _quotaService.isQuotaExceeded
                            ? Colors.redAccent
                            : (_quotaService.usedPercentage > 85 ? Colors.amberAccent : Colors.white),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_quotaService.usedPercentage / 100.0).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _quotaService.isQuotaExceeded
                          ? Colors.redAccent
                          : (_quotaService.usedPercentage > 85
                              ? Colors.amberAccent
                              : const Color(0xFF00E676)),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.shield_outlined, size: 11, color: Colors.white38),
                        SizedBox(width: 4),
                        Text(
                          'Hardware Keychain & Cloud Sync Active',
                          style: TextStyle(color: Colors.white38, fontSize: 9.5),
                        ),
                      ],
                    ),
                    Text(
                      _quotaService.formattedRemaining,
                      style: const TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roiStatBlock({
    required String label,
    required String value,
    required Color highlightColor,
    required String subText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(color: highlightColor, fontWeight: FontWeight.w900, fontSize: 15),
            overflow: TextOverflow.ellipsis,
          ),
          Text(subText, style: const TextStyle(color: Colors.white38, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOfflineGraceBanner(),
        _buildRoiDashboardCard(),
        const SizedBox(height: 16),
        _buildHeroPickCard(),
        const SizedBox(height: 16),
        _buildQueueHeader(),
        const SizedBox(height: 10),
        Expanded(
          child: _tasks.isEmpty
              ? _buildEmptyQueueNotice()
              : ListView.separated(
                  itemCount: _tasks.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _taskCard(_tasks[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildMobileTaskList() {
    if (_tasks.isEmpty) return _buildEmptyQueueNotice();
    return Column(
      children: _tasks.map((task) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _taskCard(task),
      )).toList(),
    );
  }

  // Dual Hero Picker (Select Videos or Select Entire Folder)
  Widget _buildHeroPickCard() {
    if (_projectScanResult != null) {
      final totalVideos = _projectScanResult!.videoTasks.length;
      final completedVideos = _tasks.where((t) => t.status == TaskStatus.completed).length;
      final isDone = totalVideos > 0 && completedVideos == totalVideos;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF7C4DFF).withOpacity(0.6),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.folder_open_rounded, color: Color(0xFF7C4DFF), size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.basename(_projectScanResult!.sourceDir),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C4DFF).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('FOLDER MODE', style: TextStyle(color: Color(0xFF7C4DFF), fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$totalVideos 4K videos found (${VideoTask.formatBytes(_projectScanResult!.totalSourceBytes)}) • ${_projectScanResult!.nonVideoFiles.length} other files',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Change Folder',
                  icon: const Icon(Icons.drive_file_move_rounded, color: Colors.white54, size: 20),
                  onPressed: _isProcessingBatch ? null : _pickProjectFolder,
                ),
                IconButton(
                  tooltip: 'Close Folder',
                  icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                  onPressed: _isProcessingBatch ? null : () => setState(() {
                    _projectScanResult = null;
                    _tasks.clear();
                  }),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDone ? const Color(0xFF00E676) : const Color(0xFF7C4DFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 4,
                    ),
                    onPressed: _isProcessingBatch
                        ? null
                        : isDone
                            ? null
                            : _startAllPending,
                    icon: Icon(
                      _isProcessingBatch
                          ? Icons.hourglass_top_rounded
                          : isDone
                              ? Icons.check_circle_rounded
                              : Icons.bolt_rounded,
                      size: 20,
                    ),
                    label: Text(
                      _isProcessingBatch
                          ? 'Slimming Folder Files... ($completedVideos/$totalVideos)'
                          : isDone
                              ? 'All $totalVideos Files Slimmed Successfully ✅'
                              : 'Slim All $totalVideos Files in Folder',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _saveFilesInPlace ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  color: const Color(0xFF7C4DFF),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _saveFilesInPlace
                        ? 'Saving each video as <filename>_slim.mp4 inside the folder (Originals intact)'
                        : 'Mirroring entire tree into: ${p.basename(_projectScanResult!.targetDir)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _saveFilesInPlace = !_saveFilesInPlace),
                  child: Text(
                    _saveFilesInPlace ? 'Switch to Mirror Folder' : 'Switch to In-Place',
                    style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Default: Dual Hero Cards (Select Videos vs Select Folder)
    return Row(
      children: [
        // Card 1: Select Individual Videos
        Expanded(
          child: InkWell(
            onTap: _pickFiles,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 120,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withOpacity(0.35),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_library_rounded,
                    size: 30,
                    color: const Color(0xFF00E5FF).withOpacity(0.9),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select Video(s)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Pick individual 4K camera files',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Card 2: Select Entire Folder (Slim All Files Inside)
        Expanded(
          child: InkWell(
            onTap: _pickProjectFolder,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 120,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF7C4DFF).withOpacity(0.55),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 30,
                    color: const Color(0xFF7C4DFF).withOpacity(0.95),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select Folder',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Slim all files inside a folder at once',
                    style: TextStyle(color: Color(0xFFB388FF), fontSize: 11, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQueueHeader() {
    final pendingTasks = _tasks.where((t) => t.status == TaskStatus.idle || t.status == TaskStatus.error).length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'QUEUE (${_tasks.length} Videos)',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        if (_tasks.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pendingTasks > 0)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _isProcessingBatch ? null : _startAllPending,
                  icon: const Icon(Icons.bolt, size: 14),
                  label: Text(
                    _isProcessingBatch ? 'Processing...' : 'Slim All ($pendingTasks)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() {
                  _tasks.clear();
                  _projectScanResult = null;
                }),
                child: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildEmptyQueueNotice() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.video_camera_back_outlined, size: 36, color: Colors.white24),
            SizedBox(height: 8),
            Text(
              'No 4K videos queued yet. Pick a video file or project folder.',
              style: TextStyle(color: Colors.white38, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetTile({
    required String title,
    required String subtitle,
    required CompressionPreset preset,
    required String badge,
    required Color badgeColor,
  }) {
    final isSelected = _selectedPreset == preset;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPreset = preset;
          for (final t in _tasks) {
            if (t.status == TaskStatus.idle) {
              t.preset = preset;
              t.targetBitrateKbps = _getBitrateForPreset(preset);
            }
          }
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1F242C) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF21262D),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge,
                style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Task card with Verification, Proxies, and Safe Trash
  Widget _taskCard(VideoTask task) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF21262D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${task.width}×${task.height}',
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.fileName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (task.relativeSubPath != null)
                      Text(
                        task.relativeSubPath!,
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${task.formattedInputSize} ➔ ${task.status == TaskStatus.completed ? task.formattedOutputSize : task.formattedEstimatedSize}',
                style: TextStyle(
                  color: task.status == TaskStatus.completed ? const Color(0xFF00E676) : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              if (task.status == TaskStatus.idle)
                IconButton(
                  icon: const Icon(Icons.play_arrow, color: Color(0xFF00E5FF), size: 20),
                  onPressed: () => _startCompression(task),
                )
              else if (task.status == TaskStatus.compressing)
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 20),
                  onPressed: () => _engine.cancel(),
                )
              else if (task.status == TaskStatus.completed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676).withOpacity(0.18),
                        foregroundColor: const Color(0xFF00E676),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      onPressed: () => _saveAsFile(task),
                      icon: const Icon(Icons.save_alt, size: 13),
                      label: const Text('Save As...', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Show in Finder / Folder',
                      icon: const Icon(Icons.folder_open, color: Color(0xFF00E5FF), size: 18),
                      onPressed: () {
                        if (task.outputPath != null) {
                          _revealInFolder(task.outputPath!);
                        }
                      },
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF).withOpacity(0.15),
                        foregroundColor: const Color(0xFF00E5FF),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => ComparisonPlayer(task: task),
                        );
                      },
                      icon: const Icon(Icons.compare, size: 13),
                      label: const Text('Compare', style: TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 4),
                    // Feature 4: Safe Trash Button
                    if (!task.isOriginalTrashed)
                      IconButton(
                        tooltip: 'Safely move original to Trash',
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                        onPressed: () => _confirmAndTrash(task),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('In Trash ♻️', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      ),
                  ],
                ),
            ],
          ),
          if (task.status == TaskStatus.idle) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.drive_file_move_outline, size: 13, color: Color(0xFF00E5FF)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Save to: ${_getDestinationDisplay(task)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _chooseCustomOutputDestination(task),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 10, color: Color(0xFF00E5FF)),
                        SizedBox(width: 3),
                        Text('Change...', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (task.status == TaskStatus.compressing) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress > 0 ? task.progress : null,
                backgroundColor: const Color(0xFF21262D),
                color: const Color(0xFF00E5FF),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${(task.progress * 100).toStringAsFixed(1)}% • ${task.speedMultiplier.toStringAsFixed(2)}x (${task.currentFps.toStringAsFixed(0)} FPS)',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (task.estimatedTimeRemaining != null)
                  Text(
                    'ETA: ${task.estimatedTimeRemaining!.inMinutes}m ${task.estimatedTimeRemaining!.inSeconds % 60}s',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
              ],
            ),
          ] else if (task.status == TaskStatus.completed) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E676).withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF00E676).withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF00E676), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Saved: ${task.spaceSavedPercentage.toStringAsFixed(1)}% (${task.reductionFactor.toStringAsFixed(1)}x space saving)',
                        style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      // Feature 4: Verified badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          task.isVerified ? 'VERIFIED INTACT ✅' : 'VERIFYING...',
                          style: const TextStyle(color: Color(0xFF00E676), fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.save_alt, color: Color(0xFF00E676), size: 12),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'File: ${task.outputPath ?? _getDestinationDisplay(task)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (task.proxyPath != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.bolt, color: Color(0xFF00E5FF), size: 13),
                        const SizedBox(width: 4),
                        Text(
                          '1080p Proxy Generated (${task.formattedProxySize}) for editing',
                          style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ] else if (task.status == TaskStatus.error) ...[
            const SizedBox(height: 6),
            Text(
              'Error: ${task.errorMessage}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
