import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RegisterEmployeePage extends StatefulWidget {
  final String companyId;

  const RegisterEmployeePage({
    super.key,
    required this.companyId,
  });

  @override
  State<RegisterEmployeePage> createState() => _RegisterEmployeePageState();
}

class _RegisterEmployeePageState extends State<RegisterEmployeePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController(); // New controller for confirm password
  final TextEditingController _jobController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = false;
  String _statusMessage = '';
  String? _nextWorkerId;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false; // New state for confirm password visibility

  @override
  void initState() {
    super.initState();
    _fetchNextWorkerId();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose(); // Dispose new controller
    _jobController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Fetches the next available worker ID to display from the counter document.
  Future<void> _fetchNextWorkerId() async {
    try {
      // Read the counter from the dedicated document.
      DocumentSnapshot counterSnapshot = await _firestore
          .collection('companyCounters')
          .doc(widget.companyId)
          .get();

      String nextId;
      if (!counterSnapshot.exists) {
        // If the counter doesn't exist, start from 001.
        nextId = '001';
      } else {
        // Get the current counter value and format it.
        final data = counterSnapshot.data() as Map<String, dynamic>;
        // The next worker ID should be the current number + 1, then formatted.
        int lastNumber = (data['nextWorkerId'] as int?) ?? 1; // Start from 1 if not exists
        nextId = (lastNumber).toString().padLeft(3, '0');
      }

      setState(() {
        _nextWorkerId = nextId;
      });
    } catch (e) {
      print('Error fetching worker ID from counter: $e');
      setState(() {
        _nextWorkerId = '001'; // Fallback
      });
    }
  }

  /// Handles the registration process, including atomically generating a unique ID.
  Future<void> _registerEmployee() async {
    // Clear any previous status message at the start of a new attempt
    setState(() {
      _statusMessage = '';
    });

    if (!_formKey.currentState!.validate()) {
      _showMessage('Please correct the errors in the form.', Colors.red);
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Registering employee...';
    });

    try {
      // 1. Create the user in Firebase Auth first.
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      String employeeUid = userCredential.user!.uid;

      // 2. Run a Firestore transaction to get a unique ID and save the data atomically.
      await _firestore.runTransaction((transaction) async {
        // Get the reference to the counter document.
        final counterRef = _firestore.collection('companyCounters').doc(widget.companyId);

        // Read the counter document within the transaction.
        final counterSnapshot = await transaction.get(counterRef);

        int currentId = 1; // Default starting ID if counter doesn't exist
        if (counterSnapshot.exists) {
          // Cast the data to a Map to use the [] operator.
          final data = counterSnapshot.data() as Map<String, dynamic>;
          currentId = (data['nextWorkerId'] as int?) ?? 1;
        }

        // Format the new worker ID.
        String newWorkerId = currentId.toString().padLeft(3, '0');
        
        // 3. Set the employee data in Firestore with the new worker ID.
        transaction.set(_firestore.collection('Employee').doc(employeeUid), {
          'fullName': _nameController.text.trim(), // Changed from 'name' to 'fullName'
          'email': _emailController.text.trim(),
          'username': newWorkerId, // Use the unique ID from the transaction
          'jobTitle': _jobController.text.trim(), // Changed from 'job' to 'jobTitle'
          'phone': _phoneController.text.trim(),
          'companyId': widget.companyId,
          'hasRegisteredFace': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 4. Increment the counter for the next registration.
        // If the counter document didn't exist, it will be created with `nextWorkerId: 2`.
        transaction.set(counterRef, {'nextWorkerId': currentId + 1}, SetOptions(merge: true));
      });

      // 5. Update the user's display name after the transaction is complete.
      await userCredential.user!.updateDisplayName(_nameController.text.trim());

      _showMessage('Employee registered successfully!', Colors.green);

      // Clear form and navigate back after a short delay to show the message.
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear(); // Clear confirm password field
      _jobController.clear();
      _phoneController.clear();
      // Re-fetch the next worker ID to update the displayed ID
      await _fetchNextWorkerId();

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'weak-password') {
        message = 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        message = 'An account already exists for that email.';
      } else {
        // This will catch the "No user currently signed in" error and any other Firebase Auth errors.
        message = 'Firebase Auth Error: ${e.message ?? "Unknown error"}';
      }
      _showMessage(message, Colors.red); // Show message for all FirebaseAuthExceptions
    } catch (e) {
      _showMessage('Error registering employee: ${e.toString()}', Colors.red); // Show message for general errors
    } finally {
      // Ensure isLoading is always set to false regardless of success or failure
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showMessage(String message, Color color) {
    // Ensure that _statusMessage is updated before showing the SnackBar
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
    }
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
        title: const Text('Register New Employee'),
        backgroundColor: const Color.fromARGB(255, 143, 83, 167),
        foregroundColor: Colors.black,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, // Added to make children stretch horizontally
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: _nextWorkerId == null
                  ? const Center(child: CircularProgressIndicator())
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Worker ID: ${_nextWorkerId ?? 'Loading...'}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Employee Name',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.person),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter employee name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.email),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter email';
                              }
                              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter password';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: !_isConfirmPasswordVisible,
                            decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please confirm your password';
                              }
                              if (value != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _jobController,
                            decoration: InputDecoration(
                              labelText: 'Job Title',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.work),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter job title';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Phone Number',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              prefixIcon: const Icon(Icons.phone),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_statusMessage.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10.0),
                              child: Text(
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
                            ),
                        ],
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _registerEmployee,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Register'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
