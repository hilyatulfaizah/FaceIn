import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_in/employee/change_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math'; // Import for sqrt and exp (for sigmoid)
import 'package:lottie/lottie.dart'; // Import the lottie package
import 'package:screen_brightness/screen_brightness.dart'; // Import the screen_brightness package
import '../employee/homepage_employee.dart';
import '../login.dart'; // Import the LoginPage
import 'dart:convert'; // Import for jsonEncode and jsonDecode
import 'dart:async'; // Import for Timer

class FaceRegistration extends StatefulWidget {
  final String docId;
  final String name;

  const FaceRegistration({super.key, required this.docId, required this.name});

  @override
  State<FaceRegistration> createState() => _FaceRegistrationState();
}

// Add WidgetsBindingObserver to listen to app lifecycle changes for brightness control
class _FaceRegistrationState extends State<FaceRegistration> with WidgetsBindingObserver {
  CameraController? _cameraController;
  Interpreter? _faceRecognitionInterpreter; // For generating embeddings
  Interpreter? _faceDetectionInterpreter; // For detecting faces

  bool _isInitialized = false; // True when camera and both models are ready
  bool _isRegistering = false; // True when face scan is in progress (or camera initializing)
  bool _isOnboardingComplete = false; // Controls which view is shown (onboarding vs camera)

  final double circleSize = 240;

  // New: List to store multiple embeddings for registration
  List<List<double>> _registeredEmbeddings = [];
  // New: Current step in multi-angle registration
  int _currentRegistrationStep = 0;
  // Updated instructions for continuous scan
  final List<String> _registrationInstructions = [
    "Look straight at the camera.",
    "Slowly turn your head to the left.",
    "Slowly turn your head to the right.",
    "Slowly tilt your head upwards.",
    "Slowly tilt your head downwards.",
    "Smile naturally.",
    "Look slightly up and to the right.",
  ];

  // For countdown timer
  Timer? _countdownTimer;
  int _secondsRemaining = 0;
  final int _scanDurationSeconds = 5; // Duration of the "recording" scan, changed from 10 to 5

  @override
  void initState() {
    super.initState();
    debugPrint("FaceRegistration: initState called.");
    WidgetsBinding.instance.addObserver(this); // Register observer for app lifecycle
    // Reset previous face data immediately, regardless of onboarding state
    _resetPreviousFace();
    // Camera and model initialization will now happen only after "Open Camera" is pressed
  }

  @override
  void dispose() {
    debugPrint("FaceRegistration: dispose called.");
    WidgetsBinding.instance.removeObserver(this); // Unregister observer
    _resetScreenBrightness(); // Ensure brightness is reset on dispose
    _countdownTimer?.cancel(); // Cancel any running timer
    // Only dispose if controller is not null
    _cameraController?.dispose();
    // Wrap interpreter close calls in try-catch to prevent "already deleted" errors
    try {
      _faceRecognitionInterpreter?.close();
    } on StateError catch (e) {
      debugPrint("Warning: _faceRecognitionInterpreter already deleted during dispose: $e");
    } finally {
      _faceRecognitionInterpreter = null;
    }

    try {
      _faceDetectionInterpreter?.close();
    } on StateError catch (e) {
      debugPrint("Warning: _faceDetectionInterpreter already deleted during dispose: $e");
    } finally {
      _faceDetectionInterpreter = null;
    }
    super.dispose();
  }

