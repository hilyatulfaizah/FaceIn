// onboarding_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:face_in/login.dart'; // Import your login page
import 'package:google_fonts/google_fonts.dart'; // Import Google Fonts

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<Map<String, String>> onboardingData = [
    {
      "image": "assets/logo.png", // Make sure you have a logo in your assets folder
      "title": "Welcome to FaceIn",
      "description": "Your ultimate solution for seamless attendance management and enhanced security.",
    },
    {
      "image": "assets/lottie/face_scan_animation.json", // Example image
      "title": "Effortless Attendance",
      "description": "Clock in and out with just your face! Quick, accurate, and secure.",
    },
    {
      //"image": "assets/notifications.png", // Example image
      "title": "Stay Informed",
      "description": "Receive real-time notifications about logins, attendance, and important updates.",
    },
  ];

  _onPageViewChange(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  _storeOnboardingStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFE0F2F7), // Light Blue
              Color(0xFFBBDEFB), // Darker Blue
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: onboardingData.length,
              onPageChanged: _onPageViewChange,
              itemBuilder: (context, index) {
                return OnboardingScreen(
                  image: onboardingData[index]["image"]!,
                  title: onboardingData[index]["title"]!,
                  description: onboardingData[index]["description"]!,
                );
              },
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 40.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        onboardingData.length,
                        (index) => buildDot(index, context),
                      ),
                    ),
                    const SizedBox(height: 30),
                    if (_currentPage == onboardingData.length - 1)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            await _storeOnboardingStatus();
                            if (!mounted) return;
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                          ),
                          child: Text(
                            'Get Started',
                            style: GoogleFonts.poppins( // Using Poppins font
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.ease,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                          ),
                          child: Text(
                            'Next',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (_currentPage != onboardingData.length - 1)
                      TextButton(
                        onPressed: () async {
                          await _storeOnboardingStatus();
                          if (!mounted) return;
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                          );
                        },
                        child: Text(
                          'Skip',
                          style: GoogleFonts.poppins(
                            color: Colors.black54,
                            fontSize: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Container buildDot(int index, BuildContext context) {
    return Container(
      height: 10,
      width: _currentPage == index ? 28 : 10,
      margin: const EdgeInsets.only(right: 5),
      decoration: BoxDecoration(
        color: _currentPage == index ? Colors.black : Colors.grey.shade400,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

class OnboardingScreen extends StatelessWidget {
  final String image;
  final String title;
  final String description;

  const OnboardingScreen({
    super.key,
    required this.image,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            image,
            height: 250,
            width: 250,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 50),
          Text(
            title,
            style: GoogleFonts.poppins( // Using Poppins font
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            description,
            style: GoogleFonts.poppins( // Using Poppins font
              fontSize: 17,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}