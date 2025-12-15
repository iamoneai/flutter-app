import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'user_chat_screen.dart';
import 'memories_screen.dart';
import 'profile_screen.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  int _currentIndex = 0;
  String? _userName;
  String? _userIIN;

  final List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _screens.addAll([
      const UserChatScreen(),
      const MemoriesScreen(),
      const ProfileScreen(),
    ]);
  }

  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        setState(() {
          _userName = doc.data()?['firstName'] ?? doc.data()?['displayName'] ?? 'User';
          _userIIN = doc.data()?['iin'];
        });
      }
    } catch (e) {
      debugPrint('Error loading user info: $e');
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a2e),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.psychology, color: Color(0xFF00d9ff), size: 28),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'IAMONEAI',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (_userName != null)
                  Text(
                    'Hello, $_userName',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          if (_userIIN != null)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00d9ff).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00d9ff).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fingerprint, size: 14, color: Color(0xFF00d9ff)),
                  const SizedBox(width: 4),
                  Text(
                    _formatIIN(_userIIN!),
                    style: const TextStyle(
                      color: Color(0xFF00d9ff),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF00d9ff).withValues(alpha: 0.2),
              child: Text(
                (_userName ?? 'U')[0].toUpperCase(),
                style: const TextStyle(color: Color(0xFF00d9ff), fontWeight: FontWeight.bold),
              ),
            ),
            color: const Color(0xFF1a1a2e),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, color: Colors.grey[400], size: 20),
                    const SizedBox(width: 12),
                    const Text('Profile', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, color: Colors.grey[400], size: 20),
                    const SizedBox(width: 12),
                    const Text('Settings', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red[400], size: 20),
                    const SizedBox(width: 12),
                    Text('Sign Out', style: TextStyle(color: Colors.red[400])),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'profile') {
                setState(() => _currentIndex = 2);
              } else if (value == 'settings') {
                Navigator.pushNamed(context, '/user/settings');
              } else if (value == 'signout') {
                _signOut();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a2e),
          border: Border(
            top: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF00d9ff),
          unselectedItemColor: Colors.grey[600],
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.memory_outlined),
              activeIcon: Icon(Icons.memory),
              label: 'Memories',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  String _formatIIN(String iin) {
    if (iin.length != 12) return iin;
    return '${iin.substring(0, 4)}-${iin.substring(4, 8)}-${iin.substring(8)}';
  }
}
