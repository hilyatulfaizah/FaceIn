import 'package:face_in/login.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore

// Assuming these imports are available in your project structure
import 'package:face_in/admin/homepage_admin.dart'; // Path to admin homepage
import 'package:face_in/employee/homepage_employee.dart'; // Path to employee homepage

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmNewPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isCurrentPasswordVisible = false;
  bool _isNewPasswordVisible = false;
  bool _isConfirmNewPasswordVisible = false;

  final Color appPurple = const Color.fromARGB(255, 143, 83, 167);

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;

    try {
      if (user == null || user.email == null) {
        _showSnackBar('User not logged in or email not available.');
        return;
      }

      // Reauthenticate user before changing password
      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentPasswordController.text,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(_newPasswordController.text);

      _showSnackBar('Password changed successfully!');

      // Determine user role and navigate
      await _navigateToAppropriateHomepage(user.uid, user.email!);

    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'wrong-password') {
        message = 'Invalid current password.';
      } else if (e.code == 'requires-recent-login') {
        message = 'Please log in again to update your password.';
      } else if (e.code == 'weak-password') {
        message = 'The new password is too weak.';
      } else {
        message = 'Error changing password: ${e.message}';
      }
      _showSnackBar(message);
    } catch (e) {
      _showSnackBar('An unexpected error occurred: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _navigateToAppropriateHomepage(String uid, String email) async {
    String? role;
    String? name;
    String? companyId; // Needed for Admin homepage

    // 1. Check if the user is an Admin (in 'users' collection)
    final adminDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (adminDoc.exists && adminDoc.data()?['role'] == 'admin') {
      role = 'admin';
      name = adminDoc.data()?['displayName'] ?? adminDoc.data()?['name'] ?? 'Admin';
      companyId = adminDoc.data()?['companyId'];
    } else {
      // 2. Check if the user is an Employee (in 'Employee' collection)
      final employeeSnapshot = await FirebaseFirestore.instance
          .collection('Employee')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (employeeSnapshot.docs.isNotEmpty) {
        final employeeData = employeeSnapshot.docs.first.data();
        role = 'employee';
        name = employeeData['name'] ?? 'Employee';
      }
    }

    if (!mounted) return;

    if (role == 'admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomepageAdmin(name: name ?? 'Admin', companyId: companyId ?? ''),
        ),
      );
    } else if (role == 'employee') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomepageEmployee(name: name ?? 'Employee'),
        ),
      );
    } else {
      // Fallback if role cannot be determined, perhaps go back to login
      _showSnackBar('Could not determine user role. Please log in again.');
      // You might want to sign out here and navigate to login
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()), // Assuming LoginPage is accessible
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: Color.fromARGB(255, 143, 83, 167),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        titleTextStyle: const TextStyle(
            color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current Password',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _currentPasswordController,
                obscureText: !_isCurrentPasswordVisible,
                decoration: InputDecoration(
                  hintText: 'Enter your current password',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isCurrentPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _isCurrentPasswordVisible = !_isCurrentPasswordVisible;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your current password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'New Password',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _newPasswordController,
                obscureText: !_isNewPasswordVisible,
                decoration: InputDecoration(
                  hintText: 'Enter your new password',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isNewPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _isNewPasswordVisible = !_isNewPasswordVisible;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a new password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters long';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'Confirm New Password',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _confirmNewPasswordController,
                obscureText: !_isConfirmNewPasswordVisible,
                decoration: InputDecoration(
                  hintText: 'Confirm your new password',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmNewPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _isConfirmNewPasswordVisible = !_isConfirmNewPasswordVisible;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your new password';
                  }
                  if (value != _newPasswordController.text) {
                    return 'Passwords do not match';
                  }
                  // Added validation: new password cannot be the same as current password
                  if (value == _currentPasswordController.text) {
                    return 'New password cannot be the same as current password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.0),
                child: Center(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _changePassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appPurple,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Change Password',
                            style: TextStyle(color: Colors.white),
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
}