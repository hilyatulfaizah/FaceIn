// scan_gps_employee.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:face_in/push_notification_service.dart';
import 'package:screen_brightness/screen_brightness.dart'; // Import the screen_brightness package
import 'dart:convert'; // Import for jsonEncode and jsonDecode

// This file contains the logic for employee GPS scanning, face verification,
// and recording attendance/break punches, including sending notifications to admins.

class ScanGpsEmployee extends StatefulWidget {
  final String scanType; // Defines if it's for 'attendance' or 'break'
  final String punchType; // Defines if it's 'in' or 'out'

  const ScanGpsEmployee({
    super.key,
    required this.scanType,
    required this.punchType,
  });

  @override
  State<ScanGpsEmployee> createState() => _ScanGpsEmployeeState();
}

// Add WidgetsBindingObserver to listen to app lifecycle changes for brightness control
class _ScanGpsEmployeeState extends State<ScanGpsEmployee> with WidgetsBindingObserver {
  // Google Maps related state variables
  LatLng? _currentPosition; // Stores the current geographical coordinates
  GoogleMapController? _mapController; // Controller for the Google Map widget
  final Set<Circle> _circles = {}; // Set to store circles on the map (for company location)

  // UI related state variables
  String _buttonText = "Clock In"; // Text displayed on the main action button
  String? _punchOutTime; // Stores the formatted punch-out time
  String? _currentAddress; // Stores the human-readable current address
  bool _isLocationLoading = true; // New flag to track location fetching status

  // TFLite models for face verification
  Interpreter? _faceRecognitionInterpreter; // TFLite interpreter for mobilefacenet
  Interpreter? _faceDetectionInterpreter; // TFLite interpreter for blazeface
  bool _modelsLoaded = false; // Flag to indicate if both TFLite models are loaded
  bool _isProcessing = false; // Flag to indicate if face verification is in progress

  // Timer for clock-in/out functionality (if applicable, though not directly used in the provided snippets for timer-based actions)
  Timer? _clockInTimer;
  DateTime? _clockInDateTime; // Stores the clock-in or break-in timestamp

  // Face scan UI related state variables
  bool _showFaceScan = false; // Controls visibility of the face scan camera UI
  CameraController? _cameraController; // Controller for the camera preview
  bool _isCameraInitialized = false; // Flag to indicate if the camera is initialized
  final double _circleSize = 240; // Diameter of the face scan circle

  // Company location details for geofencing
  String? _companyId;
  double? _companyLat;
  double? _companyLng;
  double? _companyRadius;
  String? _companyCheckInTime; // Added for check-in time
  String? _companyCheckOutTime; // Added for check-out time

  // StreamSubscription for real-time company location updates
  StreamSubscription<DocumentSnapshot>? _companyLocationSubscription;

  // Controller for the remark text field
  final TextEditingController _remarkController = TextEditingController();


  @override
  void initState() {
    super.initState();
    debugPrint("ScanGpsEmployee: initState called.");
    WidgetsBinding.instance.addObserver(this); // Register observer for app lifecycle
    // Initialize location, load face recognition model, and check today's attendance status
    _getCurrentLocation();
    _loadModels(); // Load both face detection and recognition models
    _checkTodayAttendance();
    _fetchEmployeeCompanyIdAndListenToCompanyLocation(); // Updated call
  }

  @override
  void dispose() {
    debugPrint("ScanGpsEmployee: dispose called.");
    WidgetsBinding.instance.removeObserver(this); // Unregister observer
    _resetScreenBrightness(); // Ensure brightness is reset on dispose
    _companyLocationSubscription?.cancel(); // Cancel the real-time listener
    // Dispose all controllers and timers to prevent memory leaks
    _mapController?.dispose();
    _faceRecognitionInterpreter?.close();
    _faceDetectionInterpreter?.close();
    _clockInTimer?.cancel();
    _cameraController?.dispose();
    _remarkController.dispose(); // Dispose remark controller
    super.dispose();
  }

  /// Handles app lifecycle state changes to manage screen brightness.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("App lifecycle state changed: $state");
    if (_showFaceScan) { // Only manage brightness if the face scan view is active
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

  /// Fetches the current employee's companyId and then sets up a real-time listener for the company's location details.
  Future<void> _fetchEmployeeCompanyIdAndListenToCompanyLocation() async {
    debugPrint("Fetching employee company ID and setting up listener...");
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      final employeeDoc = await FirebaseFirestore.instance.collection('Employee').doc(uid).get();
      debugPrint("Employee document exists: ${employeeDoc.exists}");
      if (employeeDoc.exists) {
        final data = employeeDoc.data();
        if (mounted) { // Check mounted before setState
          setState(() {
            _companyId = data?['companyId'];
          });
        }
        debugPrint("Fetched companyId: $_companyId");
        if (_companyId != null) {
          _listenToCompanyLocation(_companyId!); // Start listening to company location
        } else {
          debugPrint("Company ID is null for employee $uid.");
          _showMessage('Your company ID is not set. Please contact admin.', Colors.orange);
        }
      } else {
        debugPrint("Employee document not found for UID: $uid");
        _showMessage('Employee profile not found. Please contact admin.', Colors.red);
      }
    } catch (e) {
      debugPrint("Error fetching employee company details: $e");
      if (mounted) {
        _showMessage('Error fetching company details: ${e.toString()}', Colors.red);
      }
    }
  }

