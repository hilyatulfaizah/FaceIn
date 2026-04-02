import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'manage_employee.dart';
import 'company_profile.dart';
import 'package:intl/intl.dart';
import 'history_page_admin.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomepageAdmin extends StatefulWidget {
  final String name;
  final String companyId;

  const HomepageAdmin({
    super.key,
    required this.name,
    required this.companyId,
  });

  @override
  State<HomepageAdmin> createState() => _HomepageAdminState();
}

class _HomepageAdminState extends State<HomepageAdmin> {
  int _selectedIndex = 0;
  PageController? _mainPageController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? companyName;
  bool isLoading = true;
  String _adminDisplayName = 'Admin';
  PageController? _premiumPlanPageController;
  int _currentMonetizationPageIndex = 0;
  Timer? _timer;

  final List<Map<String, dynamic>> _premiumPlans = [
    {
      'title': 'Premium Plan',
      'price': 'RM 12.99/month',
      'description':
          'Basic Check-in/out, Leave Application, Up to 20 Employees, Get Notifications.',
      'color': Colors.blueGrey,
      'icon': Icons.star_outline,
    },
    {
      'title': 'Gold Plan',
      'price': 'RM 29.99/month',
      'description':
          'All Premium Features, Up to 50 Employees, Advanced Attendance Reports, Priority Support.',
      'color': Colors.amber,
      'icon': Icons.star,
    },
    {
      'title': 'Unlimited Plan',
      'price': 'RM 49.99/month',
      'description':
          'All Gold Features, Unlimited Employees, Customizable Reports, Dedicated Account Manager, API Access.',
      'color': Colors.purple,
      'icon': Icons.workspace_premium,
    },
  ];

  Map<String, String> _employeeNames = {};
  String? _adminProfilePictureUrl;
  String? _adminJobTitle;
  String? _companyCheckInTime;
  String? _companyCheckOutTime;

