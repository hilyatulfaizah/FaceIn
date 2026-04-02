import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';

import 'login.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUp> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  // Define the purple color for buttons (matching company_profile.dart)
  final Color appPurple = const Color.fromARGB(255, 143, 83, 167);


  @override
  void dispose() {
    _nameController.dispose();
    _companyNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  Future<void> _signUpWithEmail() async {
    final name = _nameController.text.trim();
    final companyName = _companyNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty || companyName.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showMessage("Please fill all fields.");
      return;
    }

    if (password.length < 6) {
      _showMessage("Password must be at least 6 characters.");
      return;
    }

    if (password != confirmPassword) {
      _showMessage("Passwords do not match.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        // Generate a unique companyId
        String companyId = _firestore.collection('Companies').doc().id;

        // Create the company document
        await _firestore.collection('Companies').doc(companyId).set({
          'name': companyName,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Create the Admin document linked to this company in the 'users' collection
        await _firestore.collection('users').doc(userCredential.user!.uid).set({
          'name': name,
          'email': email,
          'role': 'admin', // Changed to 'admin' to match login.dart's check
          'companyId': companyId,
          'createdAt': FieldValue.serverTimestamp(),
        });

        _showMessage("Sign Up Successful! Please log in.");
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'weak-password') {
        message = 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        message = 'The account already exists for that email.';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is not valid.';
      } else {
        message = 'An error occurred: ${e.message}';
      }
      _showMessage(message);
    } catch (e) {
      _showMessage('An unexpected error occurred: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    // Show modal loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();

      // Force account selection by signing out first.
      // This ensures the Google account picker is always shown.
      await googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading dialog
        return; // User cancelled the sign-in
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        // Check if the admin already exists in the 'users' collection
        final userDoc = await _firestore.collection('users').doc(user.uid).get();

        if (!userDoc.exists) {
          // If a new Google user, prompt for company name and create company
          if (!mounted) return;
          Navigator.of(context).pop(); // Close loading dialog before showing company name dialog

          // Show a dialog to get the company name
          String? companyName = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              final TextEditingController tempCompanyNameController = TextEditingController();
              return AlertDialog(
                title: const Text('Enter Company Name'),
                content: TextField(
                  controller: tempCompanyNameController,
                  decoration: const InputDecoration(hintText: "Company Name"),
                ),
                actions: <Widget>[
                  TextButton(
                    child: const Text('Submit'),
                    onPressed: () {
                      Navigator.of(context).pop(tempCompanyNameController.text.trim());
                    },
                  ),
                ],
              );
            },
          );

          if (companyName == null || companyName.isEmpty) {
            _showMessage("Company name is required for Admin sign-up. Please try again.");
            await user.delete(); // Delete the Firebase user if company name is not provided
            await googleSignIn.signOut(); // Sign out Google again
            return;
          }

          // Generate a unique companyId
          String companyId = _firestore.collection('Companies').doc().id;

          // Create the company document
          await _firestore.collection('Companies').doc(companyId).set({
            'name': companyName,
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Create the Admin document linked to this company in the 'users' collection
          await _firestore.collection('users').doc(user.uid).set({
            'name': user.displayName ?? 'Google User',
            'email': user.email,
            'role': 'admin', // Changed to 'admin' to match login.dart's check
            'companyId': companyId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading dialog
        _showMessage("Sign Up Successful with Google! Please log in.");
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      } else {
        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading dialog
        _showMessage("Google Sign-In failed. Please try again.");
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      _showMessage('Google Sign-Up Error: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      _showMessage('An unexpected error occurred during Google Sign-Up: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Create Admin Account",
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  labelText: "Full Name",
                  labelStyle: const TextStyle(color: Colors.black54),
                  prefixIcon: const Icon(Icons.person, color: Colors.black54),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: appPurple, width: 2), // Changed to appPurple
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _companyNameController,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  labelText: "Company Name",
                  labelStyle: const TextStyle(color: Colors.black54),
                  prefixIcon: const Icon(Icons.business, color: Colors.black54),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: appPurple, width: 2), // Changed to appPurple
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  labelText: "Email",
                  labelStyle: const TextStyle(color: Colors.black54),
                  prefixIcon: const Icon(Icons.email, color: Colors.black54),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: appPurple, width: 2), // Changed to appPurple
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  labelText: "Password",
                  labelStyle: const TextStyle(color: Colors.black54),
                  prefixIcon: const Icon(Icons.lock, color: Colors.black54),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.black54,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: appPurple, width: 2), // Changed to appPurple
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _confirmPasswordController,
                obscureText: !_isConfirmPasswordVisible,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  labelText: "Confirm Password",
                  labelStyle: const TextStyle(color: Colors.black54),
                  prefixIcon: const Icon(Icons.lock, color: Colors.black54),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.black54,
                    ),
                    onPressed: () {
                      setState(() {
                        _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                      });
                    },
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: appPurple, width: 2), // Changed to appPurple
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signUpWithEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appPurple, // Changed to appPurple
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 5,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Sign Up",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: Icon(Icons.login,
                    color: appPurple), // Changed to appPurple
                onPressed: _isLoading ? null : _signInWithGoogle,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  side: BorderSide(
                      color: appPurple), // Changed to appPurple
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: Text(
                  "Sign up with Google",
                  style: TextStyle(color: appPurple)), // Changed to appPurple
              ),
            ],
          ),
        ),
      ),
    );
  }
}