  /// Sets up a real-time listener for the company's allowed location and radius from Firestore.
  void _listenToCompanyLocation(String companyId) {
    debugPrint("Attaching real-time listener for companyId: $companyId");
    // Cancel any existing subscription to prevent multiple listeners
    _companyLocationSubscription?.cancel();

    _companyLocationSubscription = FirebaseFirestore.instance
        .collection('companies')
        .doc(companyId)
        .snapshots()
        .listen((snapshot) {
      debugPrint("Company document snapshot received!");
      debugPrint("Snapshot exists: ${snapshot.exists}");
      if (snapshot.exists) {
        final data = snapshot.data();
        debugPrint("Company data received: $data");
        if (mounted) { // Check mounted before setState
          setState(() {
            _companyLat = data?['mainLocationLat'];
            _companyLng = data?['mainLocationLng'];
            _companyRadius = data?['mainLocationRadius'];
            _companyCheckInTime = data?['checkInTime']; // Update check-in time
            _companyCheckOutTime = data?['checkOutTime']; // Update check-out time

            // Clear existing circles and add the updated company location circle to the map
            _circles.clear();
            if (_companyLat != null && _companyLng != null && _companyRadius != null) {
              _circles.add(
                Circle(
                  circleId: const CircleId('companyLocation'),
                  center: LatLng(_companyLat!, _companyLng!),
                  radius: _companyRadius!,
                  fillColor: Colors.blue.withOpacity(0.15),
                  strokeColor: Colors.blue,
                  strokeWidth: 2,
                ),
              );
            }
          });
        }
        debugPrint("Company location updated in state: Lat=$_companyLat, Lng=$_companyLng, Radius=$_companyRadius");
        debugPrint("Company check-in/out times updated: In=$_companyCheckInTime, Out=$_companyCheckOutTime");
        _zoomMapToFitLocations(); // Zoom map to fit both locations after fetching company data
      } else {
        debugPrint("Company document does not exist for ID: $companyId");
        _showMessage('Company location not set by admin.', Colors.orange);
        if (mounted) { // Check mounted before setState
          setState(() {
            _companyLat = null;
            _companyLng = null;
            _companyRadius = null;
            _companyCheckInTime = null;
            _companyCheckOutTime = null;
            _circles.clear(); // Clear circles if company location is removed
          });
        }
      }
    }, onError: (error) {
      debugPrint("Error listening to company location: $error");
      if (mounted) {
        _showMessage('Error listening to company location: ${error.toString()}', Colors.red);
      }
    });
  }

  /// Loads both TFLite face recognition and detection models from assets.
  Future<void> _loadModels() async {
    try {
      _faceRecognitionInterpreter = await Interpreter.fromAsset('assets/models/mobilefacenet_float32.tflite');
      _faceDetectionInterpreter = await Interpreter.fromAsset('assets/models/blazeface_front.tflite');
      if (mounted) { // Check mounted before setState
        setState(() => _modelsLoaded = true); // Set modelsLoaded to true on success
      }
      debugPrint("Face Recognition Interpreter: ${_faceRecognitionInterpreter != null ? 'Loaded' : 'NULL'}");
      debugPrint("Face Detection Interpreter: ${_faceDetectionInterpreter != null ? 'Loaded' : 'NULL'}");

      // Debugging: Print interpreter input/output details for detection model
      debugPrint("\n--- Face Detection Interpreter Details ---");
      for (var input in _faceDetectionInterpreter!.getInputTensors()) {
        debugPrint("Input: Name=${input.name}, Shape=${input.shape}, Type=${input.type}");
      }
      for (var output in _faceDetectionInterpreter!.getOutputTensors()) {
        debugPrint("Output: Name=${output.name}, Shape=${output.shape}, Type=${output.type}");
      }
      debugPrint("----------------------------------------\n");

    } catch (e) {
      debugPrint('Failed to load TFLite models: $e');
      if (mounted) {
        _showMessage('Failed to load AI models. Please check assets and try again.', Colors.red);
      }
    }
  }

