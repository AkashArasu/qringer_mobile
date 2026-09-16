import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/rendering.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:qringer_mobile_stream_io/utils/app_theme.dart';
import 'package:qringer_mobile_stream_io/utils/app_init.dart';

class MyQRCodeScreen extends StatefulWidget {
  const MyQRCodeScreen({super.key});

  @override
  State<MyQRCodeScreen> createState() => _MyQRCodeScreenState();
}

class _MyQRCodeScreenState extends State<MyQRCodeScreen> with SingleTickerProviderStateMixin {
  final GlobalKey _qrKey = GlobalKey();
  bool _isLoading = false;
  String _qrUrl = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // QR payloads are opaque property capabilities, never a phone number or
    // Stream user identifier.
    _loadPropertyQr();
    
    // Initialize animations for smoother UI
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    
    _animationController.forward();
  }

  Future<void> _loadPropertyQr() async {
    final propertyId = await AppInitializer.getPropertyId();
    if (!mounted) return;
    setState(() {
      _qrUrl = propertyId == null ? '' : 'https://qringer-web.pages.dev/p/$propertyId';
    });
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(26), // 0.1 opacity
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const Spacer(),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.green, Colors.lightGreen],
                      ).createShader(bounds),
                      child: const Text(
                        'My QR Code',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48), // Balance the back button
                  ],
                ),
              ),
              
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        
                        // QR Code Icon
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Colors.green.withAlpha(204), // 0.8 opacity
                                Colors.lightGreen.withAlpha(153), // 0.6 opacity
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withAlpha(77), // 0.3 opacity
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.qr_code_2,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                          
                        const SizedBox(height: 40),
                        
                        const Text(
                          'Your Property QR Code',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                          
                        const SizedBox(height: 8),
                        
                        Text(
                          'Post this code at your entrance to ring your home',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                          textAlign: TextAlign.center,
                        ),
                          
                        const SizedBox(height: 40),
                        
                        // QR Code
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(51), // 0.2 opacity
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: RepaintBoundary(
                            key: _qrKey,
                            child: QrImageView(
                              data: _qrUrl.isEmpty ? 'QROnly setup required' : _qrUrl,
                              version: QrVersions.auto,
                              size: 200.0,
                              backgroundColor: Colors.white,
                              // Using dataModuleStyle instead of deprecated foregroundColor
                              dataModuleStyle: const QrDataModuleStyle(
                                color: Colors.black,
                                dataModuleShape: QrDataModuleShape.square,
                              ),
                              errorStateBuilder: (context, error) {
                                return const Center(
                                  child: Text(
                                    'Something went wrong!',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                          
                        const SizedBox(height: 40),
                        
                        // Public destination display; no personal contact data.
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(26), // 0.1 opacity
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.cyan.withAlpha(77), // 0.3 opacity
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.phone,
                                color: Colors.cyan.withAlpha(179), // 0.7 opacity
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _qrUrl.isEmpty ? 'Setting up your property…' : 'Secure property QR',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                          
                        const SizedBox(height: 40),
                        
                        // Download button
                        _buildDownloadButton(),
                        
                        const SizedBox(height: 40)
                      ]
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Colors.cyan.withAlpha(204), // 0.8 opacity
            Colors.blue.withAlpha(204), // 0.8 opacity
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.cyan.withAlpha(77), // 0.3 opacity
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading ? null : _downloadQRCode,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.download,
                        color: Colors.white,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Download QR Code',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadQRCode() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Capture QR code as image
      RenderRepaintBoundary boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData != null) {
        Uint8List pngBytes = byteData.buffer.asUint8List();
        
        // Get temporary directory
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/my_qrcode.png';
        final file = File(filePath);
        await file.writeAsBytes(pngBytes);
        
        // Share the file
        await Share.shareXFiles([XFile(filePath)], text: 'QROnly property doorbell QR code');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
