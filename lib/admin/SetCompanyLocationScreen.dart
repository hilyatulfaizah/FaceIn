import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class SetCompanyLocationScreen extends StatefulWidget {
  final String companyId;

  const SetCompanyLocationScreen({
    super.key,
    required this.companyId,
  });

  @override
  State<SetCompanyLocationScreen> createState() =>
      _SetCompanyLocationScreenState();
}

class _SetCompanyLocationScreenState extends State<SetCompanyLocationScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _radiusController = TextEditingController();
  final TextEditingController _checkInTimeController = TextEditingController();
  final TextEditingController _checkOutTimeController = TextEditingController();

  String _statusMessage = '';
  bool _isLoading = false;
  final Color appPurple = const Color.fromARGB(255, 143, 83, 167);

  @override
  void initState() {
    super.initState();
    _loadCompanySettings(); // Load saved settings from Firestore
  }

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    _checkInTimeController.dispose();
    _checkOutTimeController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanySettings() async {
    try {
      DocumentSnapshot snapshot = await _firestore
          .collection('CompanySettings')
          .doc(widget.companyId)
          .get();

      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        setState(() {
          _latitudeController.text = data['latitude']?.toString() ?? '';
          _longitudeController.text = data['longitude']?.toString() ?? '';
          _radiusController.text = data['radius']?.toString() ?? '';
          _checkInTimeController.text = data['checkInTime'] ?? '';
          _checkOutTimeController.text = data['checkOutTime'] ?? '';
        });
      }
    } catch (e) {
      print('Error loading settings: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Fetching current location...';
    });
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _statusMessage = 'Location permissions are denied.';
        setState(() => _isLoading = false);
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _statusMessage =
            'Location permissions are permanently denied. Please enable them in app settings.';
        setState(() => _isLoading = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _latitudeController.text = position.latitude.toString();
        _longitudeController.text = position.longitude.toString();
        _statusMessage = 'Location fetched successfully!';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error fetching location: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveCompanyLocation() async {
    if (_latitudeController.text.isEmpty ||
        _longitudeController.text.isEmpty ||
        _radiusController.text.isEmpty ||
        _checkInTimeController.text.isEmpty ||
        _checkOutTimeController.text.isEmpty) {
      setState(() {
        _statusMessage = 'Please fill all fields.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Saving company settings...';
    });

    try {
      final double lat = double.parse(_latitudeController.text);
      final double lng = double.parse(_longitudeController.text);
      final double radius = double.parse(_radiusController.text);
      final String checkInTime = _checkInTimeController.text;
      final String checkOutTime = _checkOutTimeController.text;

      await _firestore.collection('CompanySettings').doc(widget.companyId).set({
        'latitude': lat,
        'longitude': lng,
        'radius': radius,
        'checkInTime': checkInTime,
        'checkOutTime': checkOutTime,
      }, SetOptions(merge: true));

      setState(() {
        _statusMessage = 'Company settings updated successfully!';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error saving settings: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _selectTime(
      BuildContext context, TextEditingController controller) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      final formattedTime = DateFormat('HH:mm').format(dt);
      setState(() {
        controller.text = formattedTime;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Set Company Location & Hours',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: appPurple,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Define the central location and radius for your company\'s attendance tracking. Employees must be within this area to clock in/out.',
              style: TextStyle(fontSize: 15, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _latitudeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Latitude',
                hintText: 'e.g., 3.14159',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(Icons.location_on),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _longitudeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Longitude',
                hintText: 'e.g., 101.6841',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(Icons.location_on),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _getCurrentLocation,
              icon: _isLoading && _statusMessage.contains('Fetching')
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.my_location, color: Colors.white),
              label: const Text(
                'Get Current Location',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _radiusController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Radius (meters)',
                hintText: 'e.g., 50',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(Icons.circle),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Set Standard Clock-in and Clock-out Times',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _checkInTimeController,
              readOnly: true,
              onTap: () => _selectTime(context, _checkInTimeController),
              decoration: InputDecoration(
                labelText: 'Standard Clock-in Time',
                hintText: 'Tap to select',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(Icons.schedule),
                suffixIcon: const Icon(Icons.access_time),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _checkOutTimeController,
              readOnly: true,
              onTap: () => _selectTime(context, _checkOutTimeController),
              decoration: InputDecoration(
                labelText: 'Standard Clock-out Time',
                hintText: 'Tap to select',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(Icons.schedule),
                suffixIcon: const Icon(Icons.access_time),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveCompanyLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: appPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              child: _isLoading && _statusMessage.contains('Saving')
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(height: 16),
            if (_statusMessage.isNotEmpty)
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _statusMessage.contains('Error')
                      ? Colors.red
                      : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
