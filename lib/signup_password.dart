// signup_password.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

import 'login.dart';

class SignUpPassword extends StatefulWidget {
  final String email;
  const SignUpPassword({super.key, required this.email});

  @override
  State<SignUpPassword> createState() => _SignUpPasswordState();
}

class _SignUpPasswordState extends State<SignUpPassword> {
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _isPasswordVisible = false;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  Future<void> _register() async {
    final password = _passwordController.text.trim();

    if (password.length < 6) {
      _showMessage("Password must be at least 6 characters");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: widget.email,
        password: password,
      );

      final user = userCredential.user;
      if (user != null) {
        final userId = user.uid;
        final companyId = _firestore.collection('companies').doc().id;

        await _firestore.collection('companies').doc(companyId).set({
          'adminId': userId,
          'companyName': '${widget.email.split('@')[0]} Company',
          'createdAt': FieldValue.serverTimestamp(),
        });

        await _firestore.collection('Admin').doc(userId).set({
          'email': widget.email,
          'companyId': companyId,
          'role': 'Admin', // Ensure 'Admin' is capitalized to match login
          'createdAt': FieldValue.serverTimestamp(),
        });

        _showMessage("Admin account and company registered successfully!");
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
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
      setState(() {
        _isLoading = false;
      });
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
              // Adjusted font size and color for consistency
              Text(
                "Create a Password",
                style: GoogleFonts.poppins(
                  fontSize: 24, // Adjusted from 28 to be closer to login page's main text size if any, or a reasonable header size.
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                style: const TextStyle(color: Colors.black), // Aligned with login.dart's text field input color
                decoration: InputDecoration(
                  hintText: "Enter your password",
                  hintStyle: const TextStyle(color: Colors.black54), // Aligned with login.dart's text field label/hint color
                  prefixIcon: const Icon(Icons.lock, color: Colors.black54),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
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
                    borderSide: const BorderSide(color: Color.fromARGB(255, 203, 118, 76), width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const CircularProgressIndicator(color: Color.fromARGB(255, 203, 118, 76))
                  : SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 203, 118, 76),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 5,
                        ),
                        child: const Text( // Using const Text for consistency with login page button text
                          "Sign Up",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16, // Adjusted to match 'Sign In' button in login.dart
                            fontWeight: FontWeight.bold, // Kept bold for prominence
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