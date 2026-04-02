import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BreakApplyPage extends StatefulWidget {
  const BreakApplyPage({super.key});

  @override
  State<BreakApplyPage> createState() => _BreakApplyPageState();
}

class _BreakApplyPageState extends State<BreakApplyPage> {
  final _reasonController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = false; // To manage loading state for submission

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  /// Function to show a date picker and update the selected date.
  Future<void> _selectDate(BuildContext context, {required bool isStartDate}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? (_startDate ?? DateTime.now()) : (_endDate ?? _startDate ?? DateTime.now()),
      firstDate: DateTime.now(), // Cannot select dates in the past
      lastDate: DateTime(DateTime.now().year + 5), // Allow selecting up to 5 years in the future
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          // If start date is set after end date, clear end date or adjust it
          if (_endDate != null && _startDate!.isAfter(_endDate!)) {
            _endDate = null; // Or set _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          // If end date is set before start date, clear start date or adjust it
          if (_startDate != null && _endDate!.isBefore(_startDate!)) {
            _startDate = null; // Or set _startDate = _endDate;
          }
        }
      });
    }
  }

  /// Submits the leave request to Firestore.
  Future<void> _submitLeaveRequest() async {
    if (_startDate == null || _endDate == null || _reasonController.text.trim().isEmpty) {
      _showMessage('Please fill all fields (start date, end date, and reason).', isError: true);
      return;
    }

    if (_endDate!.isBefore(_startDate!)) {
      _showMessage('End date cannot be before start date.', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showMessage('User not logged in. Please log in again.', isError: true);
        return;
      }

      await FirebaseFirestore.instance.collection('Leaves').add({
        'uid': user.uid,
        'startDate': Timestamp.fromDate(_startDate!),
        'endDate': Timestamp.fromDate(_endDate!),
        'reason': _reasonController.text.trim(),
        'status': 'pending', // Initial status
        'timestamp': FieldValue.serverTimestamp(), // Server timestamp for when it was submitted
      });

      _showMessage('Leave request submitted successfully!');
      // Clear form fields after successful submission
      _reasonController.clear();
      setState(() {
        _startDate = null;
        _endDate = null;
      });

    } on FirebaseException catch (e) {
      _showMessage('Failed to submit leave request: ${e.message}', isError: true);
    } catch (e) {
      _showMessage('An unexpected error occurred: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Displays a message to the user using a SnackBar.
  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apply for Leave/Holiday'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fill out the form below to apply for a leave.',
              style: TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 20),

            // Start Date Picker
            ListTile(
              title: Text(
                _startDate == null
                    ? 'Select Start Date'
                    : 'Start Date: ${DateFormat('yyyy-MM-dd').format(_startDate!)}',
                style: TextStyle(fontSize: 16, color: _startDate == null ? Colors.grey[700] : Colors.black),
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context, isStartDate: true),
            ),
            const Divider(),

            // End Date Picker
            ListTile(
              title: Text(
                _endDate == null
                    ? 'Select End Date'
                    : 'End Date: ${DateFormat('yyyy-MM-dd').format(_endDate!)}',
                style: TextStyle(fontSize: 16, color: _endDate == null ? Colors.grey[700] : Colors.black),
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context, isStartDate: false),
            ),
            const Divider(),

            const SizedBox(height: 20),

            // Reason Text Field
            TextField(
              controller: _reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason for Leave',
                hintText: 'e.g., Annual leave, Sick leave, Personal matter',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 30),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitLeaveRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Submit Leave Request',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // Placeholder for holiday information (optional)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upcoming Holidays',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple.shade800),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No upcoming holidays listed at the moment. Please check with HR for official holiday calendar.',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                    // You could fetch and display actual holidays here
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
