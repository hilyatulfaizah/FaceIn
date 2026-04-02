import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_in/login.dart'; // Assuming LoginPage is in this path
import 'package:image_picker/image_picker.dart'; // Import for image picking
import 'dart:io'; // For File class
import 'package:firebase_storage/firebase_storage.dart'; // Import for Firebase Storage
import 'package:flutter/scheduler.dart'; // Import for SchedulerBinding
import 'package:face_in/employee/change_password_screen.dart'; // Import the new screen


class ProfileUser extends StatefulWidget {
  const ProfileUser({super.key});

  @override
  State<ProfileUser> createState() => _ProfileUserState();
}

class _ProfileUserState extends State<ProfileUser> {
  final _formKey = GlobalKey<FormState>(); // This form key will now only be used for the edit profile form
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? user; // Made nullable to reflect initial state

  // Controllers for editable fields
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _jobTitleController = TextEditingController(); // Added for job title

  String? _profilePicUrl;
  File? _pickedImage; // To hold the image picked from gallery

  bool _isLoading = true; // Overall loading state for the page
  bool _showEditProfileView = false; // Toggles between main menu and edit profile view

  @override
  void initState() {
    super.initState();
    _initUserAndLoadData(); // New method to handle user and data loading
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _genderController.dispose();
    _jobTitleController.dispose(); // Dispose new controller
    super.dispose();
  }

  /// Initializes the user and then loads profile data.
  Future<void> _initUserAndLoadData() async {
    user = FirebaseAuth.instance.currentUser; // Get current user here
    await _loadProfileData();
  }

  /// Loads all employee profile data from Firestore.
  Future<void> _loadProfileData() async {
    if (!mounted) return;

    if (user == null) {
      setState(() {
        _isLoading = false;
        _fullNameController.text = 'Guest User';
        _usernameController.text = 'guest_user';
        _emailController.text = 'Not logged in';
        _genderController.text = 'N/A';
        _jobTitleController.text = 'N/A'; // Default for guest
      });
      return;
    }

    try {
      final doc = await _firestore.collection('Employee').doc(user!.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) { // Check mounted before setState
          setState(() {
            _fullNameController.text = data['fullName'] ?? '';
            _usernameController.text = data['username'] ?? data['email']?.split('@')[0] ?? '';
            _emailController.text = data['email'] ?? user!.email ?? '';
            _phoneController.text = data['phone'] ?? '';
            _genderController.text = data['gender'] ?? '';
            _jobTitleController.text = data['jobTitle'] ?? ''; // Load jobTitle
            _profilePicUrl = data['profilePicUrl'];
          });
        }
      } else {
        if (mounted) { // Check mounted before setState
          setState(() {
            _fullNameController.text = user!.displayName ?? 'Employee User';
            _usernameController.text = user!.email?.split('@')[0] ?? 'employee_user';
            _emailController.text = user!.email ?? 'N/A';
            _genderController.text = 'N/A';
            _jobTitleController.text = 'N/A'; // Default if doc doesn't exist
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading profile data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Picks an image from the gallery and updates the profile picture.
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      if (mounted) { // Check mounted before setState
        setState(() {
          _pickedImage = File(image.path);
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image selected. Tap Save to update profile.')),
        );
      }
    }
  }


  /// Saves the updated profile data to Firestore.
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please correct the errors in the form.')),
      );
      return;
    }
    if (mounted) { // Check mounted before setState
      setState(() => _isLoading = true);
    }
    try {
      String? finalProfilePicUrl = _profilePicUrl;

      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not logged in. Cannot save profile.')),
          );
        }
        if (mounted) { // Check mounted before setState
          setState(() => _isLoading = false);
        }
        return;
      }

