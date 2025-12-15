import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/session_service.dart';
import '../../core/services/entity_service.dart';
import '../../core/models/entity.dart';
import 'entity_create_screen.dart';
import 'entity_detail_screen.dart';

/// Entity Dashboard - Main screen for entity management
class EntityDashboard extends StatefulWidget {
  const EntityDashboard({super.key});

  @override
  State<EntityDashboard> createState() => _EntityDashboardState();
}

class _EntityDashboardState extends State<EntityDashboard> {
  final SessionService _sessionService = SessionService();
  final EntityService _entityService = EntityService();

  List<IINContext> _contexts = [];
  IINContext? _activeContext;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final contexts = await _sessionService.getUserIINContexts(user.uid);
      final activeContext = await _sessionService.getActiveIINContext(user.uid);

      // Filter to only entity contexts
      final entityContexts = contexts.where((c) => !c.isPersonal).toList();

      setState(() {
        _contexts = entityContexts;
        _activeContext = activeContext?.isPersonal == true ? null : activeContext;
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

  Future<void> _switchContext(IINContext iinContext) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _sessionService.setActiveIIN(user.uid, iinContext.iin.iinId);
      setState(() => _activeContext = iinContext);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error switching context: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0f),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0a0a0f),
        title: Row(
          children: [
            const Icon(Icons.business, color: Color(0xFF00d9ff)),
            const SizedBox(width: 12),
            const Text('Entity Dashboard'),
          ],
        ),
        actions: [
          // Context Switcher
          if (_contexts.isNotEmpty)
            PopupMenuButton<IINContext>(
              icon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00d9ff).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00d9ff).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _activeContext?.isEntityBrain == true
                          ? Icons.admin_panel_settings
                          : Icons.person,
                      size: 16,
                      color: const Color(0xFF00d9ff),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _activeContext?.displayName ?? 'Select Entity',
                      style: const TextStyle(
                        color: Color(0xFF00d9ff),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, color: Color(0xFF00d9ff), size: 16),
                  ],
                ),
              ),
              itemBuilder: (context) => _contexts.map((ctx) {
                return PopupMenuItem(
                  value: ctx,
                  child: Row(
                    children: [
                      Icon(
                        ctx.isEntityBrain ? Icons.admin_panel_settings : Icons.person,
                        size: 18,
                        color: ctx.iin.iinId == _activeContext?.iin.iinId
                            ? const Color(0xFF00d9ff)
                            : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ctx.displayName,
                              style: TextStyle(
                                fontWeight: ctx.iin.iinId == _activeContext?.iin.iinId
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            Text(
                              ctx.role.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (ctx.iin.iinId == _activeContext?.iin.iinId)
                        const Icon(Icons.check, color: Color(0xFF00d9ff), size: 18),
                    ],
                  ),
                );
              }).toList(),
              onSelected: _switchContext,
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EntityCreateScreen()),
          );
          if (result == true) {
            _loadData();
          }
        },
        backgroundColor: const Color(0xFF00d9ff),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Create Entity'),
      ),
    );
  }

  Widget _buildBody() {
    if (_contexts.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active Entity Card
          if (_activeContext != null) ...[
            Text(
              'ACTIVE ENTITY',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            _buildActiveEntityCard(_activeContext!),
            const SizedBox(height: 24),
          ],

          // All Entities
          Text(
            'YOUR ENTITIES',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          ...(_contexts.map((ctx) => _buildEntityCard(ctx)).toList()),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business_outlined,
            size: 80,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 24),
          Text(
            'No Entities Yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first entity or wait for an invitation',
            style: TextStyle(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EntityCreateScreen()),
              );
              if (result == true) {
                _loadData();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Create Entity'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00d9ff),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveEntityCard(IINContext ctx) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00d9ff).withOpacity(0.2),
            const Color(0xFF00d9ff).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00d9ff).withOpacity(0.3)),
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
                child: Icon(
                  ctx.isEntityBrain ? Icons.admin_panel_settings : Icons.person,
                  color: const Color(0xFF00d9ff),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ctx.entityName ?? ctx.displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Role: ${ctx.role.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EntityDetailScreen(
                        entityId: ctx.iin.ownerId,
                        context: ctx,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00d9ff),
                  foregroundColor: Colors.black,
                ),
                child: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.fingerprint, size: 16, color: Color(0xFF00d9ff)),
                const SizedBox(width: 8),
                Text(
                  'IIN: ${ctx.iin.iinId}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntityCard(IINContext ctx) {
    final isActive = ctx.iin.iinId == _activeContext?.iin.iinId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _switchContext(ctx),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF00d9ff).withOpacity(0.1)
                  : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF00d9ff).withOpacity(0.3)
                    : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  ctx.isEntityBrain ? Icons.admin_panel_settings : Icons.person,
                  color: isActive ? const Color(0xFF00d9ff) : Colors.grey,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ctx.entityName ?? ctx.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.white : Colors.grey[300],
                        ),
                      ),
                      Text(
                        ctx.role.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00d9ff).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF00d9ff),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
