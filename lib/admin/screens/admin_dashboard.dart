import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';
import '../../core/models/admin_user.dart';
import 'login_screen.dart';
import 'api_keys_screen.dart';
import 'categories_screen.dart';
import 'global_settings_screen.dart';
import 'developer_chat_screen.dart';
import 'users_screen.dart';
import 'llm_routing_screen.dart';
import 'admin_profile_screen.dart';
import 'tech_docs_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final AuthService _authService = AuthService();
  AdminUser? _adminUser;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadAdminUser();
  }

  Future<void> _loadAdminUser() async {
    final user = _authService.currentUser;
    if (user != null) {
      final adminUser = await _authService.getAdminUser(user.uid);
      setState(() {
        _adminUser = adminUser;
      });
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final isSuperAdmin = _adminUser?.hasPermission(AdminUser.permAll) ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: const Color(0xFF1a1a2e),
            extended: MediaQuery.of(context).size.width > 800,
            selectedIndex: _selectedIndex,
            indicatorColor: const Color(0xFF7c3aed).withValues(alpha: 0.2),
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7c3aed), Color(0xFF6366f1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.psychology, color: Colors.white, size: 24),
                  ),
                  if (MediaQuery.of(context).size.width > 800)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'IAMONEAI',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.account_circle),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AdminProfileScreen(),
                            ),
                          );
                        },
                        tooltip: 'My Profile',
                      ),
                      const SizedBox(height: 8),
                      IconButton(
                        icon: const Icon(Icons.logout),
                        onPressed: _signOut,
                        tooltip: 'Sign Out',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Dashboard'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.key_outlined),
                selectedIcon: Icon(Icons.key),
                label: Text('API Keys'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.category_outlined),
                selectedIcon: Icon(Icons.category),
                label: Text('Categories'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.route_outlined),
                selectedIcon: Icon(Icons.route),
                label: Text('Routing'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.science_outlined),
                selectedIcon: Icon(Icons.science),
                label: Text('Testing'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description),
                label: Text('Tech Docs'),
              ),
              if (isSuperAdmin)
                const NavigationRailDestination(
                  icon: Icon(Icons.people_outlined),
                  selectedIcon: Icon(Icons.people),
                  label: Text('Users'),
                ),
              const NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          VerticalDivider(thickness: 1, width: 1, color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e),
                    border: Border(
                      bottom: BorderSide(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _getPageTitle(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DeveloperChatScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chat, size: 18),
                        label: const Text('My Chat'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7c3aed),
                          side: const BorderSide(color: Color(0xFF7c3aed)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (_adminUser != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getRoleColor(_adminUser!.role).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _adminUser!.role.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              color: _getRoleColor(_adminUser!.role),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AdminProfileScreen(),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFF7c3aed),
                              backgroundImage: user?.photoURL != null
                                  ? NetworkImage(user!.photoURL!)
                                  : null,
                              child: user?.photoURL == null
                                  ? Text(
                                      user?.email?.substring(0, 1).toUpperCase() ?? '?',
                                      style: const TextStyle(color: Colors.white),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              user?.displayName ?? user?.email ?? 'Unknown',
                              style: const TextStyle(color: Colors.white),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, size: 20, color: Colors.white),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildPage()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getPageTitle() {
    final isSuperAdmin = _adminUser?.hasPermission(AdminUser.permAll) ?? false;
    switch (_selectedIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'API Keys';
      case 2:
        return 'Categories';
      case 3:
        return 'LLM Routing';
      case 4:
        return 'Testing';
      case 5:
        return 'Tech Docs';
      case 6:
        return isSuperAdmin ? 'Users' : 'Global Settings';
      case 7:
        return 'Global Settings';
      default:
        return 'Dashboard';
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case AdminUser.roleSuperAdmin:
        return const Color(0xFF7c3aed);
      case AdminUser.rolePromptEditor:
        return const Color(0xFF6366f1);
      case AdminUser.roleConfigEditor:
        return Colors.orange;
      case AdminUser.roleViewer:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Widget _buildPage() {
    final isSuperAdmin = _adminUser?.hasPermission(AdminUser.permAll) ?? false;
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardPage();
      case 1:
        return const ApiKeysScreen();
      case 2:
        return const CategoriesScreen();
      case 3:
        return const LLMRoutingScreen();
      case 4:
        return _buildPlaceholder('Testing', Icons.science);
      case 5:
        return const TechDocsScreen();
      case 6:
        return isSuperAdmin ? const UsersScreen() : const GlobalSettingsScreen();
      case 7:
        return const GlobalSettingsScreen();
      default:
        return _buildDashboardPage();
    }
  }

  Widget _buildDashboardPage() {
    return Container(
      color: const Color(0xFF0f0f1a),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatCard('Users', '0', Icons.people, const Color(0xFF6366f1)),
              const SizedBox(width: 16),
              _buildStatCard('Memories', '0', Icons.psychology, const Color(0xFF7c3aed)),
              const SizedBox(width: 16),
              _buildStatCard('API Calls', '0', Icons.api, Colors.green),
              const SizedBox(width: 16),
              _buildStatCard('Errors', '0', Icons.error, Colors.red),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildActionButton(
                'Add API Key',
                Icons.key,
                () => setState(() => _selectedIndex = 1),
              ),
              _buildActionButton(
                'Configure Routing',
                Icons.route,
                () => setState(() => _selectedIndex = 3),
              ),
              _buildActionButton('My Chat', Icons.chat, () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DeveloperChatScreen(),
                  ),
                );
              }),
              _buildActionButton('My Profile', Icons.person, () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminProfileScreen(),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a2e),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2a2a3e).withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(label, style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF7c3aed),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildPlaceholder(String title, IconData icon) {
    return Container(
      color: const Color(0xFF0f0f1a),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              '$title - Coming next...',
              style: TextStyle(fontSize: 18, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
