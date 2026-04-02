import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_in/login.dart'; // Keep only this, assuming your LoginPage is here

class RegisterCompany extends StatefulWidget {
  final String userId;
  final String email;
  final String companyId;

  const RegisterCompany({
    super.key,
    required this.userId,
    required this.email,
    required this.companyId,
  });

  @override
  State<RegisterCompany> createState() => _RegisterCompanyState();
}

class _RegisterCompanyState extends State<RegisterCompany> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _regNoController = TextEditingController();
  final TextEditingController _industryController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _adminPhoneController = TextEditingController();

  String? _companySize;
  final List<String> _companySizes = ['1–10', '11–50', '51–100', '100+'];
  bool _isLoading = false;

  @override
  void dispose() {
    _companyNameController.dispose();
    _regNoController.dispose();
    _industryController.dispose();
    _addressController.dispose();
    _adminPhoneController.dispose();
    super.dispose();
  }

  Future<void> _saveCompanyInfo() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    await FirebaseFirestore.instance.collection('companies').doc(widget.companyId).update({
      'name': _companyNameController.text.trim(),
      'registrationNo': _regNoController.text.trim(),
      'industry': _industryController.text.trim(),
      'size': _companySize,
      'address': _addressController.text.trim(),
      'adminEmail': widget.email,
      'adminPhone': _adminPhoneController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    setState(() => _isLoading = false);

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up Company Profile'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Company Information',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _companyNameController,
                          decoration: const InputDecoration(
                            labelText: 'Company Name',
                            prefixIcon: Icon(Icons.business),
                          ),
                          validator: (v) => v == null || v.isEmpty ? 'Enter company name' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _regNoController,
                          decoration: const InputDecoration(
                            labelText: 'Business Registration No.',
                            prefixIcon: Icon(Icons.confirmation_number),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _industryController,
                          decoration: const InputDecoration(
                            labelText: 'Industry/Category',
                            prefixIcon: Icon(Icons.category),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _companySize,
                          items: _companySizes
                              .map((size) =>
                                  DropdownMenuItem(value: size, child: Text(size)))
                              .toList(),
                          onChanged: (v) => setState(() => _companySize = v),
                          decoration: const InputDecoration(
                            labelText: 'Company Size',
                            prefixIcon: Icon(Icons.people),
                          ),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Select company size' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _addressController,
                          decoration: const InputDecoration(
                            labelText: 'Company Address',
                            prefixIcon: Icon(Icons.location_on),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 32),
                        const Text('Admin Contact',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: widget.email,
                          enabled: false,
                          decoration: const InputDecoration(
                            labelText: 'Admin Email',
                            prefixIcon: Icon(Icons.email),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _adminPhoneController,
                          decoration: const InputDecoration(
                            labelText: 'Admin Phone Number',
                            prefixIcon: Icon(Icons.phone),
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saveCompanyInfo,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.deepPurple,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Save & Continue',
                              style: TextStyle(fontSize: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
