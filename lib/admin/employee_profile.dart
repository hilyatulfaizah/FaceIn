import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/scheduler.dart';


class EmployeeProfilePage extends StatefulWidget {
  final String employeeId;
  final Map<String, dynamic> employeeData; // For initial load, StreamBuilder handles updates

  const EmployeeProfilePage({
    super.key,
    required this.employeeId,
    required this.employeeData,
  });

  @override
  State<EmployeeProfilePage> createState() => _EmployeeProfilePageState();
}

class _EmployeeProfilePageState extends State<EmployeeProfilePage> {
  // Eagerly initialize controllers to prevent LateInitializationError
  TextEditingController nameController = TextEditingController();
  TextEditingController jobTitleController = TextEditingController();
  TextEditingController phoneController = TextEditingController();
  final TextEditingController _customDepartmentController = TextEditingController(); // Controller for custom department input


  String department = 'IT'; // Initial value for department dropdown
  String role = 'Employee';
  bool hasRegisteredFace = false;

  final List<String> departments = [
    'IT',
    'HR',
    'Marketing',
    'Finance',
    'Operations',
    'Sales',
    'Customer Service',
    'Engineering',
    'Research & Development',
    'Legal',
    'Administration',
    'Logistics',
    'Production',
    'Design',
    'Quality Assurance',
    'Public Relations',
    'Procurement',
    'Training',
    'Security',
    'Healthcare',
    'Education',
    'Other' // Added 'Other' option
  ];
  final List<String> roles = ['Employee', 'Supervisor', 'Admin'];

  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    // Controllers are already initialized in their declaration
    // _initializeControllers(widget.employeeData); // Removed: Data will be streamed
  }

  // This method now only updates the text of existing controllers
  // It's primarily used when cancelling edits to revert to the current streamed data
  void _updateControllersFromData(Map<String, dynamic> data) {
    nameController.text = data['fullName'] ?? '';
    jobTitleController.text = data['jobTitle'] ?? '';
    phoneController.text = data['phone'] ?? '';

    // Set department, if it's not in the predefined list, set to 'Other' and populate custom controller
    final currentDepartment = data['department'] ?? 'IT';
    if (departments.contains(currentDepartment)) {
      department = currentDepartment;
      _customDepartmentController.text = ''; // Clear if it's a predefined option
    } else {
      department = 'Other';
      _customDepartmentController.text = currentDepartment; // Populate with custom value
    }

    role = data['role'] ?? 'Employee';
    hasRegisteredFace = data['hasRegisteredFace'] ?? false;
  }

  @override
  void dispose() {
    nameController.dispose();
    jobTitleController.dispose();
    phoneController.dispose();
    _customDepartmentController.dispose(); // Dispose custom department controller
    super.dispose();
  }

  /// Helper function to create a labeled TextFormField.
  Widget _buildLabeledTextField({
    TextEditingController? controller,
    required String label,
    String? hintText,
    TextInputType? keyboardType,
    bool readOnly = false,
    String? initialValue,
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
          // Only use initialValue if controller is null (for readOnly fields not tied to a controller)
          initialValue: controller == null ? initialValue : null,
          readOnly: readOnly,
          keyboardType: keyboardType,
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
          validator: (v) => v == null || v.isEmpty ? 'This field is required' : null,
        ),
      ],
    );
  }

  /// Helper function to create a labeled DropdownField.
  Widget _buildLabeledDropdownField({
    required String label,
    String? hintText,
    required List<String> options,
    required String currentValue, // Pass the current selected value
    required ValueChanged<String?> onChanged, // Callback for when value changes
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
          value: options.contains(currentValue) ? currentValue : null, // Ensure value is in options
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
          onChanged: onChanged,
          validator: (v) => v == null || v.isEmpty ? 'This field is required' : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('Employee').doc(widget.employeeId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Not Found')),
            body: const Center(child: Text('Employee not found.')),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;

        // IMPORTANT: Update controllers and state variables with the latest streamed data
        // This ensures the UI reflects real-time changes from Firestore.
        // Only update if not currently editing, or if the data has genuinely changed.
        // This prevents input fields from being reset while the user is typing.
        if (!_isEditing) {
          _updateControllersFromData(data);
        } else {
          // If editing, ensure the dropdowns/checkboxes still reflect the streamed data
          // even if the text controllers are holding user input.
          final streamedDepartment = data['department'] ?? 'IT';
          if (departments.contains(streamedDepartment)) {
            department = streamedDepartment;
          } else {
            department = 'Other';
            // Only update _customDepartmentController if it's not currently being edited
            // and the streamed data is indeed a custom one.
            if (_customDepartmentController.text.isEmpty || _customDepartmentController.text == widget.employeeData['department']) {
              _customDepartmentController.text = streamedDepartment;
            }
          }
          role = data['role'] ?? 'Employee';
          hasRegisteredFace = data['hasRegisteredFace'] ?? false;
        }

        final profilePicUrl = data['profilePicUrl'] as String?;
        final email = data['email'] ?? 'N/A';
        final workerId = data['username'] ?? 'N/A';


        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            title: const Text(
              'Employee Profile',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            actions: [
              IconButton(
                icon: Icon(_isEditing ? Icons.close : Icons.edit_outlined, color: Colors.black),
                tooltip: _isEditing ? 'Cancel Edit' : 'Edit Profile',
                onPressed: () {
                  setState(() {
                    _isEditing = !_isEditing;
                    if (!_isEditing) {
                      // When cancelling edit, revert controllers and state to streamed data
                      _updateControllersFromData(data);
                    }
                  });
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.blueGrey[100], // Background color for the circle
                        // Conditionally display NetworkImage or an Icon
                        backgroundImage: (profilePicUrl != null && profilePicUrl.isNotEmpty)
                            ? NetworkImage(profilePicUrl)
                            : null, // Set to null if no image, to avoid assertion error
                        // onBackgroundImageError should only be present if backgroundImage is not null
                        onBackgroundImageError: (profilePicUrl != null && profilePicUrl.isNotEmpty)
                            ? (exception, stackTrace) {
                                SchedulerBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    // If network image fails, it will fall back to the child icon
                                  }
                                });
                              }
                            : null,
                        child: (profilePicUrl == null || profilePicUrl.isEmpty)
                            ? Icon(Icons.person, size: 60, color: Colors.blueGrey[400]) // User icon
                            : null, // No child if there's a profile image
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
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
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    data['fullName'] ?? 'Employee Name', // Display streamed data
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                Center(
                  child: Text(
                    data['jobTitle'] ?? 'Unknown Job', // Display streamed data
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 20),
                if (!hasRegisteredFace)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Face Not Registered',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Worker ID - always view only
                _buildLabeledTextField(
                  label: 'Worker ID',
                  initialValue: workerId,
                  readOnly: true,
                ),
                const SizedBox(height: 16),

                if (_isEditing)
                  Column(
                    children: [
                      _buildLabeledTextField(
                        controller: nameController,
                        label: 'Full Name',
                        hintText: 'Full Name',
                      ),
                      const SizedBox(height: 16),
                      _buildLabeledTextField(
                        controller: jobTitleController,
                        label: 'Job Position',
                        hintText: 'Job Position',
                      ),
                      const SizedBox(height: 16),
                      _buildLabeledTextField(
                        label: 'Email',
                        initialValue: email,
                        readOnly: true,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      _buildLabeledTextField(
                        controller: phoneController,
                        label: 'Phone Number',
                        hintText: '+44 123 4567890',
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      _buildLabeledDropdownField(
                        label: 'Department',
                        hintText: 'Select Department',
                        options: departments,
                        currentValue: department, // Pass current value
                        onChanged: (newValue) {
                          setState(() {
                            department = newValue!;
                            if (newValue != 'Other') {
                              _customDepartmentController.clear(); // Clear custom input if not 'Other'
                            }
                          });
                        },
                      ),
                      if (department == 'Other') // Conditionally show custom department input
                        Column(
                          children: [
                            const SizedBox(height: 16),
                            _buildLabeledTextField(
                              controller: _customDepartmentController,
                              label: 'Custom Department',
                              hintText: 'e.g., Research & Development',
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      _buildLabeledDropdownField(
                        label: 'Role',
                        hintText: 'Select Role',
                        options: roles,
                        currentValue: role, // Pass current value
                        onChanged: (newValue) {
                          setState(() {
                            role = newValue!;
                          });
                        },
                      ),
                      const SizedBox(height: 40),
                      Center(
                        child: ElevatedButton(
                          onPressed: () => _saveChanges(data['email']),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1), // Light primary fill
                            foregroundColor: Theme.of(context).colorScheme.primary, // Primary color text
                            minimumSize: const Size(200, 50),
                            elevation: 0, // No shadow
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Save Changes',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Delete Employee as a detail field
                      _buildDeleteEmployeeDetailField(),
                    ],
                  )
                else
                  Column(
                    children: [
                      // Display fields using the controllers which are updated by the stream
                      _buildLabeledTextField(
                        label: 'Full Name',
                        initialValue: nameController.text, // Use controller's text
                        readOnly: true,
                      ),
                      const SizedBox(height: 16),
                      _buildLabeledTextField(
                        label: 'Job Position',
                        initialValue: jobTitleController.text, // Use controller's text
                        readOnly: true,
                      ),
                      const SizedBox(height: 16),
                      _buildLabeledTextField(
                        label: 'Email',
                        initialValue: email,
                        readOnly: true,
                      ),
                      const SizedBox(height: 16),
                      _buildLabeledTextField(
                        label: 'Phone Number',
                        initialValue: phoneController.text.isEmpty ? 'N/A' : phoneController.text, // Use controller's text
                        readOnly: true,
                      ),
                      const SizedBox(height: 16),
                      _buildLabeledTextField(
                        label: 'Department',
                        initialValue: department, // Use state variable
                        readOnly: true,
                      ),
                      const SizedBox(height: 16),
                      _buildLabeledTextField(
                        label: 'Role',
                        initialValue: role, // Use state variable
                        readOnly: true,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Helper function to build the delete employee detail field.
  Widget _buildDeleteEmployeeDetailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Danger Zone', // Label for this section
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: InkWell( // Use InkWell for a ripple effect on tap
            onTap: _confirmDelete,
            borderRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Delete Employee',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.red, // Red color for danger
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(Icons.delete_outline, color: Colors.red),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }


  Future<void> _saveChanges(String employeeEmail) async {
    try {
      // Determine the department value to save
      String departmentToSave = department;
      if (department == 'Other') {
        departmentToSave = _customDepartmentController.text.trim();
      }

      await FirebaseFirestore.instance.collection('Employee').doc(widget.employeeId).update({
        'fullName': nameController.text.trim(),
        'jobTitle': jobTitleController.text.trim(),
        'phone': phoneController.text.trim(),
        'department': departmentToSave, // Use the determined department value
        'role': role,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee updated successfully!')));

      setState(() {
        _isEditing = false;
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update employee: $e')));
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Employee'),
        content: const Text('Are you sure you want to delete this employee? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
            ),
            onPressed: () async {
              try {
                // Delete from Firestore
                await FirebaseFirestore.instance.collection('Employee').doc(widget.employeeId).delete();

                // Delete from Firebase Authentication
                // This part requires a Cloud Function or a secure backend
                // because you cannot directly delete another user's account from the client-side.
                // For demonstration, we'll assume a successful deletion or handle the error gracefully.
                final employeeAuthUser = FirebaseAuth.instance.currentUser;
                if (employeeAuthUser != null && employeeAuthUser.uid == widget.employeeId) {
                  // If the currently logged-in user is the one being deleted (unlikely for admin workflow)
                  await employeeAuthUser.delete();
                } else {
                  // In a real application, you'd trigger a Cloud Function here
                  // to delete the Firebase Auth user associated with employeeEmailToDelete.
                  // For example:
                  // await FirebaseFunctions.instance.httpsCallable('deleteUserByEmail').call({
                  //   'email': widget.employeeData['email'],
                  // });
                  print('Firebase Auth user deletion would typically be handled by a Cloud Function or admin SDK for security reasons.');
                }

                Navigator.of(ctx).pop(true); // Pop the dialog with true for success
              } on FirebaseAuthException catch (e) {
                print('Error attempting to delete user from Auth (client-side): $e');
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Failed to delete user from Auth: ${e.message}')),
                );
                Navigator.of(ctx).pop(false); // Pop the dialog with false for failure
              } catch (e) {
                print('Error deleting employee: $e');
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Failed to delete employee: $e')),
                );
                Navigator.of(ctx).pop(false); // Pop the dialog with false for failure
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee deleted.')));
      if (mounted) {
        // Pop current page (EmployeeProfilePage) to go back to ManageEmployee
        Navigator.pop(context);
      }
    }
  }
}
