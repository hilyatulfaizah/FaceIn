// login.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'sign_up.dart';
import 'admin/homepage_admin.dart';
import 'employee/homepage_employee.dart';
import 'employee/face_registration.dart';
import 'package:face_in/push_notification_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _workerIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _selectedRole = 'Employee';
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  // Define the purple color for buttons (matching company_profile.dart)
  final Color appPurple = const Color.fromARGB(255, 143, 83, 167);


  @override
  void dispose() {
    _workerIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Displays an error or information dialog.
  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Login Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Handles employee login using Worker ID.
  Future<void> _loginWithWorkerID() async {
    final workerId = _workerIdController.text.trim();
    final password = _passwordController.text.trim();

    if (workerId.isEmpty || password.isEmpty) {
      _showErrorDialog('Please enter both Worker ID and password.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Query the Employee collection for the workerId to get email and companyId.
      final employeeSnapshot = await FirebaseFirestore.instance
          .collection('Employee')
          .where('username',
              isEqualTo: workerId) // Assuming 'username' stores workerId
          .limit(1)
          .get();

      if (employeeSnapshot.docs.isEmpty) {
        _showErrorDialog('Worker ID not found.');
        return;
      }

      final employeeDoc = employeeSnapshot.docs.first;
      final employeeData = employeeDoc.data();
      final employeeEmail = employeeData['email'] as String?;
      final employeeName = employeeData['name'] ?? 'Employee';
      final employeeCompanyId = employeeData['companyId'] as String?;
      final hasRegisteredFace = employeeData['hasRegisteredFace'] ?? false;

      if (employeeEmail == null ||
          employeeCompanyId == null ||
          employeeCompanyId.isEmpty) {
        _showErrorDialog('Employee data incomplete. Please contact support.');
        return;
      }

      // 2. Authenticate the employee using their email and password.
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: employeeEmail,
        password: password,
      );

      final currentUser = userCredential.user;
      if (currentUser == null) {
        _showErrorDialog('Failed to log in as employee.');
        return;
      }

      // 3. Update the employee's FCM token in their Firestore document.
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await FirebaseFirestore.instance
            .collection('Employee')
            .doc(employeeDoc.id)
            .set({'fcmToken': fcmToken}, SetOptions(merge: true));
        print("✅ Employee FCM token updated in Firestore.");
      }

      // 4. Fetch admin tokens for this specific company and send a notification.
      final adminSnapshot = await FirebaseFirestore.instance
          .collection('Admin') // Admin accounts are in 'users' collection
          .where('role', isEqualTo: 'Admin') // Check for 'role' field
          .where('companyId', isEqualTo: employeeCompanyId)
          .get();

      for (final adminDoc in adminSnapshot.docs) {
        final adminToken = adminDoc.data()['fcmToken'];
        if (adminToken != null && adminToken.isNotEmpty) {
          await PushNotificationService.sendNotification(
            deviceToken: adminToken,
            title: 'Employee Login Alert',
            message: "$employeeName has logged in as Employee.",
          );
          print("✅ Notification sent to admin: ${adminDoc.id}");
        }
      }

      // 5. Navigate based on face registration status.
      if (!mounted) return;
      if (!hasRegisteredFace) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                FaceRegistration(docId: employeeDoc.id, name: employeeName),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomepageEmployee(name: employeeName),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        message = 'Invalid worker ID or password.';
      } else {
        message = 'Login failed: ${e.message}';
      }
      _showErrorDialog(message);
    } catch (e) {
      _showErrorDialog("Login failed: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Handles admin login using email and password.
  Future<void> _loginWithEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showErrorDialog('Please enter both email and password.');
      return;
    }

    try {
      setState(() => _isLoading = true);

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) throw FirebaseAuthException(code: 'no-user');

      final userDoc = await FirebaseFirestore.instance
          .collection(
              'users') // This collection name is correct based on your Firestore data
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        _showErrorDialog("Admin record not found. Please sign up first.");
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final data = userDoc.data()!;
      final companyId = data['companyId'] ?? '';
      final name = data['displayName'] ?? 'Admin';
      // FIX: Changed check from 'isAdmin' to 'role'
      final isAdmin = (data['role'] == 'admin');

      if (!isAdmin) {
        _showErrorDialog("Account is not an admin account.");
        if (mounted) setState(() => _isLoading = false);
        await _auth.signOut();
        return;
      }

      // Update the admin's FCM token in their user document.
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'fcmToken': fcmToken}, SetOptions(merge: true));
        print("✅ Admin FCM token updated in Firestore.");
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomepageAdmin(
            name: name,
            companyId: companyId,
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        message = 'Invalid email or password.';
      } else {
        message = 'Login failed: ${e.message}';
      }
      _showErrorDialog(message);
    } catch (e) {
      _showErrorDialog("Login failed: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Handles admin login using Google Sign-In.
  Future<void> _loginWithGoogle() async {
    try {
      setState(() => _isLoading = true);

      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut(); // Force account picker
      // Removed googleSignIn.disconnect() as it's not strictly necessary and can sometimes cause issues.

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      final user = userCredential.user;
      if (user == null) throw FirebaseAuthException(code: 'no-user');

      final userDoc = await FirebaseFirestore.instance
          .collection(
              'users') // This collection name is correct based on your Firestore data
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        await user
            .delete(); // Delete the Firebase user created by Google Sign-In
        await googleSignIn.signOut(); // Sign out from Google

        _showErrorDialog(
          "This Google account is not registered as an Admin. Please sign up first.",
        );
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final data = userDoc.data()!;
      final companyId = data['companyId'] as String? ?? '';
      final name = data['displayName'] ?? 'Admin';
      // FIX: Changed check from 'isAdmin' to 'role'
      final isAdmin = (data['role'] == 'admin');

      if (!isAdmin) {
        _showErrorDialog("Account is not an admin account.");
        if (mounted) setState(() => _isLoading = false);
        await _auth.signOut();
        return;
      }

      // Update the admin's FCM token in their user document.
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'fcmToken': fcmToken}, SetOptions(merge: true));
        print("✅ Admin FCM token updated in Firestore.");
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomepageAdmin(
            name: name,
            companyId: companyId,
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'account-exists-with-different-credential') {
        message =
            'This email is already in use with a different sign-in method.';
      } else {
        message = "Google login failed: ${e.message}";
      }
      _showErrorDialog(message);
    } catch (e) {
      _showErrorDialog("Google login failed: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Builds a text field for input.
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25.0),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? !_isPasswordVisible : false,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _isPasswordVisible = !_isPasswordVisible),
                )
              : null,
          filled: true,
          fillColor: Colors.grey.shade200,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade500),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  /// Builds a role selection button.
  Widget _buildRoleButton(String role) {
    final isSelected = _selectedRole == role;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _selectedRole = role;
          _workerIdController.clear();
          _emailController.clear();
          _passwordController.clear();
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? appPurple // Changed to appPurple
            : Colors.grey.shade400,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(role, style: const TextStyle(color: Colors.white)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock,
                  size: 80, color: appPurple), // Changed to appPurple
              const SizedBox(height: 16),
              const Text(
                "Welcome back, you've been missed!",
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildRoleButton('Employee'),
                  const SizedBox(width: 16),
                  _buildRoleButton('Admin'),
                ],
              ),
              const SizedBox(height: 24),
              if (_selectedRole == 'Employee')
                _buildTextField(
                  controller: _workerIdController,
                  label: 'Worker ID',
                  icon: Icons.badge,
                )
              else
                _buildTextField(
                  controller: _emailController,
                  label: 'Email',
                  icon: Icons.email,
                ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock,
                isPassword: true,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : (_selectedRole == 'Employee'
                          ? _loginWithWorkerID
                          : _loginWithEmail),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appPurple, // Changed to appPurple
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Sign In',
                          style: TextStyle(color: Colors.white)),
                ),
              ),
              // This section will maintain its height regardless of the selected role
              Visibility(
                visible: _selectedRole == 'Admin',
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    const Text('Or sign in with Google'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: Icon(Icons.login,
                          color: appPurple), // Changed to appPurple
                      label: Text('Sign in with Google',
                          style: TextStyle(
                              color: appPurple)), // Changed to appPurple
                      onPressed: _isLoading ? null : _loginWithGoogle,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        side: BorderSide(
                            color: appPurple), // Changed to appPurple
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // This section will also maintain its height
              Visibility(
                visible: _selectedRole == 'Admin',
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account?",
                        style: TextStyle(color: Colors.black54)),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignUp()),
                      ),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                            color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}