      if (_pickedImage != null) {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('profile_pictures')
              .child('${user!.uid}.jpg');

          await storageRef.putFile(_pickedImage!);
          finalProfilePicUrl = await storageRef.getDownloadURL();
        } on FirebaseException catch (e) {
          debugPrint("Firebase Storage Error uploading image: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to upload image: ${e.message}')),
            );
          }
          if (mounted) { // Check mounted before setState
            setState(() => _isLoading = false);
          }
          return;
        } catch (e) {
          debugPrint("General Error uploading image: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to upload image: $e')),
            );
          }
          if (mounted) { // Check mounted before setState
            setState(() => _isLoading = false);
          }
          return;
        }
      }

      await _firestore.collection('Employee').doc(user!.uid).set({
        'fullName': _fullNameController.text.trim(),
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'gender': _genderController.text.trim(),
        'jobTitle': _jobTitleController.text.trim(), // Save jobTitle
        'profilePicUrl': finalProfilePicUrl,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
      }
      await _loadProfileData();
      if (mounted) { // Check mounted before setState
        setState(() {
          _showEditProfileView = false;
          _pickedImage = null;
        });
      }
    } catch (e) {
      debugPrint("Error saving profile: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _showEditProfileView
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: () {
                  // Navigate back to profile menu from edit profile view
                  if (mounted) { // Check mounted before setState
                    setState(() {
                      _showEditProfileView = false;
                      _pickedImage = null; // Clear picked image if user goes back
                    });
                  }
                },
              )
            : null,
        title: Text(
          _showEditProfileView ? 'Edit Profile' : 'Profile',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: const [],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showEditProfileView
              ? _buildEditProfileDetailsView()
              : _buildProfileMenuView(),
    );
  }

  /// Builds the main profile menu view.
  Widget _buildProfileMenuView() {
    // Determine the image provider based on _profilePicUrl
    ImageProvider<Object>? backgroundImage;
    if (_profilePicUrl != null && _profilePicUrl!.isNotEmpty) {
      backgroundImage = NetworkImage(_profilePicUrl!);
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: (backgroundImage == null) ? Colors.grey.shade200 : null, // Only show background color if icon is visible
                  backgroundImage: backgroundImage, // No child if image is present
                  // Only provide onBackgroundImageError if there's a NetworkImage that *might* fail
                  onBackgroundImageError: (backgroundImage is NetworkImage)
                      ? (exception, stackTrace) {
                          SchedulerBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                _profilePicUrl = null; // Fallback to icon if network image fails
                              });
                            }
                          });
                        }
                      : null, // Use the determined image provider
                  child: (backgroundImage == null) // Show icon only if no background image is set
                      ? Icon(
                          Icons.person, // The profile icon
                          size: 60, // Adjust size as needed
                          color: Colors.grey.shade600, // Color of the icon
                        )
                      : null, // No error callback if there's no network image to load
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _fullNameController.text,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Employee',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 30),
          _buildProfileOption(
            context,
            icon: Icons.person_outline,
            title: 'Edit Profile',
            onTap: () {
              if (mounted) { // Check mounted before setState
                setState(() {
                  _showEditProfileView = true;
                });
              }
            },
          ),
          _buildProfileOption(
            context,
            icon: Icons.lock_outline,
            title: 'Change Password',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ChangePasswordScreen()),
              );
            },
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                }
              },
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text('Sign Out', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 143, 83, 167),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Builds the detailed editable profile form view.
  Widget _buildEditProfileDetailsView() {
    // Determine the image provider based on _pickedImage or _profilePicUrl
    ImageProvider<Object>? backgroundImage;
    if (_pickedImage != null) {
      backgroundImage = FileImage(_pickedImage!);
    } else if (_profilePicUrl != null && _profilePicUrl!.isNotEmpty) {
      backgroundImage = NetworkImage(_profilePicUrl!);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: (backgroundImage == null) ? Colors.grey.shade200 : null, // Only show background color if icon is visible
                    backgroundImage: backgroundImage, // No child if image is present
                    // Only provide onBackgroundImageError if there's a NetworkImage that *might* fail
                    onBackgroundImageError: (backgroundImage is NetworkImage)
                        ? (exception, stackTrace) {
                            SchedulerBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() {
                                  _profilePicUrl = null; // Fallback to icon if network image fails
                                });
                              }
                            });
                          }
                        : null, // Use the determined image provider
                    child: (backgroundImage == null) // Show icon only if no background image is set
                        ? Icon(
                            Icons.person, // The profile icon
                            size: 60, // Adjust size as needed
                            color: Colors.grey.shade600, // Color of the icon
                          )
                        : null, // No error callback if there's no network image to load
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.shade300, width: 1),
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.grey, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildLabeledTextField(
              controller: _fullNameController,
              label: 'Name',
              hintText: 'Albert Florest',
              validator: (v) => v == null || v.isEmpty ? 'This field is required' : null, // Added validator
            ),
            const SizedBox(height: 16),
            _buildLabeledTextField(
              controller: _usernameController,
              label: 'Username',
              hintText: 'albertflorest_',
              validator: (v) => v == null || v.isEmpty ? 'This field is required' : null, // Added validator
            ),
            const SizedBox(height: 16),
            _buildLabeledDropdownField(
              controller: _genderController,
              label: 'Gender',
              hintText: 'Male',
              options: ['Male', 'Female', 'Other'],
            ),
            const SizedBox(height: 16),
            _buildLabeledTextField(
              controller: _phoneController,
              label: 'Phone Number',
              hintText: '+44 1632 960860',
              keyboardType: TextInputType.phone,
              validator: (v) => v == null || v.isEmpty ? 'This field is required' : null, // Added validator
            ),
            const SizedBox(height: 16),
            _buildLabeledTextField(
              controller: _emailController,
              label: 'Email',
              hintText: 'albertflorest@email.com',
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v == null || v.isEmpty ? 'This field is required' : null, // Added validator
            ),
            const SizedBox(height: 16),
            _buildLabeledTextField(
              controller: _jobTitleController,
              label: 'Job Title',
              hintText: 'Software Engineer',
              validator: (v) => v == null || v.isEmpty ? 'This field is required' : null, // Added validator
            ),
            const SizedBox(height: 40),
            Center(
              child: ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 143, 83, 167),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 50),
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
                        'Save',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Helper function to build a consistent profile option tile for the main menu.
  Widget _buildProfileOption(BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        leading: Icon(icon, color: Colors.black54),
        title: Text(title, style: const TextStyle(color: Colors.black87, fontSize: 16)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  /// Helper function to create a labeled TextFormField.
  Widget _buildLabeledTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    TextInputType? keyboardType,
    bool obscureText = false, // Added for password fields
    String? Function(String?)? validator, // Added validator parameter
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText, // Apply obscureText
          style: const TextStyle(fontSize: 16, color: Colors.black),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          validator: validator, // Pass validator
        ),
      ],
    );
  }

  /// Helper function to create a labeled DropdownField.
  Widget _buildLabeledDropdownField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    required List<String> options,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: controller.text.isNotEmpty && options.contains(controller.text)
              ? controller.text
              : null,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          items: options.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              controller.text = newValue;
            }
          },
          validator: (v) => v == null || v.isEmpty ? 'This field is required' : null,
        ),
      ],
    );
  }
}
