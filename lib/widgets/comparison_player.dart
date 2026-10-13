import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/video_task.dart';

class ComparisonPlayer extends StatefulWidget {
  final VideoTask task;

  const ComparisonPlayer({super.key, required this.task});

  @override
  State<ComparisonPlayer> createState() => _ComparisonPlayerState();
}

class _ComparisonPlayerState extends State<ComparisonPlayer> {
  VideoPlayerController? _originalController;
  VideoPlayerController? _compressedController;
  bool _isPlaying = false;
  bool _showOriginal = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializePlayers();
  }

  Future<void> _initializePlayers() async {
    try {
      if (widget.task.outputPath != null && File(widget.task.outputPath!).existsSync()) {
        _compressedController = VideoPlayerController.file(File(widget.task.outputPath!));
        await _compressedController!.initialize();
        _compressedController!.setLooping(true);
      }

      if (File(widget.task.inputPath).existsSync()) {
        _originalController = VideoPlayerController.file(File(widget.task.inputPath));
        await _originalController!.initialize();
        _originalController!.setLooping(true);
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Video player init error: $e');
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_isPlaying) {
        _compressedController?.pause();
        _originalController?.pause();
        _isPlaying = false;
      } else {
        _compressedController?.play();
        _originalController?.play();
        _isPlaying = true;
      }
    });
  }

  @override
  void dispose() {
    _compressedController?.dispose();
    _originalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF30363D)),
      ),
      child: Container(
        width: 850,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF00E5FF)),
                        ),
                        child: const Text(
                          '4K UHD VERIFIED',
                          style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.task.fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Comparison Metrics Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF21262D)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metricColumn(
                      'ORIGINAL FILE',
                      widget.task.formattedInputSize,
                      '100 Mbps Source',
                      Colors.grey,
                    ),
                    Container(width: 1, height: 40, color: const Color(0xFF30363D)),
                    _metricColumn(
                      'COMPRESSED FILE',
                      widget.task.formattedOutputSize,
                      '${(widget.task.targetBitrateKbps / 1000).toStringAsFixed(1)} Mbps HEVC',
                      const Color(0xFF00E676),
                    ),
                    Container(width: 1, height: 40, color: const Color(0xFF30363D)),
                    _metricColumn(
                      'STORAGE SAVED',
                      '-${widget.task.spaceSavedPercentage.toStringAsFixed(1)}%',
                      '${widget.task.reductionFactor.toStringAsFixed(1)}x Slimmer',
                      const Color(0xFF00E5FF),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Video Area
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: Colors.black,
                      child: !_isInitialized
                      ? const Center(
                          child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            // Primary video (Compressed or Selected)
                            Center(
                              child: AspectRatio(
                                aspectRatio: _compressedController?.value.aspectRatio ?? (16 / 9),
                                child: VideoPlayer(
                                  _showOriginal
                                      ? (_originalController ?? _compressedController!)
                                      : (_compressedController ?? _originalController!),
                                ),
                              ),
                            ),
                            // Quality overlay label
                            Positioned(
                              top: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _showOriginal ? Colors.amber : const Color(0xFF00E676),
                                  ),
                                ),
                                child: Text(
                                  _showOriginal ? 'ORIGINAL 4K (100% UNCOMPRESSED)' : 'SLIM4K (1/10th SIZE HEVC)',
                                  style: TextStyle(
                                    color: _showOriginal ? Colors.amber : const Color(0xFF00E676),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _isInitialized ? _togglePlayPause : null,
                      icon: Icon(
                        _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: const Color(0xFF00E5FF),
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Hold to compare toggle
                    GestureDetector(
                      onTapDown: (_) => setState(() => _showOriginal = true),
                      onTapUp: (_) => setState(() => _showOriginal = false),
                      onTapCancel: () => setState(() => _showOriginal = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _showOriginal ? Colors.amber.withOpacity(0.2) : const Color(0xFF21262D),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _showOriginal ? Colors.amber : const Color(0xFF30363D),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.touch_app,
                              color: _showOriginal ? Colors.amber : Colors.white70,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'PRESS & HOLD: View Original',
                              style: TextStyle(
                                color: _showOriginal ? Colors.amber : Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check, color: Color(0xFF00E676)),
                  label: const Text(
                    'Done',
                    style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold),
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

  Widget _metricColumn(String title, String value, String subtitle, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }
}
