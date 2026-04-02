// splash_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:face_in/onboarding_page.dart';
import 'package:face_in/main.dart'; // Import main.dart to access AuthChecker

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  _navigateToNextScreen() async {
    await Future.delayed(const Duration(seconds: 3)); // Show logo for 3 seconds

    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

    if (!mounted) return;

    if (hasSeenOnboarding) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthChecker()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const OnboardingPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Or your preferred background color
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Your logo
            Image.asset(
              'assets/logo.png', // Make sure this path is correct and logo is in assets
              width: 300, // Adjust size as needed
              height: 300,
            ),
            // Removed: const SizedBox(height: 20),
            // Removed: const CircularProgressIndicator(
            // Removed:   valueColor: AlwaysStoppedAnimation<Color>(Colors.black), // Loading indicator color
            // Removed: ),
          ],
        ),
      ),
    );
  }
}