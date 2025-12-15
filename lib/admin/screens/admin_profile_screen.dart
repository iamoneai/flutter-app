import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _iinController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _currentIIN;
  String? _linkedUserName;
  Map<String, dynamic>? _adminData;

  @override
  void initState() {
    super.initState();
    _loadAdminProfile();
  }

  @override
  void dispose() {
    _iinController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Load admin profile
      final adminDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (adminDoc.exists) {
        final data = adminDoc.data()!;
        setState(() {
          _adminData = data;
          _currentIIN = data['iin'];
          _iinController.text = _currentIIN ?? '';
        });

        // If IIN exists, load linked user info
        if (_currentIIN != null && _currentIIN!.isNotEmpty) {
          await _loadLinkedUser(_currentIIN!);
        }
      }
    } catch (e) {
      debugPrint('Error loading admin profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLinkedUser(String iin) async {
    try {
      final userQuery = await _firestore
          .collection('users')
          .where('iin', isEqualTo: iin)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        final userData = userQuery.docs.first.data();
        setState(() {
          _linkedUserName = userData['displayName'] ?? 'Unknown';
        });
      }
    } catch (e) {
      debugPrint('Error loading linked user: $e');
    }
  }

  Future<void> _validateAndSaveIIN() async {
    if (!_formKey.currentState!.validate()) return;

    final iin = _iinController.text.trim().toUpperCase();
    
    setState(() => _isSaving = true);

    try {
      // Validate IIN format (XXXX-XXXX-XXXX-XXXX)
      final iinRegex = RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$');
      if (!iinRegex.hasMatch(iin)) {
        _showError('Invalid IIN format. Expected: XXXX-XXXX-XXXX-XXXX');
        return;
      }

      // Check if IIN exists in users collection
      final userQuery = await _firestore
          .collection('users')
          .where('iin', isEqualTo: iin)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        _showError('IIN not found. Please register as a user first to get your IIN.');
        return;
      }

      final userData = userQuery.docs.first.data();
      final userName = userData['displayName'] ?? 'Unknown';

      // Confirm linking
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm IIN Link'),
          content: Text(
            'Link your admin account to:\n\n'
            'Name: $userName\n'
            'IIN: $iin\n\n'
            'This will allow you to use the chat interface with your personal memories.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Link IIN'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Save IIN to admin profile
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore.collection('users').doc(user.uid).update({
        'iin': iin,
        'iinLinkedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _currentIIN = iin;
        _linkedUserName = userName;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully linked to $userName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Error saving IIN: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _unlinkIIN() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlink IIN'),
        content: const Text(
          'Are you sure you want to unlink your IIN?\n\n'
          'You will no longer be able to use the chat interface until you link a new IIN.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore.collection('users').doc(user.uid).update({
        'iin': FieldValue.delete(),
        'iinLinkedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _currentIIN = null;
        _linkedUserName = null;
        _iinController.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('IIN unlinked successfully')),
        );
      }
    } catch (e) {
      _showError('Error unlinking IIN: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0f0f1a),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF7c3aed))),
      );
    }

    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Admin Info Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1a1a2e),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: const Color(0xFF7c3aed),
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? Text(
                            user?.email?.substring(0, 1).toUpperCase() ?? '?',
                            style: const TextStyle(fontSize: 32, color: Colors.white),
                          )
                        : null,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? user?.email ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? '',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 8),
                        if (_adminData != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7c3aed).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              (_adminData!['role'] ?? 'viewer')
                                  .toString()
                                  .replaceAll('_', ' ')
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF7c3aed),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // IIN Section
            const Text(
              'Personal IIN',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Link your personal IAMONEAI Identity Number (IIN) to use the chat interface with your own memories.',
              style: TextStyle(color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),

            if (_currentIIN != null && _currentIIN!.isNotEmpty) ...[
              // Linked IIN Display
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[400]),
                        const SizedBox(width: 8),
                        Text(
                          'IIN Linked',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[400],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('IIN: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        SelectableText(
                          _currentIIN!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            color: Color(0xFF7c3aed),
                          ),
                        ),
                      ],
                    ),
                    if (_linkedUserName != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('User: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          Text(_linkedUserName!, style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _unlinkIIN,
                      icon: const Icon(Icons.link_off, size: 18),
                      label: const Text('Unlink IIN'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[400],
                        side: BorderSide(color: Colors.red[400]!),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // IIN Input Form
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Text(
                          'No IIN Linked',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You need to link your IIN to use the chat interface.',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _iinController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Enter your IIN',
                              labelStyle: TextStyle(color: Colors.grey[500]),
                              hintText: 'XXXX-XXXX-XXXX-XXXX',
                              hintStyle: TextStyle(color: Colors.grey[600]),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: const Color(0xFF1a1a2e),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF7c3aed)),
                              ),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your IIN';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isSaving ? null : _validateAndSaveIIN,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.link),
                              label: Text(_isSaving ? 'Validating...' : 'Link IIN'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7c3aed),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.all(16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Divider(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    Text(
                      "Don't have an IIN yet?",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Register as a user at the main app to get your personal IIN, then come back here to link it.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
