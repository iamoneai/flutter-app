import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  String _searchQuery = '';
  String _statusFilter = 'all';

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    return DateFormat('MMM d, yyyy\nh:mm a').format(timestamp.toDate());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.people, color: Color(0xFF7c3aed), size: 32),
                const SizedBox(width: 12),
                const Text(
                  'Registered Users',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'View and manage all registered IAMONEAI users',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),

            // Filters Row
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search by name, email, or IIN...',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
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
                    onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _statusFilter,
                      dropdownColor: const Color(0xFF1a1a2e),
                      style: const TextStyle(color: Colors.white),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Status')),
                        DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                        DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
                        DropdownMenuItem(value: 'SUSPENDED', child: Text('Suspended')),
                      ],
                      onChanged: (value) => setState(() => _statusFilter = value!),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Users List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  var users = snapshot.data!.docs;

                  // Apply filters
                  if (_searchQuery.isNotEmpty) {
                    users = users.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = (data['displayName'] ?? '').toString().toLowerCase();
                      final email = (data['email'] ?? '').toString().toLowerCase();
                      final iin = (data['iin'] ?? '').toString().toLowerCase();
                      return name.contains(_searchQuery) ||
                          email.contains(_searchQuery) ||
                          iin.contains(_searchQuery);
                    }).toList();
                  }

                  if (_statusFilter != 'all') {
                    users = users.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['status'] == _statusFilter;
                    }).toList();
                  }

                  if (users.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_off, size: 64, color: Colors.grey[600]),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No users match your search'
                                : 'No registered users yet',
                            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1a1a2e),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        // Table Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0f0f1a),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: Row(
                            children: [
                              _buildHeaderCell('User', flex: 3),
                              _buildHeaderCell('IIN', flex: 2),
                              _buildHeaderCell('Role', flex: 1),
                              _buildHeaderCell('Status', flex: 1),
                              _buildHeaderCell('Registered', flex: 2),
                              _buildHeaderCell('Actions', flex: 1),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
                        // Table Body
                        Expanded(
                          child: ListView.separated(
                            itemCount: users.length,
                            separatorBuilder: (context, index) => Divider(height: 1, color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
                            itemBuilder: (context, index) {
                              final doc = users[index];
                              final data = doc.data() as Map<String, dynamic>;
                              return _buildUserRow(doc.id, data);
                            },
                          ),
                        ),
                        // Footer
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0f0f1a),
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${users.length} user${users.length == 1 ? '' : 's'}',
                                style: TextStyle(color: Colors.grey[400]),
                              ),
                              Text(
                                'Total: ${snapshot.data!.docs.length}',
                                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.grey[400],
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildUserRow(String docId, Map<String, dynamic> data) {
    final displayName = data['displayName'] as String? ?? 'Unknown';
    final email = data['email'] as String? ?? '';
    final iin = data['iin'] as String? ?? 'N/A';
    final status = data['status'] as String? ?? 'UNKNOWN';
    final role = data['role'] as String? ?? 'user';
    final createdAt = data['createdAt'] as Timestamp?;
    final firstName = data['firstName'] as String? ?? '';

    final formattedDate = _formatDate(createdAt);

    Color statusColor;
    switch (status) {
      case 'ACTIVE':
        statusColor = Colors.green;
        break;
      case 'INACTIVE':
        statusColor = Colors.orange;
        break;
      case 'SUSPENDED':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    Color roleColor;
    switch (role) {
      case 'super_admin':
        roleColor = const Color(0xFF7c3aed);
        break;
      case 'admin':
        roleColor = const Color(0xFF6366f1);
        break;
      case 'prompt_editor':
      case 'config_editor':
        roleColor = Colors.blue;
        break;
      case 'viewer':
        roleColor = Colors.grey;
        break;
      default:
        roleColor = const Color(0xFF7c3aed);
    }

    return InkWell(
      onTap: () => _showUserDetails(docId, data),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // User info
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF7c3aed).withValues(alpha: 0.2),
                    child: Text(
                      (firstName.isNotEmpty ? firstName[0] : displayName[0]).toUpperCase(),
                      style: const TextStyle(color: Color(0xFF7c3aed), fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          email,
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // IIN
            Expanded(
              flex: 2,
              child: SelectableText(
                iin,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF7c3aed),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Role
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  role.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: roleColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // Status
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // Created date
            Expanded(
              flex: 2,
              child: Text(
                formattedDate,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ),
            // Actions
            Expanded(
              flex: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => _showUserDetails(docId, data),
                    icon: const Icon(Icons.visibility, size: 20),
                    tooltip: 'View Details',
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserDetails(String docId, Map<String, dynamic> data) {
    final createdAt = data['createdAt'] as Timestamp?;
    final role = data['role'] as String? ?? 'user';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person, color: Colors.teal[700]),
            const SizedBox(width: 8),
            Expanded(child: Text(data['displayName'] as String? ?? 'User Details')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                role.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(
                  color: Colors.purple[700],
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Firebase UID', docId),
              _buildDetailRow('IIN', data['iin'] as String? ?? 'N/A'),
              _buildDetailRow('Email', data['email'] as String? ?? 'N/A'),
              _buildDetailRow('First Name', data['firstName'] as String? ?? 'N/A'),
              _buildDetailRow('Last Name', data['lastName'] as String? ?? 'N/A'),
              _buildDetailRow('Role', role.replaceAll('_', ' ').toUpperCase()),
              _buildDetailRow('Status', data['status'] as String? ?? 'N/A'),
              _buildDetailRow('Registered', _formatDate(createdAt)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (data['status'] == 'ACTIVE')
            TextButton(
              onPressed: () => _updateUserStatus(docId, 'SUSPENDED'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Suspend User'),
            ),
          if (data['status'] == 'SUSPENDED')
            TextButton(
              onPressed: () => _updateUserStatus(docId, 'ACTIVE'),
              style: TextButton.styleFrom(foregroundColor: Colors.green),
              child: const Text('Activate User'),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateUserStatus(String docId, String newStatus) async {
    Navigator.pop(context);
    try {
      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User status updated to $newStatus')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e')),
        );
      }
    }
  }
}