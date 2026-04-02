import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'employee_profile.dart';
import 'register_employee.dart';

class ManageEmployee extends StatefulWidget {
  final String companyId;

  const ManageEmployee({super.key, required this.companyId});

  @override
  State<ManageEmployee> createState() => _ManageEmployeeState();
}

class _ManageEmployeeState extends State<ManageEmployee> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Employees'),
        backgroundColor: const Color.fromARGB(255, 143, 83, 167),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black, size: 28),
            tooltip: 'Add Employee',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RegisterEmployeePage(
                    companyId: widget.companyId,
                  ),
                ),
              );

              // This setState is mainly for clearing the search bar,
              // but the StreamBuilder would handle the data update anyway.
              setState(() {
                _searchQuery = '';
                _searchController.clear();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by Name, Worker ID or Job Title',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Employee')
                  .where('companyId', isEqualTo: widget.companyId)
                  .snapshots(), // Listening to real-time changes
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No employees found.'));
                }

                // Filter employees based on search query
                final employees = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final fullName = (data['fullName'] ?? '').toLowerCase();
                  final workerId = (data['username'] ?? '').toLowerCase(); // Assuming 'username' is workerId
                  final jobTitle = (data['jobTitle'] ?? '').toLowerCase();

                  return fullName.contains(_searchQuery) ||
                      workerId.contains(_searchQuery) ||
                      jobTitle.contains(_searchQuery);
                }).toList();

                if (employees.isEmpty && _searchQuery.isNotEmpty) {
                  return Center(
                      child: Text('No employees found for "$_searchQuery"'));
                } else if (employees.isEmpty && _searchQuery.isEmpty) {
                  return const Center(child: Text('No employees registered.'));
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.75, // Adjust as needed
                  ),
                  itemCount: employees.length,
                  itemBuilder: (context, index) {
                    final employee = employees[index].data() as Map<String, dynamic>;
                    final employeeId = employees[index].id;
                    return EmployeeCard(
                      employee: employee,
                      employeeId: employeeId,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EmployeeProfilePage(
                              employeeId: employeeId,
                              employeeData: employee, // Pass initial data
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class EmployeeCard extends StatelessWidget {
  final Map<String, dynamic> employee;
  final String employeeId;
  final VoidCallback onTap;

  const EmployeeCard({
    super.key,
    required this.employee,
    required this.employeeId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.blueGrey[100],
              // Use 'profilePicUrl' for the image
              backgroundImage: employee['profilePicUrl'] != null &&
                      employee['profilePicUrl'].toString().isNotEmpty
                  ? NetworkImage(employee['profilePicUrl'])
                  : null,
              child: employee['profilePicUrl'] == null ||
                      employee['profilePicUrl'].toString().isEmpty
                  ? Icon(Icons.person,
                      size: 40, color: Colors.blueGrey[400])
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              employee['fullName'] ?? 'No Name', // Use 'fullName'
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                employee['jobTitle'] ?? 'Unknown Job', // Use 'jobTitle'
                style:
                    const TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}