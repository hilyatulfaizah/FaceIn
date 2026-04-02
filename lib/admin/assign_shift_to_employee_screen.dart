import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ManageCompanyShiftsScreen extends StatefulWidget {
  final String companyId;

  const ManageCompanyShiftsScreen({super.key, required this.companyId});

  @override
  State<ManageCompanyShiftsScreen> createState() => _ManageCompanyShiftsScreenState();
}

class _ManageCompanyShiftsScreenState extends State<ManageCompanyShiftsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _shifts = [];
  bool _isLoading = true;
  String _statusMessage = '';

  // List of predefined time options (e.g., every 30 minutes)
  final List<String> _timeOptions = [];

  @override
  void initState() {
    super.initState();
    _generateTimeOptions();
    _loadCompanyShifts();
  }

  void _generateTimeOptions() {
    for (int h = 0; h < 24; h++) {
      for (int m = 0; m < 60; m += 30) {
        _timeOptions.add(
          '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
        );
      }
    }
  }

  Future<void> _loadCompanyShifts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading shifts...';
    });
    try {
      final shiftsSnapshot = await _firestore
          .collection('companies')
          .doc(widget.companyId)
          .collection('shifts')
          .orderBy('name') // Order shifts by name for better display
          .get();

      final List<Map<String, dynamic>> loadedShifts = [];
      for (var doc in shiftsSnapshot.docs) {
        loadedShifts.add({
          'id': doc.id,
          'name': doc.data()['name'],
          'checkInTime': doc.data()['checkInTime'],
          'checkOutTime': doc.data()['checkOutTime'],
        });
      }

      if (mounted) {
        setState(() {
          _shifts = loadedShifts;
          _isLoading = false;
          _statusMessage = 'Shifts loaded.';
        });
      }
    } catch (e) {
      debugPrint("Error loading shifts: $e");
      if (mounted) {
        setState(() {
          _statusMessage = 'Error loading shifts: $e';
          _isLoading = false;
        });
      }
      _showMessage('Error loading shifts: $e', Colors.red);
    }
  }

  Future<void> _showShiftDialog({Map<String, dynamic>? shiftToEdit}) async {
    final TextEditingController shiftNameController = TextEditingController(text: shiftToEdit?['name']);
    String? selectedCheckInTime = shiftToEdit?['checkInTime'];
    String? selectedCheckOutTime = shiftToEdit?['checkOutTime'];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(shiftToEdit == null ? 'Add New Shift' : 'Edit Shift'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: shiftNameController,
                      decoration: const InputDecoration(labelText: 'Shift Name'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedCheckInTime,
                      decoration: InputDecoration(
                        labelText: 'Check-in Time',
                        hintText: 'Select time',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.access_time),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      items: _timeOptions.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedCheckInTime = newValue;
                        });
                      },
                      validator: (value) => value == null || value.isEmpty ? 'Please select a check-in time' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedCheckOutTime,
                      decoration: InputDecoration(
                        labelText: 'Check-out Time',
                        hintText: 'Select time',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.access_time_filled),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      items: _timeOptions.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedCheckOutTime = newValue;
                        });
                      },
                      validator: (value) => value == null || value.isEmpty ? 'Please select a check-out time' : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (shiftNameController.text.isEmpty ||
                        selectedCheckInTime == null ||
                        selectedCheckOutTime == null) {
                      _showMessage('Please fill all shift fields.', Colors.orange);
                      return;
                    }
                    if (shiftToEdit == null) {
                      await _addShift(
                        shiftNameController.text,
                        selectedCheckInTime!,
                        selectedCheckOutTime!,
                      );
                    } else {
                      await _updateShift(
                        shiftToEdit['id'],
                        shiftNameController.text,
                        selectedCheckInTime!,
                        selectedCheckOutTime!,
                      );
                    }
                    if (mounted) Navigator.pop(context); // Close dialog
                  },
                  child: Text(shiftToEdit == null ? 'Add' : 'Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addShift(String name, String checkIn, String checkOut) async {
    try {
      setState(() => _isLoading = true);
      final docRef = await _firestore
          .collection('companies')
          .doc(widget.companyId)
          .collection('shifts')
          .add({
        'name': name,
        'checkInTime': checkIn,
        'checkOutTime': checkOut,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _shifts.add({
            'id': docRef.id,
            'name': name,
            'checkInTime': checkIn,
            'checkOutTime': checkOut,
          });
          _isLoading = false;
        });
      }
      _showMessage('Shift added successfully!', Colors.green);
      _loadCompanyShifts(); // Reload to reflect changes
    } catch (e) {
      debugPrint("Error adding shift: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _showMessage('Error adding shift: $e', Colors.red);
    }
  }

  Future<void> _updateShift(String id, String name, String checkIn, String checkOut) async {
    try {
      setState(() => _isLoading = true);
      await _firestore
          .collection('companies')
          .doc(widget.companyId)
          .collection('shifts')
          .doc(id)
          .update({
        'name': name,
        'checkInTime': checkIn,
        'checkOutTime': checkOut,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          final index = _shifts.indexWhere((shift) => shift['id'] == id);
          if (index != -1) {
            _shifts[index] = {
              'id': id,
              'name': name,
              'checkInTime': checkIn,
              'checkOutTime': checkOut,
            };
          }
          _isLoading = false;
        });
      }
      _showMessage('Shift updated successfully!', Colors.green);
      _loadCompanyShifts(); // Reload to reflect changes
    } catch (e) {
      debugPrint("Error updating shift: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _showMessage('Error updating shift: $e', Colors.red);
    }
  }

  Future<void> _deleteShift(String id) async {
    try {
      setState(() => _isLoading = true);
      await _firestore
          .collection('companies')
          .doc(widget.companyId)
          .collection('shifts')
          .doc(id)
          .delete();
      if (mounted) {
        setState(() {
          _shifts.removeWhere((shift) => shift['id'] == id);
          _isLoading = false;
        });
      }
      _showMessage('Shift deleted successfully!', Colors.green);
      _loadCompanyShifts(); // Reload to reflect changes
    } catch (e) {
      debugPrint("Error deleting shift: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _showMessage('Error deleting shift: $e', Colors.red);
    }
  }

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Company Shifts'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  Text(_statusMessage),
                ],
              ),
            )
          : _shifts.isEmpty
              ? const Center(child: Text('No shifts defined yet. Tap "+" to add your first shift.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _shifts.length,
                  itemBuilder: (context, index) {
                    final shift = _shifts[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        title: Text(
                          shift['name'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('Check-in: ${shift['checkInTime']} | Check-out: ${shift['checkOutTime']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _showShiftDialog(shiftToEdit: shift),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteShift(shift['id']),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showShiftDialog(),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
