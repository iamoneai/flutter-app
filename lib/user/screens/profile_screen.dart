import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        setState(() {
          _userData = doc.data();
        });
      }

      // Load stats
      await _loadStats(user.uid);
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats(String userId) async {
    try {
      // Get memories count
      final memoriesSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('memories')
          .count()
          .get();

      // Get chat history count (if you have a chat_history collection)
      final chatsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('chat_history')
          .count()
          .get();

      setState(() {
        _stats = {
          'memories': memoriesSnap.count ?? 0,
          'conversations': chatsSnap.count ?? 0,
        };
      });
    } catch (e) {
      setState(() {
        _stats = {'memories': 0, 'conversations': 0};
      });
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Colors.grey),
        ),
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

  void _copyIIN() {
    final iin = _userData?['iin'] as String?;
    if (iin != null) {
      Clipboard.setData(ClipboardData(text: iin));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('IIN copied to clipboard'),
          backgroundColor: Color(0xFF00d9ff),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00d9ff)),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    final displayName = _userData?['displayName'] ?? _userData?['firstName'] ?? user?.displayName ?? 'User';
    final email = _userData?['email'] ?? user?.email ?? 'No email';
    final iin = _userData?['iin'] as String? ?? 'Not set';
    final createdAt = _userData?['createdAt'] as Timestamp?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Profile card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a2e),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2a2a3e)),
            ),
            child: Column(
              children: [
                // Avatar
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00d9ff), width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFF00d9ff).withValues(alpha: 0.2),
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? Text(
                            displayName[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00d9ff),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: TextStyle(color: Colors.grey[500]),
                ),
                const SizedBox(height: 16),
                // IIN Badge
                GestureDetector(
                  onTap: _copyIIN,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00d9ff).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF00d9ff).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fingerprint, color: Color(0xFF00d9ff), size: 20),
                        const SizedBox(width: 10),
                        Text(
                          _formatIIN(iin),
                          style: const TextStyle(
                            color: Color(0xFF00d9ff),
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.copy, color: Colors.grey[600], size: 16),
                      ],
                    ),
                  ),
                ),
                if (createdAt != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Member since ${_formatDate(createdAt.toDate())}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stats cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Memories',
                  '${_stats?['memories'] ?? 0}',
                  Icons.memory,
                  Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Conversations',
                  '${_stats?['conversations'] ?? 0}',
                  Icons.chat_bubble_outline,
                  Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Settings section
          _buildSectionTitle('Settings'),
          const SizedBox(height: 12),
          _buildSettingsTile(
            icon: Icons.person_outline,
            title: 'Edit Profile',
            subtitle: 'Update your name and preferences',
            onTap: () => _showEditProfileDialog(),
          ),
          _buildSettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Manage notification preferences',
            onTap: () {},
          ),
          _buildSettingsTile(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Theme and display settings',
            onTap: () {},
          ),
          _buildSettingsTile(
            icon: Icons.security_outlined,
            title: 'Privacy & Security',
            subtitle: 'Control your data',
            onTap: () {},
          ),
          const SizedBox(height: 24),

          // Danger zone
          _buildSectionTitle('Account'),
          const SizedBox(height: 12),
          _buildSettingsTile(
            icon: Icons.logout,
            title: 'Sign Out',
            subtitle: 'Sign out of your account',
            iconColor: Colors.orange,
            onTap: _signOut,
          ),
          _buildSettingsTile(
            icon: Icons.delete_forever,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account and data',
            iconColor: Colors.red,
            onTap: () => _showDeleteAccountDialog(),
          ),
          const SizedBox(height: 32),

          // App info
          Text(
            'IAMONEAI v1.0.0',
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Your brain. Your rules. Your guardian.',
            style: TextStyle(color: Colors.grey[800], fontSize: 10),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2a2a3e)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2a2a3e)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor ?? const Color(0xFF00d9ff)).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor ?? const Color(0xFF00d9ff), size: 20),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: Icon(Icons.chevron_right, color: Colors.grey[700]),
        onTap: onTap,
      ),
    );
  }

  String _formatIIN(String iin) {
    if (iin.length != 12) return iin;
    return '${iin.substring(0, 4)}-${iin.substring(4, 8)}-${iin.substring(8)}';
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.year}';
  }

  void _showEditProfileDialog() {
    final firstNameCtrl = TextEditingController(text: _userData?['firstName'] ?? '');
    final lastNameCtrl = TextEditingController(text: _userData?['lastName'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstNameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'First Name',
                labelStyle: TextStyle(color: Colors.grey[500]),
                filled: true,
                fillColor: const Color(0xFF0a0a0f),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2a2a3e)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: lastNameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Last Name',
                labelStyle: TextStyle(color: Colors.grey[500]),
                filled: true,
                fillColor: const Color(0xFF0a0a0f),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2a2a3e)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;

              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .update({
                'firstName': firstNameCtrl.text.trim(),
                'lastName': lastNameCtrl.text.trim(),
                'displayName': '${firstNameCtrl.text.trim()} ${lastNameCtrl.text.trim()}'.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              });

              if (ctx.mounted) Navigator.pop(ctx);
              _loadUserData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00d9ff),
              foregroundColor: Colors.black,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red[400]),
            const SizedBox(width: 8),
            const Text('Delete Account', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will permanently delete your account and all your data including memories and chat history. This action cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: Implement account deletion
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please contact support to delete your account'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
  }
}
