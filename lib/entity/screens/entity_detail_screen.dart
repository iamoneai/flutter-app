import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/entity_service.dart';
import '../../core/services/session_service.dart';
import '../../core/models/entity.dart';
import '../../core/models/entity_employee.dart';

/// Entity Detail Screen - View and manage entity details
class EntityDetailScreen extends StatefulWidget {
  final String entityId;
  final IINContext context;

  const EntityDetailScreen({
    super.key,
    required this.entityId,
    required this.context,
  });

  @override
  State<EntityDetailScreen> createState() => _EntityDetailScreenState();
}

class _EntityDetailScreenState extends State<EntityDetailScreen> {
  final EntityService _entityService = EntityService();

  Entity? _entity;
  List<EntityEmployee> _employees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final entity = await _entityService.getEntity(widget.entityId);
      final employees = await _entityService.getEntityEmployees(widget.entityId);

      setState(() {
        _entity = entity;
        _employees = employees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _inviteEmployee() async {
    final emailController = TextEditingController();
    String selectedRole = 'member';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          title: const Text('Invite Employee'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedRole,
                dropdownColor: const Color(0xFF1a1a2e),
                decoration: InputDecoration(
                  labelText: 'Role',
                  labelStyle: TextStyle(color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'member', child: Text('Member')),
                  DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                ],
                onChanged: (value) {
                  setDialogState(() => selectedRole = value!);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  'email': emailController.text.trim(),
                  'role': selectedRole,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00d9ff),
                foregroundColor: Colors.black,
              ),
              child: const Text('Invite'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['email']!.isNotEmpty) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        await _entityService.inviteEmployee(
          entityId: widget.entityId,
          email: result['email']!,
          invitedByUid: user.uid,
          role: result['role']!,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invitation sent to ${result['email']}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error sending invitation: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0f),
        title: Text(_entity?.name ?? 'Entity Details'),
        actions: [
          if (widget.context.hasAdminAccess)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                // TODO: Edit entity
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      floatingActionButton: widget.context.hasAdminAccess
          ? FloatingActionButton.extended(
              onPressed: _inviteEmployee,
              backgroundColor: const Color(0xFF00d9ff),
              foregroundColor: Colors.black,
              icon: const Icon(Icons.person_add),
              label: const Text('Invite'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_entity == null) {
      return const Center(child: Text('Entity not found'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Entity Info Card
          _buildEntityInfoCard(),
          const SizedBox(height: 24),

          // IIN Info
          _buildIINCard(),
          const SizedBox(height: 24),

          // Employees Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TEAM MEMBERS (${_employees.length})',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  letterSpacing: 1,
                ),
              ),
              if (widget.context.hasAdminAccess)
                TextButton.icon(
                  onPressed: _inviteEmployee,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00d9ff),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_employees.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 12),
                  Text(
                    'No team members yet',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ],
              ),
            )
          else
            ...(_employees.map(_buildEmployeeCard).toList()),
        ],
      ),
    );
  }

  Widget _buildEntityInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00d9ff).withOpacity(0.1),
            Colors.transparent,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00d9ff).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF00d9ff).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.business,
                  color: Color(0xFF00d9ff),
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _entity!.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _entity!.isActive
                            ? Colors.green.withOpacity(0.2)
                            : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _entity!.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: _entity!.isActive ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_entity!.description != null && _entity!.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              _entity!.description!,
              style: TextStyle(color: Colors.grey[400]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIINCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ENTITY IIN',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.fingerprint, color: Color(0xFF00d9ff)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _entity!.brainIinId ?? 'N/A',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                color: Colors.grey,
                onPressed: () {
                  // Copy to clipboard
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your Role: ${widget.context.role.toUpperCase()}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(EntityEmployee employee) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF00d9ff).withOpacity(0.2),
            child: Icon(
              employee.isAdmin ? Icons.admin_panel_settings : Icons.person,
              color: const Color(0xFF00d9ff),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.uid,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  employee.role.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          Text(
            employee.employeeIinId.split('-').last,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: Colors.grey[500],
            ),
          ),
          if (widget.context.hasAdminAccess) ...[
            const SizedBox(width: 8),
            PopupMenuButton(
              icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 18),
              color: const Color(0xFF1a1a2e),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'role',
                  child: Text('Change Role'),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove', style: TextStyle(color: Colors.red)),
                ),
              ],
              onSelected: (value) async {
                if (value == 'remove') {
                  await _entityService.removeEmployee(widget.entityId, employee.uid);
                  _loadData();
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