  /// Handles app lifecycle state changes to manage screen brightness.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("App lifecycle state changed: $state");
    // Only manage brightness if we are on the camera registration view
    if (_isOnboardingComplete && _isInitialized) {
      if (state == AppLifecycleState.resumed) {
        _setScreenBrightnessForScan(); // Re-apply brightness if app resumes
      } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
        _resetScreenBrightness(); // Reset brightness if app goes to background/inactive
      }
    }
  }

  /// Sets the screen brightness to a high value for face scanning.
  Future<void> _setScreenBrightnessForScan() async {
    try {
      // Set brightness to 90% for better face scanning conditions
      await ScreenBrightness().setScreenBrightness(0.9);
      debugPrint("Screen brightness set to 0.9");
    } catch (e) {
      debugPrint("Failed to set screen brightness: $e");
      // Optionally, show a message to the user if brightness cannot be controlled
    }
  }

  /// Resets the screen brightness to the system's default.
  Future<void> _resetScreenBrightness() async {
    try {
      await ScreenBrightness().resetScreenBrightness();
      debugPrint("Screen brightness reset to system default");
    } catch (e) {
      debugPrint("Failed to reset screen brightness: $e");
    }
  }

  Future<void> _resetPreviousFace() async {
    debugPrint("Resetting previous face data...");
    try {
      // Use FieldValue.delete() to remove the 'embeddings' field entirely
      await FirebaseFirestore.instance.collection('Employee').doc(widget.docId).update({
        'hasRegisteredFace': false,
        'embeddings': FieldValue.delete(),
      });
      debugPrint("Previous face data cleared successfully.");
    } catch (e) {
      // If the field doesn't exist, update will throw an error, which is fine.
      // We can ignore the error if it's just that the field isn't there.
      if (e is FirebaseException && e.code == 'not-found') {
        debugPrint("Previous 'embeddings' field not found, no need to delete.");
      } else {
        debugPrint("Error clearing face data: $e");
      }
    }
  }

  Future<void> _initializeCameraAndModel() async {
    debugPrint("Initializing camera and models...");
    // If a controller already exists and is initialized, dispose it first for a clean re-init
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      await _cameraController!.dispose();
      _cameraController = null; // Nullify after disposing
      debugPrint("Disposed existing camera controller.");
    }

    // Close existing interpreters if they are open and not null, then nullify them
    // Use try-catch here to prevent "already deleted" errors if dispose was called previously
    try {
      _faceRecognitionInterpreter?.close();
    } on StateError catch (e) {
      debugPrint("Warning: _faceRecognitionInterpreter already deleted during re-init: $e");
    } finally {
      _faceRecognitionInterpreter = null;
    }

    try {
      _faceDetectionInterpreter?.close();
    } on StateError catch (e) {
      debugPrint("Warning: _faceDetectionInterpreter already deleted during re-init: $e");
    } finally {
      _faceDetectionInterpreter = null;
    }


    setState(() {
      _isInitialized = false; // Set to false while initializing
      _isRegistering = true; // Show loading indicator during camera setup
    });

    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere((cam) => cam.lensDirection == CameraLensDirection.front);

      // Changed ResolutionPreset to .high for consistency
      _cameraController = CameraController(frontCamera, ResolutionPreset.high, enableAudio: false);
      await _cameraController!.initialize(); // Use ! because we just created it

      // Load both TFLite models with individual try-catch for better error reporting
      try {
        _faceRecognitionInterpreter = await Interpreter.fromAsset('assets/models/mobilefacenet_float32.tflite');
        debugPrint("mobilefacenet_float32.tflite loaded.");
      } catch (e) {
        debugPrint("Error loading mobilefacenet_float32.tflite: $e");
        _faceRecognitionInterpreter = null; // Ensure null if loading fails
      }

      try {
        // Changed to blazeface_front.tflite - ensure you have this model!
        _faceDetectionInterpreter = await Interpreter.fromAsset('assets/models/blazeface_front.tflite');
        debugPrint("blazeface_front.tflite loaded.");
      } catch (e) {
        debugPrint("Error loading blazeface_front.tflite: $e");
        _faceDetectionInterpreter = null; // Ensure null if loading fails
      }

      // Verify interpreters loaded successfully
      if (_faceRecognitionInterpreter == null || _faceDetectionInterpreter == null) {
        throw Exception("One or more TFLite models failed to load. Check console for details.");
      }

      setState(() => _isInitialized = true); // Correctly set to true when ready
      debugPrint("Camera and models initialized successfully.");
      debugPrint("Face Recognition Interpreter: ${_faceRecognitionInterpreter != null ? 'Loaded' : 'NULL'}");
      debugPrint("Face Detection Interpreter: ${_faceDetectionInterpreter != null ? 'Loaded' : 'NULL'}");

      // Debugging: Print interpreter input/output details
      debugPrint("\n--- Face Detection Interpreter Details ---");
      for (var input in _faceDetectionInterpreter!.getInputTensors()) {
        debugPrint("Input: Name=${input.name}, Shape=${input.shape}, Type=${input.type}");
      }
      for (var output in _faceDetectionInterpreter!.getOutputTensors()) {
        debugPrint("Output: Name=${output.name}, Shape=${output.shape}, Type=${output.type}");
      }
      debugPrint("----------------------------------------\n");

      // Set screen brightness after camera and models are initialized
      _setScreenBrightnessForScan();


    } catch (e) {
      debugPrint("Initialization failed: $e");
      String errorMessage = 'Camera or model initialization failed: ${e.toString()}';
      if (e.toString().contains("TFLite models failed to load")) {
        errorMessage = "Error loading AI models. Please ensure 'mobilefacenet_float32.tflite' and 'blazeface_front.tflite' are in your assets/models folder and pubspec.yaml is updated.";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      // If initialization fails, go back to onboarding and reset state
      setState(() {
        _isOnboardingComplete = false;
        _isInitialized = false; // Correctly set to false on failure
        _cameraController = null; // Ensure controller is nullified on failure
        _faceRecognitionInterpreter?.close();
        _faceDetectionInterpreter?.close();
        _faceRecognitionInterpreter = null;
        _faceDetectionInterpreter = null;
      });
      _resetScreenBrightness(); // Reset brightness on initialization failure
    } finally {
      setState(() {
        _isRegistering = false; // Hide loading indicator
      });
    }
  }

  /// Converts an image to Float32List for MobileFaceNet.
  Float32List _imageToFloat32List(img.Image image) {
    final img.Image resized = img.copyResize(image, width: 112, height: 112);
    final Float32List buffer = Float32List(1 * 112 * 112 * 3);
    int index = 0;

    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final pixel = resized.getPixel(x, y);
        final r = img.getRed(pixel);
        final g = img.getGreen(pixel);
        final b = img.getBlue(pixel);

        buffer[index++] = (r - 127.5) / 128.0;
        buffer[index++] = (g - 127.5) / 128.0;
        buffer[index++] = (b - 127.5) / 128.0;
      }
    }
    return buffer;
  }

  // --- BlazeFace Anchor Box Generation and Decoding ---
  // These constants are specific to the BlazeFace model (128x128 input)
  static const int _outputChannels = 16; // 4 box coords + 12 landmarks
  static const int _numAnchors = 896; // Total number of anchors
  static const List<double> _strides = [8.0, 16.0];
  static const double _anchorOffsetX = 0.5;
  static const double _anchorOffsetY = 0.5;
  static const double _boxCoordScale = 128.0; // Input image size for BlazeFace

  List<List<double>> _generateAnchors() {
    List<List<double>> anchors = [];
    // These scales are derived from common BlazeFace implementations for 128x128 input
    // They define the base size of anchors for each feature map.
    List<List<double>> layerScales = [
      [10.0 / _boxCoordScale, 17.0 / _boxCoordScale], // For stride 8 (16x16 feature map), 2 anchors per location
      [27.0 / _boxCoordScale, 37.0 / _boxCoordScale, 47.0 / _boxCoordScale, 57.0 / _boxCoordScale, 67.0 / _boxCoordScale, 77.0 / _boxCoordScale] // For stride 16 (8x8 feature map), 6 anchors per location
    ];
    // BlazeFace typically uses only 1.0 aspect ratio for its anchors
    List<double> aspectRatios = [1.0];

    for (int layerId = 0; layerId < _strides.length; layerId++) {
      double stride = _strides[layerId];
      int featureMapWidth = (_boxCoordScale / stride).floor();
      int featureMapHeight = (_boxCoordScale / stride).floor();

      List<double> scalesForLayer = layerScales[layerId];

      for (int y = 0; y < featureMapHeight; y++) {
        for (int x = 0; x < featureMapWidth; x++) {
          for (double scale in scalesForLayer) {
            for (double aspectRatio in aspectRatios) {
              double w = scale * aspectRatio;
              double h = scale / aspectRatio;
              double cx = (x + _anchorOffsetX) * stride / _boxCoordScale;
              double cy = (y + _anchorOffsetY) * stride / _boxCoordScale;
              anchors.add([cx, cy, w, h]); // cx, cy, w, h (normalized)
            }
          }
        }
      }
    }
    debugPrint("Generated ${anchors.length} anchors."); // Add debug print for anchor count
    return anchors;
  }

  // Non-Maximum Suppression (NMS) implementation
  List<Tuple<Rect, double>> _nonMaxSuppression(List<Tuple<Rect, double>> boxes, double iouThreshold) {
    if (boxes.isEmpty) return [];

    // Sort by confidence score in descending order
    boxes.sort((a, b) => b.item2.compareTo(a.item2));

    List<Tuple<Rect, double>> selectedBoxes = [];
    List<bool> suppressed = List.filled(boxes.length, false);

    for (int i = 0; i < boxes.length; i++) {
      if (suppressed[i]) continue;

      selectedBoxes.add(boxes[i]);

      for (int j = i + 1; j < boxes.length; j++) {
        if (suppressed[j]) continue;

        double iou = _calculateIoU(boxes[i].item1, boxes[j].item1);
        if (iou > iouThreshold) {
          suppressed[j] = true;
        }
      }
    }
    return selectedBoxes;
  }

  // Calculate Intersection over Union (IoU)
  double _calculateIoU(Rect box1, Rect box2) {
    double xA = max(box1.left, box2.left);
    double yA = max(box1.top, box2.top);
    double xB = min(box1.right, box2.right);
    double yB = min(box1.bottom, box2.bottom);

    double intersectionArea = max(0.0, xB - xA) * max(0.0, yB - yA);
    double box1Area = box1.width * box1.height;
    double box2Area = box2.width * box2.height; 

    double unionArea = box1Area + box2Area - intersectionArea;
    return unionArea == 0 ? 0 : intersectionArea / unionArea;
  }


