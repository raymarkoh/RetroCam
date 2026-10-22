import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'photo_storage.dart';
import 'retro_filter.dart';

const _backgroundColor = Color(0xFF171717);
const _surfaceColor = Color(0xFF242424);
const _accentColor = Color(0xFFE6A85C);

void main() {
  runApp(const RetroCamApp());
}

class RetroCamApp extends StatelessWidget {
  const RetroCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _accentColor,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'RetroCam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: _backgroundColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: _backgroundColor,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        cardTheme: const CardThemeData(color: _surfaceColor, elevation: 0),
      ),
      home: const RetroCamHomePage(),
    );
  }
}

class RetroCamHomePage extends StatefulWidget {
  const RetroCamHomePage({super.key});

  @override
  State<RetroCamHomePage> createState() => _RetroCamHomePageState();
}

class _RetroCamHomePageState extends State<RetroCamHomePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  XFile? _capturedPhoto;
  RetroFilter _filter = RetroFilter.warm;
  FlashMode _flashMode = FlashMode.off;
  String? _cameraError;
  bool _isInitializing = true;
  bool _isCapturing = false;
  bool _showingPhoto = false;
  int _cameraGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraGeneration++;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive) {
      _cameraGeneration++;
      _controller = null;
      if (controller != null) unawaited(controller.dispose());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera({CameraDescription? camera}) async {
    final generation = ++_cameraGeneration;
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _cameraError = null;
      });
    }

    CameraController? controller;
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (!mounted || generation != _cameraGeneration) return;

      if (_cameras.isEmpty) {
        _setCameraError('No camera was found on this device.');
        return;
      }

      final selectedCamera = camera ?? _cameras.first;
      final previousController = _controller;
      _controller = null;
      if (previousController != null) await previousController.dispose();
      if (!mounted || generation != _cameraGeneration) return;

      controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      await controller.setFlashMode(_flashMode);

      if (!mounted || generation != _cameraGeneration) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _cameraError = null;
      });
    } on CameraException catch (error) {
      if (generation != _cameraGeneration || !mounted) {
        return;
      }
      _controller = null;
      if (controller != null) await controller.dispose();
      setState(() {
        _isInitializing = false;
        _cameraError = _cameraExceptionMessage(error);
      });
    } on Exception catch (error) {
      if (generation != _cameraGeneration || !mounted) {
        return;
      }
      _controller = null;
      if (controller != null) await controller.dispose();
      setState(() {
        _isInitializing = false;
        _cameraError = 'Could not start the camera: $error';
      });
    }
  }

  void _setCameraError(String message) {
    if (!mounted) return;
    setState(() {
      _isInitializing = false;
      _cameraError = message;
    });
  }

  String _cameraExceptionMessage(CameraException error) {
    return switch (error.code) {
      'CameraAccessDenied' =>
        'Camera access is denied. Allow camera access in Settings.',
      'CameraAccessDeniedWithoutPrompt' =>
        'Camera access is denied. Allow camera access in Settings.',
      'CameraAccessRestricted' => 'Camera access is restricted on this device.',
      _ =>
        'Camera error (${error.code}): ${error.description ?? 'Unknown error'}',
    };
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) {
      _showMessage('No second camera is available.');
      return;
    }
    final currentIndex = _cameras.indexOf(
      _controller?.description ?? _cameras.first,
    );
    final nextCamera = _cameras[(currentIndex + 1) % _cameras.length];
    await _initializeCamera(camera: nextCamera);
  }

  Future<void> _toggleFlash() async {
    final nextMode = switch (_flashMode) {
      FlashMode.off => FlashMode.torch,
      _ => FlashMode.off,
    };
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      _showMessage('The camera is not ready yet.');
      return;
    }
    try {
      await controller.setFlashMode(nextMode);
      if (!mounted) return;
      setState(() => _flashMode = nextMode);
    } on CameraException catch (error) {
      _showMessage(_cameraExceptionMessage(error));
    }
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }
    setState(() => _isCapturing = true);
    try {
      final photo = await controller.takePicture();
      final savedPhoto = await PhotoStorage().savePhoto(
        source: File(photo.path),
        filter: _filter,
      );
      if (!mounted) return;
      setState(() {
        _capturedPhoto = XFile(savedPhoto.path);
        _showingPhoto = true;
      });
    } on CameraException catch (error) {
      _showMessage(_cameraExceptionMessage(error));
    } on Exception catch (error) {
      _showMessage('Could not save the photo: $error');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _openGallery() async {
    final controller = _controller;
    try {
      if (controller != null && controller.value.isInitialized) {
        await controller.pausePreview();
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => RetroCamGalleryPage(storage: PhotoStorage()),
        ),
      );
    } on CameraException catch (error) {
      _showMessage(_cameraExceptionMessage(error));
    } finally {
      if (mounted &&
          controller != null &&
          controller == _controller &&
          controller.value.isInitialized) {
        try {
          await controller.resumePreview();
        } on CameraException catch (error) {
          _showMessage(_cameraExceptionMessage(error));
        }
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _showingPhoto
            ? IconButton(
                tooltip: 'Back to camera',
                onPressed: () => setState(() => _showingPhoto = false),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: Text(
          _showingPhoto ? 'YOUR SNAPSHOT' : 'RETROCAM',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Open gallery',
            onPressed: () => unawaited(_openGallery()),
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: _showingPhoto && _capturedPhoto != null
            ? _buildPhotoPreview()
            : _buildCameraScreen(),
      ),
    );
  }

  Widget _buildCameraScreen() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildViewfinder(),
                            const _ViewfinderFrame(),
                            Positioned(
                              top: 20,
                              left: 0,
                              right: 0,
                              child: Text(
                                _filter.label.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black87,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _buildFilterPicker(),
              const SizedBox(height: 16),
              _buildCameraControls(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildViewfinder() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      final matrix = _filter.matrix;
      return matrix == null
          ? CameraPreview(controller)
          : ColorFiltered(
              colorFilter: ColorFilter.matrix(matrix),
              child: CameraPreview(controller),
            );
    }

    return ColoredBox(
      color: const Color(0xFF30291F),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _cameraError == null
                    ? Icons.photo_camera_outlined
                    : Icons.no_photography_outlined,
                size: 54,
                color: _accentColor,
              ),
              const SizedBox(height: 14),
              Text(
                _isInitializing
                    ? 'Starting your camera...'
                    : _cameraError ?? 'Camera unavailable',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.5),
              ),
              if (!_isInitializing && _cameraError != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => unawaited(_initializeCamera()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPicker() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final filter in RetroFilter.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter),
                selectedColor: _accentColor,
                labelStyle: TextStyle(
                  color: _filter == filter ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide(
                  color: _filter == filter ? _accentColor : Colors.white24,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _RoundControl(
          tooltip: 'Switch camera',
          onPressed: () => unawaited(_switchCamera()),
          icon: Icons.flip_camera_ios_outlined,
        ),
        Semantics(
          label: 'Capture photo',
          button: true,
          child: GestureDetector(
            onTap: _isCapturing ? null : () => unawaited(_capturePhoto()),
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _isCapturing ? Colors.white54 : _accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: _isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
        _RoundControl(
          tooltip: _flashMode == FlashMode.off
              ? 'Turn flash on'
              : 'Turn flash off',
          onPressed: () => unawaited(_toggleFlash()),
          icon: _flashMode == FlashMode.off
              ? Icons.flash_off_outlined
              : Icons.flash_on,
          isActive: _flashMode != FlashMode.off,
        ),
      ],
    );
  }

  Widget _buildPhotoPreview() {
    final photo = _capturedPhoto!;
    final image = Image.file(
      File(photo.path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(
        color: _surfaceColor,
        child: Center(child: Text('Could not load this photo.')),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        image,
                        const _ViewfinderFrame(),
                        Positioned(
                          top: 20,
                          left: 0,
                          right: 0,
                          child: Text(
                            _filter.label.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _showingPhoto = false),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take another'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.isActive = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: isActive ? _accentColor : _surfaceColor,
        foregroundColor: isActive ? Colors.black : Colors.white,
        fixedSize: const Size(52, 52),
      ),
    );
  }
}

class _ViewfinderFrame extends StatelessWidget {
  const _ViewfinderFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class RetroCamGalleryPage extends StatefulWidget {
  const RetroCamGalleryPage({required this.storage, super.key});

  final PhotoStorage storage;

  @override
  State<RetroCamGalleryPage> createState() => _RetroCamGalleryPageState();
}

class _RetroCamGalleryPageState extends State<RetroCamGalleryPage> {
  List<SavedPhoto> _photos = [];
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPhotos());
  }

  Future<void> _loadPhotos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final photos = await widget.storage.listPhotos();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the gallery: $error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to camera',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text(
          'GALLERY',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2.4),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh gallery',
            onPressed: _isLoading ? null : () => unawaited(_loadPhotos()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _GalleryMessage(
                icon: Icons.error_outline,
                message: _error!,
                action: TextButton.icon(
                  onPressed: () => unawaited(_loadPhotos()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              )
            : _photos.isEmpty
            ? const _GalleryMessage(
                icon: Icons.photo_library_outlined,
                message: 'Your saved photos will appear here.',
              )
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.76,
                ),
                itemCount: _photos.length,
                itemBuilder: (context, index) {
                  final photo = _photos[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) => _GalleryPhotoPage(photo: photo),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            photo.file,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(
                                  color: _surfaceColor,
                                  child: Center(
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              color: Colors.black54,
                              child: Text(
                                _formatGalleryDate(photo.capturedAt),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _GalleryPhotoPage extends StatelessWidget {
  const _GalleryPhotoPage({required this.photo});

  final SavedPhoto photo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_formatGalleryDate(photo.capturedAt))),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            child: Image.file(
              photo.file,
              errorBuilder: (context, error, stackTrace) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Could not load this photo.'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryMessage extends StatelessWidget {
  const _GalleryMessage({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: _accentColor),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

String _formatGalleryDate(DateTime date) {
  final localDate = date.toLocal();
  final month = localDate.month.toString().padLeft(2, '0');
  final day = localDate.day.toString().padLeft(2, '0');
  final hour = localDate.hour % 12 == 0 ? 12 : localDate.hour % 12;
  final minute = localDate.minute.toString().padLeft(2, '0');
  final period = localDate.hour < 12 ? 'AM' : 'PM';
  return '$month/$day/${localDate.year}  '
      '${hour.toString().padLeft(2, '0')}:$minute $period';
}