  @override
  void initState() {
    super.initState();
    _loadCompanyData();
    _mainPageController = PageController();
    _premiumPlanPageController =
        PageController(initialPage: _currentMonetizationPageIndex);
    _startAutoSlide();
    _fetchEmployeeNames();
    _loadAdminProfileData();
    _loadAdminDisplayName();
    _fetchCompanyAttendanceTimes();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _premiumPlanPageController?.dispose();
    _mainPageController?.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _timer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (!mounted ||
          _premiumPlanPageController == null ||
          !_premiumPlanPageController!.hasClients) {
        timer.cancel();
        return;
      }
      int nextPage = (_premiumPlanPageController!.page!.round() + 1) %
          _premiumPlans.length;
      _premiumPlanPageController!.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeIn,
      );
    });
  }

  Future<void> _loadCompanyData() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
    });
    try {
      final doc =
          await _firestore.collection('companies').doc(widget.companyId).get();
      if (!mounted) return;
      if (doc.exists) {
        setState(() {
          companyName = doc['name'] ?? 'Unnamed Company';
          isLoading = false;
        });
      } else {
        setState(() {
          companyName = 'Company not found';
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        companyName = 'Error loading company';
        isLoading = false;
      });
    }
  }

  Future<void> _loadAdminProfileData() async {
    if (mounted) {
      setState(() {
        _adminProfilePictureUrl = null;
        _adminJobTitle = 'Company Administrator';
      });
    }
  }

  Future<void> _loadAdminDisplayName() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final userDoc =
            await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          if (mounted) {
            setState(() {
              _adminDisplayName = userDoc.data()?['name'] ?? 'Admin';
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading admin display name: $e');
        if (mounted) {
          setState(() {
            _adminDisplayName = 'Admin';
          });
        }
      }
    }
  }

  Future<void> _fetchCompanyAttendanceTimes() async {
    try {
      final companyDoc =
          await _firestore.collection('companies').doc(widget.companyId).get();
      if (companyDoc.exists) {
        if (mounted) {
          setState(() {
            _companyCheckInTime = companyDoc.data()?['checkInTime'];
            _companyCheckOutTime = companyDoc.data()?['checkOutTime'];
          });
        }
        debugPrint(
            'Company Check-in Time: $_companyCheckInTime, Check-out Time: $_companyCheckOutTime');
      }
    } catch (e) {
      debugPrint('Error fetching company attendance times: $e');
    }
  }

  Future<void> _fetchEmployeeNames() async {
    try {
      final querySnapshot = await _firestore
          .collection('Employee')
          .where('companyId', isEqualTo: widget.companyId)
          .get();
      final Map<String, String> names = {};
      for (var doc in querySnapshot.docs) {
        names[doc.id] = doc.data()['name'] ?? 'Unknown Employee';
      }
      if (mounted) {
        setState(() {
          _employeeNames = names;
        });
      }
    } catch (e) {
      print("Error fetching employee names: $e");
    }
  }

  void _onItemTapped(int index) async {
    if (!mounted) return;
    if (index == 0) {
      _mainPageController?.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
      if (mounted) {
        setState(() {
          _selectedIndex = index;
        });
      }
    } else {
      _mainPageController?.jumpToPage(0);
      if (mounted) {
        setState(() {
          _selectedIndex = 0;
        });
      }
      if (index == 1) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ManageEmployee(companyId: widget.companyId),
          ),
        );
      } else if (index == 2) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HistoryPageAdmin(companyId: widget.companyId),
          ),
        );
      } else if (index == 3) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileCompany(companyId: widget.companyId),
          ),
        );
        _loadCompanyData();
        _loadAdminDisplayName();
        _fetchCompanyAttendanceTimes();
      }
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }

  String _formatDay(DateTime dt) {
    final weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final weekday = weekdays[dt.weekday - 1];
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    final month = months[dt.month - 1];
    return '$weekday, ${dt.day} $month ${dt.year}';
  }

  Widget _buildPremiumPlanCard(BuildContext context, String title, String price,
      String description, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            price,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileCompany(companyId: widget.companyId),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 143, 83, 167),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text('Apply Now', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime startOfToday = DateTime(now.year, now.month, now.day);
    final DateTime endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'F a c e I n',
          style: TextStyle(
            color: Colors.purple,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
        actions: const [],
      ),
      body: _mainPageController != null
          ? PageView(
              controller: _mainPageController,
              onPageChanged: (index) {
                _onItemTapped(index);
              },
              children: [
                RefreshIndicator(
                  onRefresh: () async {
                    _loadCompanyData();
                    _fetchEmployeeNames();
                    _loadAdminProfileData();
                    _loadAdminDisplayName();
                    _fetchCompanyAttendanceTimes();
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildWelcomeBox(),
                          const SizedBox(height: 16),
                          _buildCurrentTimeCard(),
                          const SizedBox(height: 20),
                          _buildMonetizationBox(context),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(_premiumPlans.length, (index) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                                height: 8.0,
                                width: _currentMonetizationPageIndex == index ? 24.0 : 8.0,
                                decoration: BoxDecoration(
                                  color: _currentMonetizationPageIndex == index
                                      ? Colors.blue.shade700
                                      : Colors.grey.shade400,
                                  borderRadius: BorderRadius.circular(4.0),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Recent Activity',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                          const SizedBox(height: 8),
                          StreamBuilder<QuerySnapshot>(
                            stream: _firestore
                                .collection('PunchLogs')
                                .doc(widget.companyId)
                                .collection('Records')
                                .where('timestamp', isGreaterThanOrEqualTo: startOfToday)
                                .where('timestamp', isLessThanOrEqualTo: endOfToday)
                                .orderBy('timestamp', descending: true)
                                .limit(10)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                                return const Card(
                                  child: ListTile(
                                    leading: Icon(Icons.info_outline, color: Colors.grey),
                                    title: Text('No important recent activity for today.'),
                                  ),
                                );
                              }
                              final importantActivities = snapshot.data!.docs.where((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final String latenessMessage = data['latenessMessage'] ?? '';
                                final String remark = data['remark'] ?? '';
                                final Timestamp timestamp = data['timestamp'] as Timestamp;
                                final DateTime punchTime = timestamp.toDate();
                                return latenessMessage.isNotEmpty ||
                                    remark.isNotEmpty ||
                                    _isLate(punchTime) ||
                                    _isEarly(punchTime);
                              }).toList();
                              if (importantActivities.isEmpty) {
                                return const Card(
                                  child: ListTile(
                                    leading: Icon(Icons.info_outline, color: Colors.grey),
                                    title: Text('No important recent activity for today.'),
                                  ),
                                );
                              }
                              return ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: importantActivities.length,
                                itemBuilder: (context, index) {
                                  final activityDoc = importantActivities[index];
                                  final data = activityDoc.data() as Map<String, dynamic>;
                                  final String employeeName = data['employeeName'] ?? 'Unknown Employee';
                                  final Timestamp timestamp = data['timestamp'] as Timestamp;
                                  final String type = data['type'] ?? 'Activity';
                                  final String latenessMessage = data['latenessMessage'] ?? '';
                                  final String remark = data['remark'] ?? '';
                                  final DateTime punchTime = timestamp.toDate();
                                  IconData icon;
                                  Color iconColor;
                                  String activityTitle;
                                  String activitySubtitle;
                                  if (latenessMessage.isNotEmpty || remark.isNotEmpty) {
                                    icon = Icons.warning_amber;
                                    iconColor = Colors.orange;
                                    activityTitle = '$employeeName $type';
                                    activitySubtitle = 'At ${_formatTime(punchTime)} ${latenessMessage.trim()}';
                                    if (remark.isNotEmpty) {
                                      activitySubtitle += '\nRemark: "$remark"';
                                    }
                                  } else if (_isLate(punchTime)) {
                                    icon = Icons.warning_amber;
                                    iconColor = Colors.orange;
                                    activityTitle = '$employeeName clocked in late';
                                    activitySubtitle = 'At ${_formatTime(punchTime)} (late)';
                                    if (remark.isNotEmpty) {
                                      activitySubtitle += '\nRemark: "$remark"';
                                    }
                                  } else if (_isEarly(punchTime)) {
                                    icon = Icons.warning_amber;
                                    iconColor = Colors.orange;
                                    activityTitle = '$employeeName clocked out early';
                                    activitySubtitle = 'At ${_formatTime(punchTime)} (early)';
                                    if (remark.isNotEmpty) {
                                      activitySubtitle += '\nRemark: "$remark"';
                                    }
                                  } else {
                                    icon = Icons.info_outline;
                                    iconColor = Colors.blueGrey;
                                    activityTitle = '$employeeName $type';
                                    activitySubtitle = 'At ${_formatTime(punchTime)}';
                                    if (remark.isNotEmpty) {
                                      activitySubtitle += '\nRemark: "$remark"';
                                    }
                                  }
                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 6),
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                    color: Colors.white,
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: iconColor.withOpacity(0.1),
                                        child: Icon(icon, color: iconColor),
                                      ),
                                      title: Text(
                                        activityTitle,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(activitySubtitle),
                                          Text(
                                            _formatDay(punchTime),
                                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                      onTap: () {},
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(),
                Container(),
                Container(),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        onTap: _onItemTapped,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.white,
        backgroundColor: const Color.fromARGB(255, 143, 83, 167),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Manage Users'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildWelcomeBox() {
    final DateTime now = DateTime.now();
    String greeting;
    List<Color> gradientColors = [
      Colors.yellow.withOpacity(0.8),
      const Color.fromARGB(255, 143, 83, 167),
    ];
    Color textColor = Colors.white;
    if (now.hour >= 5 && now.hour < 12) {
      greeting = 'Good Morning,';
    } else if (now.hour >= 12 && now.hour < 18) {
      greeting = 'Good Afternoon,';
    } else {
      greeting = 'Good Evening,';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white.withOpacity(0.8),
            backgroundImage: _adminProfilePictureUrl != null &&
                    _adminProfilePictureUrl!.isNotEmpty
                ? NetworkImage(_adminProfilePictureUrl!)
                : null,
            child: _adminProfilePictureUrl == null ||
                    _adminProfilePictureUrl!.isEmpty
                ? Icon(Icons.business, size: 40, color: gradientColors.last)
                : null,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: TextStyle(
                    color: textColor.withOpacity(0.8),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  companyName ?? 'Your Company',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (_adminJobTitle != null && _adminJobTitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      _adminJobTitle!,
                      style: TextStyle(
                        color: textColor.withOpacity(0.7),
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTimeCard() {
    final DateTime now = DateTime.now();
    const String currentLocation = 'Company Main Office';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        image: const DecorationImage(
          image: AssetImage('assets/map_background.jpg'),
          fit: BoxFit.cover,
          opacity: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.access_time,
                        color: Colors.blue.shade700, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text('Current Status',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800])),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Active',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEE, MMM dd,yyyy').format(now),
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                DateFormat('hh:mm').format(now),
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[900]),
              ),
              const SizedBox(width: 4),
              Text(
                DateFormat('a').format(now),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    color: Colors.grey[700]),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Colors.blueGrey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  currentLocation,
                  style: TextStyle(color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonetizationBox(BuildContext context) {
    // Fixed height for all boxes
    const double boxHeight = 260.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: boxHeight,
        width: double.infinity,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: PageView.builder(
            controller: _premiumPlanPageController,
            itemCount: _premiumPlans.length,
            onPageChanged: (index) {
              if (mounted) {
                setState(() {
                  _currentMonetizationPageIndex = index;
                });
              }
            },
            itemBuilder: (context, index) {
              final plan = _premiumPlans[index];
              return Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(plan['icon'], color: plan['color'], size: 24),
                        const SizedBox(width: 8),
                        Text(
                          plan['title'],
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: plan['color'],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      plan['price'],
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plan['description'],
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfileCompany(companyId: widget.companyId),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 143, 83, 167),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        child: const Text('Apply Now', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  bool _isLate(DateTime punchTime) {
    if (_companyCheckInTime == null || _companyCheckInTime!.isEmpty) {
      return false;
    }
    try {
      final parts = _companyCheckInTime!.split(':');
      final int officialHour = int.parse(parts[0]);
      final int officialMinute = int.parse(parts[1]);
      final officialTimeToday = DateTime(punchTime.year, punchTime.month,
          punchTime.day, officialHour, officialMinute);
      return punchTime
          .isAfter(officialTimeToday.add(const Duration(minutes: 5)));
    } catch (e) {
      debugPrint('Error parsing company check-in time for lateness check: $e');
      return false;
    }
  }

  bool _isEarly(DateTime punchTime) {
    if (_companyCheckOutTime == null || _companyCheckOutTime!.isEmpty) {
      return false;
    }
    try {
      final parts = _companyCheckOutTime!.split(':');
      final int officialHour = int.parse(parts[0]);
      final int officialMinute = int.parse(parts[1]);
      final officialTimeToday = DateTime(punchTime.year, punchTime.month,
          punchTime.day, officialHour, officialMinute);
      return punchTime
          .isBefore(officialTimeToday.subtract(const Duration(minutes: 15)));
    } catch (e) {
      debugPrint('Error parsing company check-out time for early check: $e');
      return false;
    }
  }
}