  /// Fetches the current geographical location and its human-readable address.
  Future<void> _getCurrentLocation() async {
    debugPrint("Getting current location...");
    if (mounted) { // Check mounted before setState
      setState(() {
        _isLocationLoading = true; // Start loading location
      });
    }

    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        _showMessage('Location services are disabled. Please enable them.', Colors.red);
      }
      if (mounted) { // Check mounted before setState
        setState(() {
          _isLocationLoading = false; // Stop loading
        });
      }
      debugPrint("Location services disabled.");
      return;
    }

    // Check and request location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          _showMessage('Location permissions are denied. Cannot get current location.', Colors.red);
        }
        if (mounted) { // Check mounted before setState
          setState(() {
            _isLocationLoading = false; // Stop loading
          });
        }
        debugPrint("Location permissions denied.");
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        _showMessage('Location permissions are permanently denied. Please enable them in app settings.', Colors.red);
      }
      if (mounted) { // Check mounted before setState
        setState(() {
          _isLocationLoading = false; // Stop loading
        });
      }
      debugPrint("Location permissions denied forever.");
      return;
    }

    // Get the current position with high accuracy
    Position position = await Geolocator.getCurrentPosition(locationSettings: 
    const LocationSettings(accuracy: LocationAccuracy.high));
    if (!mounted) {
      if (mounted) { // Check mounted before setState
        setState(() {
          _isLocationLoading = false; // Stop loading
        });
      }
      debugPrint("Widget not mounted after getting current position.");
      return;
    }

    if (mounted) { // Check mounted before setState
      setState(() => _currentPosition = LatLng(position.latitude, position.longitude));
    }
    debugPrint("Current position fetched: Lat=${_currentPosition!.latitude}, Lng=${_currentPosition!.longitude}");

    // Convert coordinates to human-readable address
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      Placemark place = placemarks[0]; // Take the first placemark
      if (!mounted) {
        if (mounted) { // Check mounted before setState
          setState(() {
            _isLocationLoading = false; // Stop loading
          });
        }
        debugPrint("Widget not mounted after getting placemarks.");
        return;
      }
      if (mounted) { // Check mounted before setState
        setState(() => _currentAddress = "${place.name}, ${place.locality}, ${place.administrativeArea}, ${place.country}");
      }
      debugPrint("Current address fetched: $_currentAddress");
    } catch (e) {
      debugPrint("Error fetching address: $e");
      if (mounted) {
        setState(() => _currentAddress = "Unable to fetch address");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocationLoading = false; // Ensure loading stops even on address fetch error
        });
      }
      _zoomMapToFitLocations(); // Zoom map to fit both locations after getting current location
    }
  }


  /// Zooms the map camera to fit both the current location and the company location.
  void _zoomMapToFitLocations() {
    debugPrint("Attempting to zoom map to fit locations.");
    if (_mapController != null && _currentPosition != null && _companyLat != null && _companyLng != null) {
      LatLngBounds bounds;
      LatLng companyLatLng = LatLng(_companyLat!, _companyLng!);
      debugPrint("Zooming to current: $_currentPosition and company: $companyLatLng");

      // Create a LatLngBounds that includes both points
      if (_currentPosition!.latitude < companyLatLng.latitude) {
        bounds = LatLngBounds(
          southwest: LatLng(_currentPosition!.latitude, min(_currentPosition!.longitude, companyLatLng.longitude)),
          northeast: LatLng(companyLatLng.latitude, max(_currentPosition!.longitude, companyLatLng.longitude)),
        );
      } else {
        bounds = LatLngBounds(
          southwest: LatLng(companyLatLng.latitude, min(_currentPosition!.longitude, companyLatLng.longitude)),
          northeast: LatLng(_currentPosition!.latitude, max(_currentPosition!.longitude, companyLatLng.longitude)),
        );
      }

      // Add padding to the bounds
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100)); // 100 pixels padding
    } else if (_mapController != null && _currentPosition != null) {
      debugPrint("Zooming to current position only: $_currentPosition");
      // If only current position is available, just animate to it
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_currentPosition!, 15));
    } else if (_mapController != null && _companyLat != null && _companyLng != null) {
      debugPrint("Zooming to company position only: Lat=$_companyLat, Lng=$_companyLng");
      // If only company position is available, animate to it
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(_companyLat!, _companyLng!), 15));
    } else {
      debugPrint("Not enough data to zoom map: _mapController=${_mapController != null}, _currentPosition=${_currentPosition != null}, _companyLat=${_companyLat != null}");
    }
  }


  /// Checks today's attendance/break record from Firestore and updates UI accordingly.
  Future<void> _checkTodayAttendance() async {
    debugPrint("Checking today's attendance...");
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final today = DateTime.now();
    final dateStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    // Get the attendance record for the current user and today's date
    final doc = await FirebaseFirestore.instance
        .collection('Attendance')
        .doc(uid)
        .collection('Records')
        .doc(dateStr)
        .get();

    debugPrint("Attendance record for $dateStr exists: ${doc.exists}");

    if (doc.exists) {
      final data = doc.data();
      if (widget.scanType == 'attendance') {
        // Handle attendance (Clock In/Out)
        final clockIn = data?["Clock InOut.in"];
        final clockOut = data?["Clock InOut.out"];
        if (mounted) { // Check mounted before setState
          setState(() {
            if (clockIn != null) {
              _clockInDateTime = (clockIn is Timestamp) ? clockIn.toDate() : DateTime.parse(clockIn.toString());
              _buttonText = (clockOut == null) ? "Clock Out" : "Clock In";
              if (clockOut != null) {
                final outTime = (clockOut is Timestamp) ? clockOut.toDate() : DateTime.parse(clockOut.toString());
                final hour12 = outTime.hour % 12 == 0 ? 12 : outTime.hour % 12;
                final ampm = outTime.hour >= 12 ? 'PM' : 'AM';
                _punchOutTime = "${hour12.toString().padLeft(2, '0')}:${outTime.minute.toString().padLeft(2, '0')} $ampm";
              }
            } else {
              _clockInDateTime = null;
              _buttonText = "Clock In";
              _punchOutTime = null;
            }
          });
        }
      } else {
        // Handle break (Break In/Out)
        final breakIn = data?["Break.in"];
        final breakOut = data?["Break.out"];
        if (mounted) { // Check mounted before setState
          setState(() {
            if (breakIn != null) {
              _clockInDateTime = (breakIn is Timestamp) ? breakIn.toDate() : DateTime.parse(breakIn.toString());
              _buttonText = (breakOut == null) ? "Break Out" : "Break In";
              if (breakOut != null) {
                // Corrected: Declare breakOutTime here without referencing itself
                final DateTime breakOutTime = (breakOut is Timestamp) ? breakOut.toDate() : DateTime.parse(breakOut.toString());
                final hour12 = breakOutTime.hour % 12 == 0 ? 12 : breakOutTime.hour % 12;
                final ampm = breakOutTime.hour >= 12 ? 'PM' : 'AM';
                _punchOutTime = "${hour12.toString().padLeft(2, '0')}:${breakOutTime.minute.toString().padLeft(2, '0')} $ampm";
              }
            } else {
              _clockInDateTime = null;
              _buttonText = "Break In";
              _punchOutTime = null;
            }
          });
        }
      }
    } else {
      // If no record exists for today, reset states
      if (mounted) { // Check mounted before setState
        setState(() {
          _clockInDateTime = null;
          _buttonText = widget.scanType == 'attendance' ? "Clock In" : "Break In";
          _punchOutTime = null;
        });
      }
    }
  }

  /// Saves the attendance/break punch record to Firestore.
  Future<void> _saveAttendance({
    required String type,
    required DateTime time,
    required String location,
    String? remark, // Added remark parameter
  }) async {
    debugPrint("Saving attendance record...");
    final user = FirebaseAuth.instance.currentUser;
    final uid = user!.uid;
    final today = DateTime.now();
    final dateStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    // Fetch registered name (fullName) from Employee collection to update in Attendance doc
    final employeeDoc = await FirebaseFirestore.instance.collection('Employee').doc(uid).get();
    final registeredFullName = employeeDoc.data()?['fullName'] ?? 'Unknown'; // Fetch fullName

    // Update employee name in Attendance/{uid} document
    await FirebaseFirestore.instance
        .collection('Attendance')
        .doc(uid)
        .set({
          'name': registeredFullName, // Use fullName here
        }, SetOptions(merge: true)); // Use merge to avoid overwriting existing fields

    // Set or update the specific punch time and location based on scanType
    Map<String, dynamic> updateData = {
      "Clock InOut.$type": time,
      "Clock InOut.${type}_location": location,
    };
    if (remark != null && remark.isNotEmpty) {
      updateData["Clock InOut.${type}_remark"] = remark; // Save remark
    }

    if (widget.scanType == 'attendance') {
      await FirebaseFirestore.instance
          .collection('Attendance')
          .doc(uid)
          .collection('Records')
          .doc(dateStr)
          .set(updateData, SetOptions(merge: true));
    } else {
      // For break, remarks are not currently implemented, but you could extend this
      await FirebaseFirestore.instance
          .collection('Attendance')
          .doc(uid)
          .collection('Records')
          .doc(dateStr)
          .set({
            "Break.$type": time,
            "Break.${type}_location": location,
          }, SetOptions(merge: true));
    }
    debugPrint("Attendance record saved for $uid on $dateStr, type: $type.");
  }

  /// Checks if the user has already clocked in/out or broken in/out for the current day.
  Future<bool> _hasClocked({required String type}) async {
    debugPrint("Checking if already clocked $type...");
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final today = DateTime.now();
    final dateStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    final doc = await FirebaseFirestore.instance
        .collection('Attendance')
        .doc(uid)
        .collection('Records')
        .doc(dateStr)
        .get();

    bool clocked = false;
    if (widget.scanType == 'attendance') {
      clocked = doc.exists && doc.data()?["Clock InOut.$type"] != null;
    } else {
      clocked = doc.exists && doc.data()?["Break.$type"] != null;
    }
    debugPrint("Already clocked $type: $clocked");
    return clocked;
  }

  // --- Face Scan Section ---

  /// Initializes the front camera for face scanning.
  Future<void> _initCameraForFaceScan() async {
    debugPrint("Initializing camera for face scan...");
    // Dispose existing camera controller if it's already initialized
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      await _cameraController!.dispose();
      _cameraController = null;
      debugPrint("Disposed existing camera controller.");
    }

    if (mounted) { // Check mounted before setState
      setState(() {
        _isCameraInitialized = false; // Set to false while initializing
        _isProcessing = true; // Show loading indicator during camera setup
      });
    }

    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere((cam) => cam.lensDirection == CameraLensDirection.front);
      _cameraController = CameraController(frontCamera, ResolutionPreset.high, enableAudio: false);
      await _cameraController!.initialize();
      if (mounted) { // Check mounted before setState
        setState(() => _isCameraInitialized = true);
      }
      debugPrint("Camera initialized for face scan successfully.");
      _setScreenBrightnessForScan(); // Set brightness after camera init
    } catch (e) {
      debugPrint("Camera initialization failed for face scan: $e");
      if (mounted) {
        _showMessage('Camera initialization failed: ${e.toString()}', Colors.red);
      }
      if (mounted) { // Check mounted before setState
        setState(() => _isCameraInitialized = false);
        setState(() => _isProcessing = false); // Stop loading on failure
      }
      _resetScreenBrightness(); // Reset brightness on camera init failure
    } finally {
      if (mounted) { // Check mounted before setState
        setState(() => _isProcessing = false); // Hide loading indicator
      }
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
        // debugPrint("Candidate $i filtered out: Score $score below threshold (0.75).");
        continue;
      }

      // Decode bounding box from raw regressors and anchor
      final List<double> anchor = anchors[i];
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

  /// Verifies the user's face using the TFLite model and camera input.
  /// Returns true if the face matches a registered embedding, false otherwise.
  Future<bool> _verifyFaceWithCamera() async {
    debugPrint("Starting face verification with camera...");
    if (!_isCameraInitialized || _cameraController == null || !_modelsLoaded) {
      await _showResultDialog(false, "Camera or face recognition models not ready. Please try again.", accuracy: 0.0); // Pass 0.0 accuracy
      debugPrint("Verification aborted: Camera initialized: $_isCameraInitialized, Models loaded: $_modelsLoaded");
      return false;
    }
    if (mounted) { // Check mounted before setState
      setState(() => _isProcessing = true); // Indicate that processing has started
    }
    double maxSimilarity = 0.0; // Initialize max similarity
    try {
      final file = await _cameraController!.takePicture(); // Capture an image
      debugPrint("Picture taken: ${file.path}");
      final rawBytes = await File(file.path).readAsBytes();
      final originalImage = img.decodeImage(rawBytes);
      if (originalImage == null) throw Exception("Failed to decode image");

      // --- Face Detection Step ---
      debugPrint("Attempting face detection for verification...");
      final Rect? faceRect = _detectFace(originalImage);

      img.Image imageToProcess;
      if (faceRect != null) {
        // Crop the original image to the detected face bounding box
        imageToProcess = img.copyCrop(
          originalImage,
          faceRect.left.toInt(),
          faceRect.top.toInt(),
          faceRect.width.toInt(),
          faceRect.height.toInt(),
        );
        debugPrint("Face detected and cropped for verification. Cropped image dimensions: ${imageToProcess.width}x${imageToProcess.height}");
      } else {
        // If no face is detected, throw an error
        await _showResultDialog(false, "No face detected. Please ensure your face is clearly visible within the circle.", accuracy: 0.0); // Pass 0.0 accuracy
        debugPrint("No discernible face detected in the image for verification.");
        return false; // Return false immediately if no face is detected
      }

      // --- Face Recognition (Embedding) Step ---
      // Ensure the cropped image is valid before processing
      if (imageToProcess.width == 0 || imageToProcess.height == 0) {
        await _showResultDialog(false, "Failed to crop face from image. Ensure your face is clearly visible and large enough.", accuracy: 0.0); // Pass 0.0 accuracy
        debugPrint("Cropped image is empty, likely due to invalid face detection or cropping during verification.");
        return false; // Return false immediately if cropped image is empty
      }

      final input = _imageToFloat32List(imageToProcess); // Preprocess the cropped image for the recognition model
      final output = List.generate(1, (_) => List.filled(128, 0.0)); // Output buffer for the embedding
      _faceRecognitionInterpreter!.run(input.reshape([1, 112, 112, 3]), output); // Run inference
      debugPrint("Face recognition interpreter ran.");

      List<double> liveEmbedding = List<double>.from(output[0]); // Get the generated face embedding
      double norm = sqrt(liveEmbedding.fold(0.0, (sum, val) => sum + val * val));

      // Validate the embedding to ensure it's not empty or invalid
      if (norm == 0 || liveEmbedding.any((e) => e.isNaN || e.isInfinite)) {
        await _showResultDialog(false, "Face verification failed: Invalid embedding. Please ensure your face is clearly visible and try again.", accuracy: 0.0); // Pass 0.0 accuracy
        if (mounted) { // Check mounted before setState
          setState(() => _isProcessing = false);
        }
        debugPrint("Invalid embedding generated.");
        return false;
      }
      liveEmbedding = liveEmbedding.map((e) => e / norm).toList(); // Normalize the embedding
      debugPrint("Generated live embedding normalized. First 5 values: ${liveEmbedding.sublist(0, min(5, liveEmbedding.length))}");

      // Fetch the registered face embeddings from Firestore (now a JSON string)
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final snapshot = await FirebaseFirestore.instance.collection('Employee').doc(uid).get();
      debugPrint("Fetched employee document for UID: $uid. Exists: ${snapshot.exists}");

      if (snapshot.exists && snapshot.data() != null && snapshot.data()!.containsKey('embeddings')) {
        final String embeddingsJson = snapshot.get('embeddings'); // Retrieve as String
        final List<dynamic> storedEmbeddingsRaw = jsonDecode(embeddingsJson); // Decode the JSON string
        // Convert dynamic list of lists to List<List<double>>
        final List<List<double>> storedEmbeddings = storedEmbeddingsRaw
            .map((e) => (e as List<dynamic>).cast<double>().toList())
            .toList();

        debugPrint("Retrieved ${storedEmbeddings.length} stored embeddings.");

        bool isMatch = false;
        // Increased threshold for stricter matching
        const double verificationThreshold = 0.75; 
        debugPrint("Verification Threshold set to: $verificationThreshold");

        for (List<double> storedEmbedding in storedEmbeddings) {
          double currentSimilarity = _calculateSimilarity(liveEmbedding, storedEmbedding);
          if (currentSimilarity > maxSimilarity) {
            maxSimilarity = currentSimilarity; // Update max similarity
          }
          debugPrint("Comparing with a stored embedding. Current similarity: $currentSimilarity (Threshold: $verificationThreshold)");
          if (currentSimilarity > verificationThreshold) {
            isMatch = true;
            break; // Found a match, no need to check further
          }
        }

        if (isMatch) {
          await _showResultDialog(true, "Face verified successfully!", accuracy: maxSimilarity);
          debugPrint("Face match successful with one of the registered embeddings. Max similarity: $maxSimilarity");
          return true;
        } else {
          await _showResultDialog(false, "Face verification failed! Only the registered person can clock in/out. Please try again.", accuracy: maxSimilarity);
          debugPrint("Face match failed against all registered embeddings. Max similarity: $maxSimilarity");
          return false;
        }
      } else {
        await _showResultDialog(false, "No registered face found for this user. Please register your face first.", accuracy: 0.0); // Pass 0.0 accuracy
        debugPrint("No registered face embeddings found for UID: $uid.");
        return false;
      }
    } catch (e) {
      debugPrint("Face verification error: $e");
      String errorMessage = "Verification failed due to an error: ${e.toString()}.";
      // Specific error messages are now handled earlier in the function
      await _showResultDialog(false, errorMessage, accuracy: maxSimilarity); // Pass calculated accuracy
      return false;
    } finally {
      if (mounted) { // Check mounted before setState
        setState(() => _isProcessing = false); // End processing indicator
      }
      debugPrint("Face verification process finished.");
    }
  }

  /// Displays a customizable dialog for success or failure messages.
  /// Now includes an optional accuracy parameter.
  Future<void> _showResultDialog(bool success, String message, {double accuracy = 0.0}) async {
    debugPrint("Showing result dialog: Success=$success, Message=$message, Accuracy=$accuracy");
    String accuracyText = (accuracy * 100).toStringAsFixed(2); // Format as percentage

    await showDialog(
      context: context,
      barrierDismissible: false, // User must tap OK to dismiss
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(success ? Icons.check_circle : Icons.error, color: success ? Colors.green : Colors.red, size: 32),
            const SizedBox(width: 10),
            Text(
              success ? "Success" : "Failed",
              style: TextStyle(color: success ? Colors.green : Colors.red),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 16)),
            if (accuracy > 0) ...[ // Only show accuracy if it was calculated
              const SizedBox(height: 10),
              Text(
                "Accuracy: $accuracyText%",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(), // Dismiss the dialog
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  /// Calculates the cosine similarity between two face embeddings.
  double _calculateSimilarity(List<double> a, List<double> b) {
    double dot = 0;
    double normA = 0;
    double normB = 0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    return (sqrt(normA) * sqrt(normB)) == 0 ? 0 : dot / (sqrt(normA) * sqrt(normB));
  }

  bool _isFaceMatch(List<double> a, List<double> b, {double threshold = 0.7}) { // Set default threshold to 0.7
    double similarity = _calculateSimilarity(a, b);
    debugPrint("Face match similarity: $similarity (Threshold: $threshold)"); // Added debug print
    return similarity > threshold;
  }

  /// Helper to check if a clock-in was late based on company's check-in time.
  bool _isLate(DateTime punchTime) {
    if (widget.scanType != 'attendance' || widget.punchType != 'in') {
      return false; // Only check lateness for attendance clock-in
    }
    if (_companyCheckInTime == null || _companyCheckInTime!.isEmpty) {
      return false; // Cannot determine lateness if no official time is set
    }
    try {
      final parts = _companyCheckInTime!.split(':');
      final int officialHour = int.parse(parts[0]);
      final int officialMinute = int.parse(parts[1]);

      final officialTimeToday = DateTime(punchTime.year, punchTime.month, punchTime.day, officialHour, officialMinute);
      
      // Allow a small grace period, e.g., 5 minutes
      return punchTime.isAfter(officialTimeToday.add(const Duration(minutes: 5)));
    } catch (e) {
      debugPrint('Error parsing company check-in time for lateness check: $e');
      return false;
    }
  }

  /// Handles the overall clock-in/out or break-in/out process.
  /// First checks if a punch has already been made for the day, then initiates face scan.
  Future<void> _handleClockInOut() async {
    debugPrint("Handling clock in/out process.");
    // Show a dialog if location is still loading
    if (_isLocationLoading || _currentPosition == null) {
      debugPrint("Location not ready. _isLocationLoading: $_isLocationLoading, _currentPosition: $_currentPosition");
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Location Not Ready'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.location_off, color: Colors.orange, size: 40),
              SizedBox(height: 10),
              Text(
                'We are still fetching your current location. Please wait a moment and try again.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return; // Exit the function if location is not ready
  }

    String type = widget.punchType;
    // Check if the user has already performed this type of punch today
    if (await _hasClocked(type: type)) {
      await _showResultDialog(false,
        "You have already clocked ${widget.scanType == 'attendance' ? (type == 'in' ? 'in' : 'out') : (type == 'in' ? 'break in' : 'break out')} today.",
        accuracy: 0.0 // No accuracy to show for already clocked
      );
      return;
    }

    // --- Start: Location Check Logic ---
    debugPrint("Checking company location details: Lat=$_companyLat, Lng=$_companyLng, Radius=$_companyRadius");
    if (_companyLat == null || _companyLng == null || _companyRadius == null) {
      _showMessage("Company location not set or could not be retrieved. Please contact admin.", Colors.red);
      debugPrint("Company location details are incomplete.");
      return;
    }

    final double distance = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _companyLat!,
      _companyLng!,
    );
    debugPrint("Distance to company location: $distance meters (Allowed: $_companyRadius meters)");

    if (distance > _companyRadius!) {
      _showMessage("You are outside the allowed company location range (${distance.toStringAsFixed(2)} meters away).", Colors.red);
      debugPrint("User is outside company geofence.");
      return;
    }
    // --- End: Location Check Logic ---

    // If all checks pass, show face scan UI and initialize camera
    if (mounted) { // Check mounted before setState
      setState(() => _showFaceScan = true);
    }
    debugPrint("Showing face scan UI.");
    await _initCameraForFaceScan();
    // Brightness is now set inside _initCameraForFaceScan
  }

  /// Executed after a successful face scan. Saves punch data and sends notifications.
  Future<void> _onFaceScanPressed() async {
    debugPrint("Face scan button pressed. Initiating verification.");
    final isFaceVerified = await _verifyFaceWithCamera();
    if (isFaceVerified) {
      final now = DateTime.now();
      String type = widget.punchType; // 'in' or 'out'
      final user = FirebaseAuth.instance.currentUser;
      final userId = user!.uid;

      // Fetch employee name & companyId from Firestore
      final employeeDoc = await FirebaseFirestore.instance.collection('Employee').doc(userId).get();
      final employeeName = employeeDoc.data()?['fullName'] ?? 'Unknown'; // Changed to fetch 'fullName'
      final companyId = employeeDoc.data()?['companyId'];
      debugPrint("Employee Name: $employeeName, Company ID: $companyId");

      // Check for lateness during clock-in
      String latenessMessage = '';
      bool isLatePunch = false;
      if (widget.scanType == 'attendance' && type == 'in') {
        isLatePunch = _isLate(now); // Use the new _isLate helper
        if (isLatePunch) {
          final String? checkInTimeStr = _companyCheckInTime;
          if (checkInTimeStr != null && checkInTimeStr.isNotEmpty) {
            final parts = checkInTimeStr.split(':');
            if (parts.length == 2) {
              final int checkInHour = int.parse(parts[0]);
              final int checkInMinute = int.parse(parts[1]);
              final officialStartTime = DateTime(now.year, now.month, now.day, checkInHour, checkInMinute);
              final lateMinutes = now.difference(officialStartTime).inMinutes;
              latenessMessage = ' (late by $lateMinutes minutes)';
            }
          }
        }
      }

      String? remarkInput; // Variable to hold the remark from the dialog

      // Show remark dialog if it's a late attendance clock-in
      if (isLatePunch) {
        remarkInput = await _showRemarkDialog();
        if (remarkInput == null) { // If user cancels the remark dialog, cancel the punch
          _showMessage("Punch cancelled. Remark not provided.", Colors.red);
          _cameraController?.dispose();
          if (mounted) {
            setState(() {
              _showFaceScan = false;
              _isCameraInitialized = false;
              _cameraController = null;
              _isProcessing = false;
            });
          }
          await _resetScreenBrightness();
          return;
        }
      }

      // Save the attendance/break record to Firestore
      await _saveAttendance(
        type: type,
        time: now,
        location: _currentAddress ?? 'Unknown location',
        remark: remarkInput, // Pass the remark if available
      );

      // Save real-time punch log to PunchLogs collection for company-specific records
      if (companyId != null) {
        final punchAction = widget.scanType == 'attendance'
            ? (type == 'in' ? 'clocked in' : 'clocked out')
            : (type == 'in' ? 'started break' : 'ended break');

        await FirebaseFirestore.instance
            .collection('PunchLogs')
            .doc(companyId)
            .collection('Records')
            .add({
              'employeeId': userId,
              'employeeName': employeeName, // Use the fetched employeeName
              'timestamp': Timestamp.now(),
              'type': punchAction, // Use punchAction for clarity
              'location': _currentAddress ?? 'Unknown location',
              'latenessMessage': latenessMessage, // Store lateness message
              'remark': remarkInput, // Store the remark in punch logs as well
            });

        debugPrint("✅ Punch log saved to PunchLogs/$companyId/Records");

        // Send push notification to all admins associated with this company
        final adminSnapshot = await FirebaseFirestore.instance
            .collection('users') // Admins are in 'users' collection
            .where('role', isEqualTo: 'admin')
            .where('companyId', isEqualTo: companyId)
            .get();
        debugPrint("Found ${adminSnapshot.docs.length} admins for company $companyId");

        // Construct notification title and body
        final notificationTitle = 'Employee Activity Alert';
        String notificationBody = '$employeeName has $punchAction from ${_currentAddress ?? 'an unknown location'}$latenessMessage.';
        if (remarkInput != null && remarkInput.isNotEmpty) {
          notificationBody += ' Remark: "$remarkInput"';
        }

        for (final adminDoc in adminSnapshot.docs) {
          final adminToken = adminDoc.data()['fcmToken'];
          if (adminToken != null && adminToken.isNotEmpty) {
            await PushNotificationService.sendNotification(
              deviceToken: adminToken,
              title: notificationTitle,
              message: notificationBody,
            );
            debugPrint("✅ Notification sent to admin: ${adminDoc.id}");
          } else {
            debugPrint("Admin ${adminDoc.id} has no FCM token.");
          }
        }
      } else {
        debugPrint("Company ID is null, cannot save punch log or send notifications.");
      }

      // Cleanup camera and update UI state
      _clockInTimer?.cancel();
      _cameraController?.dispose();
      if (mounted) { // Check mounted before setState
        setState(() {
          _showFaceScan = false;
          _isCameraInitialized = false;
          _cameraController = null;
          _isProcessing = false;
        });
      }
      await _checkTodayAttendance(); // Refresh attendance status after successful punch
      if (mounted) { // Ensure widget is still mounted before navigating
        Navigator.of(context).pop(); // Go back to the previous screen
      }
    }
    await _resetScreenBrightness(); // Reset brightness after face scan attempt (success or failure)
    debugPrint("Face scan process completed.");
  }

  /// Displays a dialog for the employee to enter a remark for late clock-in.
  /// Returns the remark string or null if cancelled.
  Future<String?> _showRemarkDialog() async {
    _remarkController.clear(); // Clear previous input
    return await showDialog<String>(
      context: context,
      barrierDismissible: false, // User must provide remark or cancel
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Late Clock-in Remark'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('You are clocking in late. Please provide a brief reason:', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 15),
            TextField(
              controller: _remarkController,
              decoration: InputDecoration(
                hintText: 'e.g., Traffic jam, personal emergency',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              maxLines: 3,
              minLines: 1,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(null); // Return null if cancelled
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(_remarkController.text.trim()); // Return the remark
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit Remark'),
          ),
        ],
      ),
    );
  }

  /// Custom message box function instead of alert()
  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If _showFaceScan is true, display the camera preview for face scanning
    if (_showFaceScan) {
      return _buildFaceVerificationView();
    }

    // --- Original GPS UI (with Google Map) ---
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Transparent app bar
        elevation: 0, // No shadow
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context), // Back button
        ),
      ),
      extendBodyBehindAppBar: true, // App bar extends over the body
      body: Stack(
        children: [
          // Google Map Widget - displays the map with current location marker
          GoogleMap(
            // Use current position if available, otherwise a default Kuala Terengganu location
            initialCameraPosition: CameraPosition(
              target: _currentPosition ?? (_companyLat != null && _companyLng != null ? LatLng(_companyLat!, _companyLng!) : const LatLng(3.1390, 101.6869)),
              zoom: 15,
            ),
            onMapCreated: (controller) {
              _mapController = controller; // Get map controller
              _zoomMapToFitLocations(); // Zoom to fit locations once map is created
            },
            markers: _currentPosition != null
                ? { // Show a marker at the current location
                    Marker(
                      markerId: const MarkerId('currentLocation'),
                      position: _currentPosition!,
                      infoWindow: const InfoWindow(title: 'Your Location'),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), // Blue marker for current location
                    ),
                  }
                : {}, // No markers if position is null
            circles: _circles, // Display the company location circle
          ),
          Align( // Position the info box and button at the bottom
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min, // Column takes minimum space
              children: [
                const SizedBox(height: 16), // Spacing
                // Debugging Text: Display fetched company location
                if (_companyLat != null && _companyLng != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Company Lat: ${_companyLat!.toStringAsFixed(4)}, Lng: ${_companyLng!.toStringAsFixed(4)}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16), // More spacing
                Container( // Info box for location and punch status
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text( // Location label
                        widget.scanType == 'attendance' ? 'Location' : 'Break Location',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 5),
                      Text(_currentAddress ?? 'Fetching address...', style: const TextStyle(fontSize: 14, color: Colors.grey)), // Display fetched address
                      const SizedBox(height: 20),
                      Row( // Punch in/out times
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text( // Punch In label
                                widget.scanType == 'attendance' ? 'Clock In' : 'Break In',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 5),
                              Text( // Display clock-in time
                                _clockInDateTime != null
                                    ? "${(_clockInDateTime!.hour % 12 == 0 ? 12 : _clockInDateTime!.hour % 12).toString().padLeft(2, '0')}:${_clockInDateTime!.minute.toString().padLeft(2, '0')} ${_clockInDateTime!.hour >= 12 ? 'PM' : 'AM'}"
                                    : '-- : --',
                                style: const TextStyle(fontSize: 16, color: Colors.green),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text( // Punch Out label
                                widget.scanType == 'attendance' ? 'Clock Out' : 'Break Out',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 5),
                              Text(_punchOutTime ?? '-- : --', style: const TextStyle(fontSize: 16, color: Colors.red)), // Display punch-out time
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton( // Main action button (Clock In/Out, Break In/Out)
                        onPressed: (_modelsLoaded && !_isProcessing && !_isLocationLoading) ? _handleClockInOut : null, // Enabled only when model is loaded, not processing, and location is not loading
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: _isProcessing || _isLocationLoading
                            ? const CircularProgressIndicator(color: Colors.white) // Show spinner if processing or location is loading
                            : Text( // Display button text
                                widget.scanType == 'attendance'
                                    ? _buttonText
                                    : (widget.punchType == 'in' ? "Break In" : "Break Out"),
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                      if (!_modelsLoaded) // Message if face model is still loading
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text("Loading face models...", style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the face verification camera view.
  Widget _buildFaceVerificationView() {
    // Show loading indicator if camera controller is null or not initialized
    if (!_isCameraInitialized) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () {
              _cameraController?.dispose();
              if (mounted) { // Check mounted before setState
                setState(() {
                  _showFaceScan = false;
                  _isCameraInitialized = false;
                  _cameraController = null;
                });
              }
              _resetScreenBrightness();
            },
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                _isProcessing ? 'Initializing camera...' : 'Preparing for face scan...',
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    // Otherwise, show the camera preview
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            // When going back from face scan, dispose camera and hide face scan UI
            _cameraController?.dispose();
            if (mounted) { // Check mounted before setState
              setState(() {
                _showFaceScan = false;
                _isCameraInitialized = false;
                _cameraController = null;
              });
            }
            _resetScreenBrightness(); // Reset brightness when user navigates back
          },
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: ClipOval(
              child: SizedBox(
                width: _circleSize,
                height: _circleSize,
                child: FittedBox( // Use FittedBox to ensure the camera feed fills the circle without stretching
                  fit: BoxFit.cover, // This makes the camera fill the box, cropping if necessary
                  child: SizedBox( // This SizedBox provides the original aspect ratio to FittedBox
                    width: _cameraController!.value.previewSize!.height,
                    height: _cameraController!.value.previewSize!.width,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),
            ),
          ),
          // Pass the border color and width to the overlay painter
          _WhiteOverlayWithHole(
            diameter: _circleSize,
            borderColor: Colors.green.shade400, // Green border color
            borderWidth: 4.0, // 4-pixel border
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.1, // Adjust top position dynamically
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min, // Use min to wrap content
              children: [
                Text(
                  "Position your face in the circle.", // Simplified main instruction
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade400, // Themed color
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8), // Spacing
                Text(
                  "Ensure good lighting for best results.", // Simplified secondary instruction
                  style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.1, // Adjust bottom position dynamically
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min, // Use min to wrap content
              children: [
                ElevatedButton( // Changed from ElevatedButton.icon to ElevatedButton
                  onPressed: _isProcessing ? null : _onFaceScanPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600, // Themed color
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text(_isProcessing ? "Verifying..." : "Verify Face"), // Text only
                ),
                if (_isProcessing) Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: CircularProgressIndicator(color: Colors.orange.shade400), // Themed color
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter to make white screen with circular hole (Copied from face_registration.dart)
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
