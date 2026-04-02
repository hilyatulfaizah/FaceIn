import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_in/login.dart';
import 'package:face_in/admin/SetCompanyLocationScreen.dart';
import 'package:image_picker/image_picker.dart'; // Corrected import
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class ProfileCompany extends StatefulWidget {
  final String companyId;

  const ProfileCompany({super.key, required this.companyId});

  @override
  State<ProfileCompany> createState() => _ProfileCompanyState();
}

class _ProfileCompanyState extends State<ProfileCompany> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _adminNameController = TextEditingController();
  final TextEditingController _adminEmailController = TextEditingController();
  final TextEditingController _currentPlanController = TextEditingController();
  final TextEditingController _companyIdController = TextEditingController();

  Map<String, dynamic>? _companyData;
  String? _companyLogoUrl;
  File? _pickedImage;

  bool _isLoading = true;
  bool _showEditCompanyForm = false; // Controls showing the editable form
  bool _showCompanyDetailsDisplay = false; // Controls showing the non-editable display view
  String _statusMessage = '';

  String? _loadedAdminName; // track loaded admin name

  // Define the purple color for buttons
  final Color appPurple = const Color.fromARGB(255, 143, 83, 167);
  // Define the yellow color for icons
  final Color appYellow = const Color.fromARGB(255, 255, 193, 7);

  @override
  void initState() {
    super.initState();
    _companyIdController.text = widget.companyId;
    _loadAllCompanyData();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _currentPlanController.dispose();
    _companyIdController.dispose();
    super.dispose();
  }

  Future<void> _loadAllCompanyData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final user = _auth.currentUser;
      if (user != null) {
        _adminEmailController.text = user.email ?? '';
        final userDoc =
            await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          _adminNameController.text = userDoc.data()?['name'] ?? 'Admin';
          _loadedAdminName = _adminNameController.text;
        } else {
          _adminNameController.text = 'Admin';
          _loadedAdminName = 'Admin';
        }
      } else {
        _adminNameController.text = 'N/A';
        _adminEmailController.text = 'N/A';
        _loadedAdminName = 'N/A';
      }

      final companyDoc = await _firestore
          .collection('companies')
          .doc(widget.companyId)
          .get();
      if (companyDoc.exists) {
        _companyData = companyDoc.data();
        if (mounted) {
          setState(() {
            _companyNameController.text = _companyData?['name'] ?? 'Unnamed Company';
            _companyLogoUrl = _companyData?['logoUrl'];
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _companyNameController.text = 'Unnamed Company';
            _statusMessage = 'Company settings not found. Please set them.';
          });
        }
      }

      final subscriptionDoc = await _firestore
          .collection('subscriptions')
          .doc(widget.companyId)
          .get();
      if (subscriptionDoc.exists) {
        if (mounted) {
          setState(() {
            // Force the current plan to 'PREMIUM' for demonstration purposes
            _currentPlanController.text = 'PREMIUM';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _currentPlanController.text = 'Free Plan'; // Default if no subscription found
          });
        }
      }

    } catch (e) {
      debugPrint('Error loading company data: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Error loading company profile: ${e.toString()}';
        });
      }
      _showSnackBar(
          'Error loading company profile: ${e.toString()}', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      if (mounted) {
        setState(() {
          _pickedImage = File(image.path);
        });
      }
      _showSnackBar(
          'Image selected. Tap Save to update company logo.', Colors.green);
    }
  }

  Future<void> _saveCompanyProfile() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please correct the errors in the form.', Colors.red);
      return;
    }

    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      String? finalCompanyLogoUrl = _companyLogoUrl;

      if (_pickedImage != null) {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('company_logos')
              .child('${widget.companyId}.jpg');
          await storageRef.putFile(_pickedImage!);
          finalCompanyLogoUrl = await storageRef.getDownloadURL();
        } on FirebaseException catch (e) {
          debugPrint("Firebase Storage Error: $e");
          _showSnackBar('Failed to upload logo: ${e.message}', Colors.red);
          if (mounted) {
            setState(() => _isLoading = false);
          }
          return;
        }
      }

      await _firestore
          .collection('companies')
          .doc(widget.companyId)
          .set({
        'name': _companyNameController.text.trim(),
        'logoUrl': finalCompanyLogoUrl,
      }, SetOptions(merge: true));

      if (_auth.currentUser != null &&
          _adminNameController.text.trim() != (_loadedAdminName ?? '')) {
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .set({
          'name': _adminNameController.text.trim(),
        }, SetOptions(merge: true));
      }

      _showSnackBar('Company profile updated successfully!', Colors.green);
      await _loadAllCompanyData();
      if (mounted) {
        setState(() {
          _showEditCompanyForm = false;
          _showCompanyDetailsDisplay = true; // Go back to the display view
          _pickedImage = null;
        });
      }
    } catch (e) {
      debugPrint("Error saving company profile: $e");
      _showSnackBar('Error saving company profile: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      duration: const Duration(seconds: 3),
    ));
  }

  Widget _buildPlanOption(String title, String price, String description, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: color)),
          Text(price,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w500)),
          Text(description,
              style:
                  const TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 5),
          const Divider(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_showEditCompanyForm) {
          if (mounted) {
            setState(() {
              _showEditCompanyForm = false;
              _showCompanyDetailsDisplay = true; // Go back to display view
              _pickedImage = null;
            });
          }
          return false;
        } else if (_showCompanyDetailsDisplay) {
          if (mounted) {
            setState(() {
              _showCompanyDetailsDisplay = false; // Go back to main menu
            });
          }
          return false;
        }
        return true; // Allow normal back navigation from main menu
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () {
              if (_showEditCompanyForm) {
                if (mounted) {
                  setState(() {
                    _showEditCompanyForm = false;
                    _showCompanyDetailsDisplay = true;
                    _pickedImage = null;
                  });
                }
              } else if (_showCompanyDetailsDisplay) {
                if (mounted) {
                  setState(() {
                    _showCompanyDetailsDisplay = false;
                  });
                }
              } else {
                Navigator.pop(context); // Pop from main menu
              }
            },
          ),
          title: Text(
            _showEditCompanyForm
                ? 'Edit Company Profile'
                : _showCompanyDetailsDisplay
                    ? 'Company Details'
                    : 'Company Profile',
            style: const TextStyle(
                color: Colors.black87, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color.fromARGB(255, 143, 83, 167),
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black87),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _showEditCompanyForm
                ? _buildEditCompanyFormView() // Editable form view
                : _showCompanyDetailsDisplay
                    ? _buildCompanyDetailsDisplayView() // Non-editable display view
                    : _buildCompanyMenuView(), // Main menu view
      ),
    );
  }

  Widget _buildCompanyMenuView() {
    // Determine the image provider based on _companyLogoUrl
    ImageProvider<Object>? backgroundImage;
    if (_companyLogoUrl != null && _companyLogoUrl!.isNotEmpty) {
      backgroundImage = NetworkImage(_companyLogoUrl!);
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Center(
            child: CircleAvatar(
              radius: 60,
              backgroundColor: (backgroundImage == null) ? Colors.grey.shade200 : null,
              backgroundImage: backgroundImage,
              onBackgroundImageError: (backgroundImage is NetworkImage)
                  ? (exception, stackTrace) {
                      if (mounted) {
                        setState(() {
                          _companyLogoUrl = null;
                        });
                      }
                    }
                  : null,
              child: (backgroundImage == null)
                  ? Icon(
                      Icons.business,
                      size: 60,
                      color: appYellow, // Icon color yellow
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _companyNameController.text,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Center(
            child: Text(
              'Company Administrator',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 30),
          _buildProfileOption(
              context,
              icon: Icons.business_center_outlined,
              title: 'Company Details', // Changed title to reflect the display view
              onTap: () {
                if (mounted) {
                  setState(() {
                    _showCompanyDetailsDisplay = true; // Go to display view
                    _showEditCompanyForm = false; // Ensure edit form is hidden
                  });
                }
              }),
          const SizedBox(height: 10),
          _buildProfileOption(
              context,
              icon: Icons.settings_outlined,
              title: 'Company Operations Settings',
              onTap: () async {
await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => SetCompanyLocationScreen(
      companyId: widget.companyId,
    ),
  ),
);
                _loadAllCompanyData();
              }),
          const SizedBox(height: 10),
          _buildProfileOption(
              context,
              icon: Icons.workspace_premium_outlined,
              title: 'Manage Subscription',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SubscriptionManagementPage(
                      currentPlan: _currentPlanController.text,
                      companyId: widget.companyId,
                    ),
                  ),
                );
              }),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                await _auth.signOut();
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                }
              },
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text('Sign Out',
                  style: TextStyle(color: Colors.white)), // Explicit font style
              style: ElevatedButton.styleFrom(
                backgroundColor: appPurple, // Button color purple
                minimumSize: const Size(double.infinity, 50), // Same size as requested
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_statusMessage.isNotEmpty && !_isLoading)
            Center(
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _statusMessage.contains('Error')
                        ? Colors.red
                        : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompanyDetailsDisplayView() {
    ImageProvider<Object>? backgroundImage;
    if (_companyLogoUrl != null && _companyLogoUrl!.isNotEmpty) {
      backgroundImage = NetworkImage(_companyLogoUrl!);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // Center items horizontally
        children: [
          const SizedBox(height: 20),
          Center(
            child: CircleAvatar(
              radius: 60,
              backgroundColor: (backgroundImage == null) ? Colors.grey.shade200 : null,
              backgroundImage: backgroundImage,
              onBackgroundImageError: (backgroundImage is NetworkImage)
                  ? (exception, stackTrace) {
                      if (mounted) {
                        setState(() {
                          _companyLogoUrl = null;
                        });
                      }
                    }
                  : null,
              child: (backgroundImage == null)
                  ? Icon(
                      Icons.business,
                      size: 60,
                      color: appYellow, // Icon color yellow
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 20),
          _buildInfoRow(
              icon: Icons.corporate_fare,
              label: 'Company Name',
              value: _companyNameController.text),
          const SizedBox(height: 16),
          _buildInfoRow(
              icon: Icons.person,
              label: 'Admin Name',
              value: _adminNameController.text),
          const SizedBox(height: 16),
          _buildInfoRow(
              icon: Icons.email,
              label: 'Admin Email',
              value: _adminEmailController.text),
          const SizedBox(height: 16),
          _buildInfoRow(
              icon: Icons.vpn_key,
              label: 'Company ID',
              value: _companyIdController.text),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () {
              if (mounted) {
                setState(() {
                  _showEditCompanyForm = true; // Show the editable form
                  _showCompanyDetailsDisplay = false; // Hide this display view
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: appPurple, // Button color purple
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50), // Same size as requested
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(color: Colors.white), // Explicit font style
            ),
            child: const Text('Edit Profile'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: appYellow), // Icon color yellow
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditCompanyFormView() {
    // Determine the image provider based on _pickedImage or _companyLogoUrl
    ImageProvider<Object>? backgroundImage;
    if (_pickedImage != null) {
      backgroundImage = FileImage(_pickedImage!);
    } else if (_companyLogoUrl != null && _companyLogoUrl!.isNotEmpty) {
      backgroundImage = NetworkImage(_companyLogoUrl!);
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
                    backgroundColor: (backgroundImage == null) ? Colors.grey.shade200 : null,
                    backgroundImage: backgroundImage,
                    onBackgroundImageError: (backgroundImage is NetworkImage)
                        ? (exception, stackTrace) {
                            if (mounted) {
                              setState(() {
                                _companyLogoUrl = null;
                              });
                            }
                          }
                        : null,
                    child: (backgroundImage == null)
                        ? Icon(
                            Icons.business,
                            size: 60,
                            color: appYellow, // Icon color yellow
                          )
                        : null,
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
                          border: Border.all(
                              color: Colors.grey.shade300, width: 1),
                        ),
                        child: Icon(Icons.camera_alt,
                            color: appYellow, size: 20), // Icon color yellow
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildLabeledTextField(
              controller: _companyNameController,
              label: 'Company Name',
              hintText: 'Your Company Name',
              validator: (value) => value == null || value.isEmpty
                  ? 'Company name cannot be empty'
                  : null,
            ),
            const SizedBox(height: 16),
            _buildLabeledTextField(
              controller: _adminNameController,
              label: 'Admin Name',
              hintText: 'Admin Full Name',
              readOnly: false,
              validator: (value) => value == null || value.isEmpty
                  ? 'Admin name cannot be empty'
                  : null,
            ),
            const SizedBox(height: 16),
            _buildLabeledTextField(
              controller: _adminEmailController,
              label: 'Admin Email',
              hintText: 'admin@company.com',
              keyboardType: TextInputType.emailAddress,
              readOnly: true,
            ),
            const SizedBox(height: 16),
            _buildLabeledTextField(
              controller: _companyIdController,
              label: 'Company ID',
              readOnly: true,
            ),
            const SizedBox(height: 40),
            Center(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveCompanyProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: appPurple, // Button color purple
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                      )
                    : const Text('Save Changes',
                        style: TextStyle(color: Colors.white)), // Explicit font style
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOption(BuildContext context,
      {required IconData icon,
      required String title,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 5,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: appYellow), // Icon color yellow
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 16, color: appYellow), // Icon color yellow
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabeledTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    bool readOnly = false,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: keyboardType,
          validator: validator,
          onTap: onTap,
          decoration: InputDecoration(
            hintText: hintText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
}

// SubscriptionManagementPage class
class SubscriptionManagementPage extends StatelessWidget {
  final String currentPlan;
  final String companyId;

  const SubscriptionManagementPage({
    super.key,
    required this.currentPlan,
    required this.companyId,
  });

  Widget _buildPlanOption(BuildContext context, String title, String price,
      String description, Color color) {
    String buttonText;
    VoidCallback? onPressed;
    bool isPremiumPlan = (title == 'PREMIUM');

    if (title == 'PREMIUM') {
      buttonText = 'Already Subscribed';
      onPressed = null; // Disabled only for Premium
    } else {
      buttonText = 'Select Plan';
      onPressed = () {
        // Dummy action just to keep button active and colored
      };
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isPremiumPlan ? Border.all(color: Colors.yellow, width: 2) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: onPressed == null ? Colors.grey : color,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Choose Your Plan',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 15),
            _buildPlanOption(
              context,
              'FREE PLAN',
              'MYR 0/month',
              'Manage attendance for up to 5 employees.\nBasic reporting features.',
              Colors.blueGrey,
            ),
            const SizedBox(height: 10),
            _buildPlanOption(
              context,
              'PREMIUM',
              'MYR 22/month',
              'Manage attendance for up to 100 employees.\nAdvanced reporting & analytics.\nGeo-fencing for attendance tracking.',
              Colors.deepOrange,
            ),
            const SizedBox(height: 10),
            _buildPlanOption(
              context,
              'UNLIMITED',
              'MYR 199.99/month',
              'Unlimited employees.\nAll Premium features, custom integrations, dedicated support, enterprise-grade security.',
              Colors.purple.shade700,
            ),
            const SizedBox(height: 20),
            const Text(
              'Choose the plan that best fits your company\'s needs!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