/// Performs face detection and returns the largest face bounding box.
/// Returns null if no face is detected.
Rect? _detectFace(img.Image image) {
  debugPrint("Starting face detection. Input image dimensions: ${image.width}x${image.height}");
  if (_faceDetectionInterpreter == null) {
    debugPrint("Face detection interpreter is NULL. Cannot run detection.");
    return null;
  }

  final img.Image rgbImage = img.Image.fromBytes(
    image.width,
    image.height,
    image.getBytes(format: img.Format.rgb),
    format: img.Format.rgb,
  );

  final int inputSize = 128; // BlazeFace input size
  final img.Image resized = img.copyResize(rgbImage, width: inputSize, height: inputSize);

  final Float32List inputBuffer = Float32List(1 * inputSize * inputSize * 3);
  int pixelIndex = 0;
  for (int y = 0; y < inputSize; y++) {
    for (int x = 0; x < inputSize; x++) {
      final pixel = resized.getPixel(x, y);
      inputBuffer[pixelIndex++] = img.getRed(pixel) / 255.0;
      inputBuffer[pixelIndex++] = img.getGreen(pixel) / 255.0;
      inputBuffer[pixelIndex++] = img.getBlue(pixel) / 255.0;
    }
  }

  final inputTensor = inputBuffer.reshape([1, inputSize, inputSize, 3]);

  // Outputs for BlazeFace:
  // Output 0 (regressors): [1, 896, 16] - Bounding box and landmark data
  // Output 1 (classificators): [1, 896, 1] - Confidence scores (logits)
  final Map<int, Object> outputs = {
    0: List.filled(1 * _numAnchors * _outputChannels, 0.0).reshape([1, _numAnchors, _outputChannels]),
    1: List.filled(1 * _numAnchors * 1, 0.0).reshape([1, _numAnchors, 1]),
  };

  try {
    _faceDetectionInterpreter!.runForMultipleInputs([inputTensor], outputs);
    debugPrint("BlazeFace detection ran successfully.");
  } catch (e) {
    debugPrint("Error running face detection model: $e");
    return null;
  }

  final List<List<List<double>>> rawBoxes = (outputs[0] as List<dynamic>)
      .map((e) => (e as List<dynamic>)
          .map((f) => (f as List<dynamic>).cast<double>().toList())
          .toList())
      .toList();

  final List<List<List<double>>> rawScores = (outputs[1] as List<dynamic>)
      .map((e) => (e as List<dynamic>)
          .map((f) => (f as List<dynamic>).cast<double>().toList())
          .toList())
      .toList();

  List<List<double>> anchors = _generateAnchors();
  List<Tuple<Rect, double>> detectedFaces = [];

  // Define the detection confidence threshold
  const double detectionConfidenceThreshold = 0.7; // Set detection threshold to 0.7

  for (int i = 0; i < _numAnchors; i++) {
    final double rawScore = rawScores[0][i][0];
    final double score = 1.0 / (1.0 + exp(-rawScore)); // Apply sigmoid to get probability

    // Filter by confidence threshold
    if (score < detectionConfidenceThreshold) { // Use the new constant
      continue;
    }

    // Decode bounding box from raw regressors and anchor
    final List<double> anchor = anchors[i]; // This is where the RangeError was occurring
    final List<double> boxData = rawBoxes[0][i];

    // Center x, y, width, height for the predicted box
    double centerY = boxData[0] / _boxCoordScale + anchor[0];
    double centerX = boxData[1] / _boxCoordScale + anchor[1];
    double h = boxData[2] / _boxCoordScale;
    double w = boxData[3] / _boxCoordScale;

    // Convert center-width-height to xmin, ymin, xmax, ymax (normalized)
    double ymin = centerY - h / 2.0;
    double xmin = centerX - w / 2.0;
    double ymax = centerY + h / 2.0;
    double xmax = centerX + w / 2.0;

    // Convert normalized coordinates to original image pixel coordinates
    final left = (xmin * image.width).clamp(0, image.width).toDouble();
    final top = (ymin * image.height).clamp(0, image.height).toDouble();
    final right = (xmax * image.width).clamp(0, image.width).toDouble();
    final bottom = (ymax * image.height).clamp(0, image.height).toDouble();

    // Ensure valid bounding box dimensions and a minimum size
    if (right > left && bottom > top && (right - left) > 20 && (bottom - top) > 20) {
      detectedFaces.add(Tuple(Rect.fromLTRB(left, top, right, bottom), score));
      debugPrint("Decoded Face candidate: Score=$score, Box=Rect.fromLTRB($left, $top, $right, $bottom)");
    } else {
      debugPrint("Decoded Candidate filtered out (invalid dimensions): Score=$score, Box=Rect.fromLTRB($left, $top, $right, $bottom)");
    }
  }

  // Apply Non-Maximum Suppression
  List<Tuple<Rect, double>> nmsResults = _nonMaxSuppression(detectedFaces, 0.3); // IoU threshold for NMS

  if (nmsResults.isEmpty) {
    debugPrint("No faces detected after NMS.");
    return null;
  }

  // Select the highest scoring face after NMS
  nmsResults.sort((a, b) => b.item2.compareTo(a.item2));
  Rect bestBox = nmsResults.first.item1;
  double bestScore = nmsResults.first.item2;

  debugPrint("Final best face detected after NMS: Score=$bestScore, Box=$bestBox");
  return bestBox;
}


  Future<void> _startRegistrationScan() async {
    debugPrint("Starting face registration scan...");
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not ready. Please wait or try again.')),
      );
      debugPrint("Registration scan aborted: Camera not ready.");
      return;
    }
    if (_faceDetectionInterpreter == null || _faceRecognitionInterpreter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI models not loaded. Please restart the registration.')),
      );
      debugPrint("Registration scan aborted: Models not loaded.");
      return;
    }

    setState(() {
      _isRegistering = true; // Indicate that scan is in progress
      _registeredEmbeddings.clear(); // Clear previous embeddings for a new scan
      _secondsRemaining = _scanDurationSeconds; // Start countdown
    });

    // Start countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsRemaining--;
        });
      }
      if (_secondsRemaining == 0) {
        timer.cancel();
      }
    });

    // Capture multiple photos over the scan duration
    final int numberOfPhotos = 7; // Capture 7 photos over 5 seconds
    final int delayBetweenPhotosMs = (_scanDurationSeconds * 1000) ~/ numberOfPhotos;

    List<XFile> capturedPhotos = [];
    for (int i = 0; i < numberOfPhotos; i++) {
      try {
        final file = await _cameraController!.takePicture();
        capturedPhotos.add(file);
        debugPrint("Captured photo ${i + 1}/${numberOfPhotos}");
      } catch (e) {
        debugPrint("Error taking picture during scan: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error capturing photo: ${e.toString()}')),
        );
        // Continue trying to capture other photos even if one fails
      }
      await Future.delayed(Duration(milliseconds: delayBetweenPhotosMs));
    }

    _countdownTimer?.cancel(); // Ensure timer is cancelled after capture loop

    // Process all captured photos
    for (XFile file in capturedPhotos) {
      try {
        final rawBytes = await File(file.path).readAsBytes();
        final originalImage = img.decodeImage(rawBytes);
        if (originalImage == null) {
          debugPrint("Failed to decode image from ${file.path}");
          continue; // Skip this image if decoding fails
        }

        final Rect? faceRect = _detectFace(originalImage);
        if (faceRect != null) {
          img.Image imageToProcess = img.copyCrop(
            originalImage,
            faceRect.left.toInt(),
            faceRect.top.toInt(),
            faceRect.width.toInt(),
            faceRect.height.toInt(),
          );

          if (imageToProcess.width == 0 || imageToProcess.height == 0) {
            debugPrint("Cropped image is empty, skipping embedding generation.");
            continue;
          }

          final input = _imageToFloat32List(imageToProcess);
          final output = List.generate(1, (_) => List.filled(128, 0.0));
          _faceRecognitionInterpreter!.run(input.reshape([1, 112, 112, 3]), output);

          List<double> embedding = List<double>.from(output[0]);
          double norm = sqrt(embedding.fold(0.0, (sum, val) => sum + val * val));

          if (norm != 0 && !embedding.any((e) => e.isNaN || e.isInfinite)) {
            embedding = embedding.map((e) => e / norm).toList();
            _registeredEmbeddings.add(embedding);
            debugPrint("Generated and added embedding from a captured photo.");
          } else {
            debugPrint("Invalid embedding generated from a captured photo. Skipping.");
          }
        } else {
          debugPrint("No face detected in one of the captured photos. Skipping embedding generation.");
        }
      } catch (e) {
        debugPrint("Error processing captured photo for embedding: $e");
        // Continue to the next photo even if one fails
      }
    }

    if (_registeredEmbeddings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid face captures during scan. Please try again.')),
      );
      if (mounted) {
        setState(() {
          _isRegistering = false;
          _secondsRemaining = 0;
        });
      }
      return;
    }

    // Now, proceed with confirmation and saving
    final bool? confirmSave = await _showConfirmationDialog();

    if (confirmSave == true) {
      final String embeddingsJson = jsonEncode(_registeredEmbeddings);
      await FirebaseFirestore.instance.collection('Employee').doc(widget.docId).update({
        'hasRegisteredFace': true,
        'embeddings': embeddingsJson,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Face successfully registered with multiple angles!')),
      );

      await Future.delayed(const Duration(seconds: 1));

      final bool? changePassword = await _showPasswordChangePrompt();

      if (changePassword == true) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
          );
        }
      } else {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HomepageEmployee(name: widget.name)),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Face registration cancelled.')),
      );
      debugPrint("Face registration cancelled by user.");
      if (mounted) {
        setState(() {
          _currentRegistrationStep = 0; // Reset step
          _registeredEmbeddings.clear(); // Clear embeddings
        });
      }
    }

    if (mounted) {
      setState(() {
        _isRegistering = false;
        _secondsRemaining = 0;
      });
    }
  }


  /// Displays a confirmation dialog for face registration.
  /// Returns true if user confirms, false otherwise.
  Future<bool?> _showConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must make a choice
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Multi-Angle Registration?'), // Simplified title
        content: Column( // Used const as content is static
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have captured your face from ${_registeredEmbeddings.length} angles. Are you satisfied with these captures?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 15), // Adjusted spacing
            const Text(
              'Confirming will save these faces to your profile for better accuracy.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // User cancels
            child: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true), // User confirms
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  /// Displays a dialog prompting the user to change their password.
  /// Returns true if user chooses to change password, false if they choose "Later".
  Future<bool?> _showPasswordChangePrompt() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must make a choice
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Security Recommendation'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'For enhanced security, we recommend changing your password now.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 15),
            Text(
              'You can do this later from your profile settings if you prefer.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Choose "Later"
            child: const Text('Later', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true), // Choose "Change Password"
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Change Password'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () {
            if (_isOnboardingComplete) {
              // If on camera view, go back to onboarding
              setState(() {
                _isOnboardingComplete = false;
                _isInitialized = false; // Set to false when going back to onboarding
                _currentRegistrationStep = 0; // Reset step
                _registeredEmbeddings.clear(); // Clear embeddings
                // Dispose camera controller when moving back to onboarding
                _cameraController?.dispose();
                _cameraController = null; // Nullify the controller
                // Reset interpreter states as well
                // These will be closed and nulled by the dispose method when the widget is removed
                // from the tree, or by the re-initialization logic in _initializeCameraAndModel.
                // No need to explicitly close/nullify here again.
              });
            } else {
              // If on onboarding view, go back to LoginPage
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            }
          },
        ),
      ),
      body: _isOnboardingComplete
          ? _buildCameraRegistrationView()
          : _buildOnboardingView(context),
    );
  }

  /// Builds the onboarding view for face registration.
  Widget _buildOnboardingView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title
          const Text(
            'Take Selfie',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          // Subtitle
          Text(
            'We use your selfie to compare with your registered profile.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          // Lottie Animation
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Lottie.asset(
              'assets/lottie/face_scan_animation.json', // Updated Lottie path
              width: 150, // Adjust size as needed
              height: 150, // Adjust size as needed
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 40),

          // Instructions List
          _buildInstructionItem(
            context,
            number: 1,
            title: 'Good lighting',
            description: 'Make sure you are in a well-lit area and both ears are uncovered.',
          ),
          const SizedBox(height: 20),
          _buildInstructionItem(
            context,
            number: 2,
            title: 'Look straight',
            description: 'Hold your phone at eye level and look straight to the camera.',
          ),
          const Spacer(), // Pushes content to the top and button to the bottom

          // Open Camera Button
          ElevatedButton(
            onPressed: _isRegistering ? null : () { // Disable button if camera is initializing
              setState(() {
                _isOnboardingComplete = true;
                _currentRegistrationStep = 0; // Start from the first step
                _registeredEmbeddings.clear(); // Clear any old embeddings
              });
              _initializeCameraAndModel(); // Initialize camera and model
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600, // Engaging button color
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 55), // Full width button
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 5,
            ),
            child: _isRegistering
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Open Camera',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Builds the camera registration view.
  Widget _buildCameraRegistrationView() {
    // Show loading indicator if camera controller is null or not initialized
    if (!_isInitialized) { // Use _isInitialized here to check overall readiness
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _isRegistering ? 'Initializing camera...' : 'Preparing for face scan...',
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    // Otherwise, show the camera preview
    return Stack(
      children: [
        // Camera Preview (fills the entire available space)
        Center( // Centered to ensure the circle is in the middle
          child: ClipOval(
            child: SizedBox(
              width: circleSize,
              height: circleSize,
              child: FittedBox( // Use FittedBox to ensure the camera feed fills the circle without stretching
                fit: BoxFit.cover, // This makes the camera fill the box, cropping if necessary
                child: SizedBox( // This SizedBox provides the original aspect ratio to FittedBox
                  // Use the actual preview size from the camera controller
                  width: _cameraController!.value.previewSize!.height,
                  height: _cameraController!.value.previewSize!.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),
          ),
        ),

        // White Overlay with Circular Hole (covers the camera preview, showing only the hole)
        _WhiteOverlayWithHole(
          diameter: circleSize,
          borderColor: Colors.orange.shade400, // Changed border color to green
          borderWidth: 4.0, // Existing border width
        ),

        // Content positioned above the circle
        Positioned(
          top: MediaQuery.of(context).size.height * 0.1, // Adjust top position dynamically
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min, // Use min to wrap content
            children: [
              Text(
                _isRegistering && _secondsRemaining > 0
                    ? "Recording... $_secondsRemaining"
                    : _registrationInstructions[min(_currentRegistrationStep, _registrationInstructions.length - 1)], // Dynamic instruction
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade400, // Themed color
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8), // Spacing
              if (!_isRegistering || _secondsRemaining == 0) // Only show step indicator when not actively recording
                Text(
                  "Step ${_currentRegistrationStep + 1} of ${_registrationInstructions.length}", // Step indicator
                  style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),

        // Content positioned below the circle (button and loading indicator)
        Positioned(
          bottom: MediaQuery.of(context).size.height * 0.1, // Adjust bottom position dynamically
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min, // Use min to wrap content
            children: [
              ElevatedButton( // Changed from ElevatedButton.icon to ElevatedButton
                onPressed: _isRegistering ? null : _startRegistrationScan, // Call the new scan function
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600, // Themed color
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: Text(
                  _isRegistering
                      ? "Scanning..."
                      : "Start Scan", // Dynamic button text
                ),
              ),
              if (_isRegistering) Padding(
                padding: const EdgeInsets.only(top: 20),
                child: CircularProgressIndicator(color: Colors.orange.shade400), // Themed color
              )
            ],
          ),
        ),
      ],
    );
  }

  // Helper widget to build each instruction item
  Widget _buildInstructionItem(BuildContext context, {
    required int number,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF8F53A7), // Green circle for number
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                description,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Custom painter to make white screen with circular hole
class _WhiteOverlayWithHole extends StatelessWidget {
  final double diameter;
  final Color? borderColor; // Made nullable
  final double borderWidth;

  const _WhiteOverlayWithHole({
    required this.diameter,
    this.borderColor,
    this.borderWidth = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return IgnorePointer(
        ignoring: true,
        child: CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _HolePainter(
            diameter,
            borderColor ?? Colors.transparent, // Provide a default if null
            borderWidth,
          ),
        ),
      );
    });
  }
}

class _HolePainter extends CustomPainter {
  final double diameter;
  final Color borderColor; // Keep it non-nullable here, as default is provided by _WhiteOverlayWithHole
  final double borderWidth;

  _HolePainter(this.diameter, this.borderColor, this.borderWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final center = Offset(size.width / 2, size.height / 2);
    final hole = Path()..addOval(Rect.fromCircle(center: center, radius: diameter / 2));

    path.addPath(hole, Offset.zero);
    path.fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw the border around the hole
    if (borderWidth > 0 && borderColor != Colors.transparent) {
      final borderPaint = Paint()
        ..color = borderColor // This should now always be a valid Color
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth;
      canvas.drawCircle(center, diameter / 2, borderPaint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    // Only repaint if diameter, borderColor, or borderWidth changes
    return oldDelegate is _HolePainter &&
        (oldDelegate.diameter != diameter ||
            oldDelegate.borderColor != borderColor ||
            oldDelegate.borderWidth != borderWidth);
  }
}

// Helper class for Tuple (Rect, double)
class Tuple<T1, T2> {
  final T1 item1;
  final T2 item2;
  Tuple(this.item1, this.item2);
}