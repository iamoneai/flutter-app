// IAMONEAI - Admin Dashboard
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_login_screen.dart';
import '../widgets/llm_status_content.dart';
import '../widgets/llm_config_content.dart';

/// Menu item data
class MenuItem {
  final String id;
  final String label;
  final IconData icon;
  final List<String> subItems;

  const MenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.subItems,
  });
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _auth = FirebaseAuth.instance;

  // Menu items (reorderable)
  List<MenuItem> _menuItems = [
    const MenuItem(
      id: 'dashboard',
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      subItems: ['Status', 'Live Status', 'Metrics'],
    ),
    const MenuItem(
      id: 'cortex_route',
      label: 'Cortex Route',
      icon: Icons.route_outlined,
      subItems: [],
    ),
    const MenuItem(
      id: 'llms_config',
      label: 'LLMs Config',
      icon: Icons.memory_outlined,
      subItems: ['Status', 'Config', 'Metrics'],
    ),
    const MenuItem(
      id: 'global_setting',
      label: 'Global Setting',
      icon: Icons.settings_outlined,
      subItems: ['Admin Settings', 'User Settings', 'Chat Settings'],
    ),
    const MenuItem(
      id: 'repository',
      label: 'Repository',
      icon: Icons.folder_outlined,
      subItems: ['Tech Doc'],
    ),
    const MenuItem(
      id: 'billing',
      label: 'Billing',
      icon: Icons.payment_outlined,
      subItems: [],
    ),
  ];

  // Selection state
  int _selectedMainIndex = 0;
  int _selectedSubIndex = -1;

  // Collapse state
  bool _isColumnACollapsed = false;
  bool _isColumnBCollapsed = false;

  // Resizable widths
  double _columnAWidth = 180;
  double _columnBWidth = 180;

  // Test windows height ratio (0.0 to 1.0)
  double _testWindowsHeightRatio = 0.35;

  // Get current sub items
  List<String> get _currentSubItems =>
      _menuItems[_selectedMainIndex].subItems;

  // Check if current selection has sub items
  bool get _hasSubItems => _currentSubItems.isNotEmpty;

  // Get current selection label
  String get _currentSelectionLabel {
    if (_selectedSubIndex >= 0 && _selectedSubIndex < _currentSubItems.length) {
      return _currentSubItems[_selectedSubIndex];
    }
    return _menuItems[_selectedMainIndex].label;
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
      );
    }
  }

  void _onMainMenuSelected(int index) {
    setState(() {
      _selectedMainIndex = index;
      _selectedSubIndex = -1; // Reset sub selection
      // Auto-expand Column B if there are sub-items
      if (_menuItems[index].subItems.isNotEmpty) {
        _isColumnBCollapsed = false;
      }
    });
  }

  void _onSubMenuSelected(int index) {
    setState(() {
      _selectedSubIndex = index;
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _menuItems.removeAt(oldIndex);
      _menuItems.insert(newIndex, item);
      // Update selected index if needed
      if (_selectedMainIndex == oldIndex) {
        _selectedMainIndex = newIndex;
      } else if (oldIndex < _selectedMainIndex && newIndex >= _selectedMainIndex) {
        _selectedMainIndex--;
      } else if (oldIndex > _selectedMainIndex && newIndex <= _selectedMainIndex) {
        _selectedMainIndex++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // Header
          _buildHeader(user),
          // Body
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Column A - Main Menu
                _buildColumnA(),
                // Resizable divider between A and B
                if (!_isColumnACollapsed && _hasSubItems && !_isColumnBCollapsed)
                  _buildVerticalDivider(
                    onDrag: (delta) {
                      setState(() {
                        _columnAWidth = (_columnAWidth + delta).clamp(120, 280);
                      });
                    },
                  ),
                // Column B - Sub Menu (only if has items and not collapsed)
                if (_hasSubItems) _buildColumnB(),
                // Right side - Future Menu, Config, Test
                Expanded(
                  child: _buildRightSide(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Header bar
  Widget _buildHeader(User? user) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo/Title
          const Icon(Icons.admin_panel_settings, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          const Text(
            'IAMONEAI Admin Dashboard',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          // User info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Welcome, ${user?.email ?? 'Admin'}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Sign out
          TextButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout, size: 20, color: Colors.white70),
            label: const Text(
              'Sign out',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  /// Vertical resizable divider
  Widget _buildVerticalDivider({required Function(double) onDrag}) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(
          width: 8,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 4,
              margin: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Column A - Main Menu (Reorderable)
  Widget _buildColumnA() {
    if (_isColumnACollapsed) {
      return _buildCollapsedColumn(
        icon: Icons.menu,
        onExpand: () => setState(() => _isColumnACollapsed = false),
      );
    }

    return Container(
      width: _columnAWidth,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE0E0E0)),
              ),
            ),
            child: const Text(
              'Main Menu',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF999999),
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Reorderable list
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _menuItems.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                final item = _menuItems[index];
                final isSelected = index == _selectedMainIndex;
                return ReorderableDragStartListener(
                  key: ValueKey(item.id),
                  index: index,
                  child: _buildMainMenuItem(
                    index: index,
                    item: item,
                    isSelected: isSelected,
                  ),
                );
              },
            ),
          ),
          // Collapse button
          _buildCollapseButton(
            onTap: () => setState(() => _isColumnACollapsed = true),
          ),
        ],
      ),
    );
  }

  Widget _buildMainMenuItem({
    required int index,
    required MenuItem item,
    required bool isSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onMainMenuSelected(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF0F0F0) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? const Color(0xFF1A1A1A) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 22,
                color: isSelected
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFF666666),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFF444444),
                  ),
                ),
              ),
              // Drag handle
              const Icon(
                Icons.drag_indicator,
                size: 18,
                color: Color(0xFFCCCCCC),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Column B - Sub Menu
  Widget _buildColumnB() {
    if (_isColumnBCollapsed) {
      return _buildCollapsedColumn(
        icon: Icons.list,
        onExpand: () => setState(() => _isColumnBCollapsed = false),
      );
    }

    return Container(
      width: _columnBWidth,
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(
          right: BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE0E0E0)),
              ),
            ),
            child: Text(
              _menuItems[_selectedMainIndex].label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF999999),
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Sub menu items (always start at top)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8),
              itemCount: _currentSubItems.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedSubIndex;
                return _buildSubMenuItem(
                  label: _currentSubItems[index],
                  isSelected: isSelected,
                  onTap: () => _onSubMenuSelected(index),
                );
              },
            ),
          ),
          // Collapse button
          _buildCollapseButton(
            onTap: () => setState(() => _isColumnBCollapsed = true),
          ),
        ],
      ),
    );
  }

  Widget _buildSubMenuItem({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE8E8E8) : Colors.transparent,
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? const Color(0xFF1A1A1A)
                      : const Color(0xFFCCCCCC),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFF444444),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Collapsed column (thin strip with expand button)
  Widget _buildCollapsedColumn({
    required IconData icon,
    required VoidCallback onExpand,
  }) {
    return Container(
      width: 40,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          IconButton(
            icon: Icon(icon, color: const Color(0xFF666666)),
            onPressed: onExpand,
            tooltip: 'Expand',
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Color(0xFF666666)),
            onPressed: onExpand,
            tooltip: 'Expand',
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Collapse button for menus
  Widget _buildCollapseButton({required VoidCallback onTap}) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFE0E0E0)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chevron_left, size: 20, color: Color(0xFF999999)),
                SizedBox(width: 4),
                Text(
                  'Collapse',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Right side - Future Menu Area, Configuration Area, Test Windows
  Widget _buildRightSide() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight - 92; // Minus future menu area
        final testWindowsHeight = totalHeight * _testWindowsHeightRatio;
        final configHeight = totalHeight - testWindowsHeight;

        return Column(
          children: [
            // Future Menu Area (placeholder)
            _buildFutureMenuArea(),
            // Configuration Area
            SizedBox(
              height: configHeight,
              child: _buildConfigurationArea(),
            ),
            // Horizontal resizable divider
            _buildHorizontalDivider(
              onDrag: (delta) {
                setState(() {
                  final newRatio = _testWindowsHeightRatio - (delta / totalHeight);
                  _testWindowsHeightRatio = newRatio.clamp(0.15, 0.6);
                });
              },
            ),
            // Test Windows
            SizedBox(
              height: testWindowsHeight,
              child: _buildTestWindows(),
            ),
          ],
        );
      },
    );
  }

  /// Horizontal resizable divider
  Widget _buildHorizontalDivider({required Function(double) onDrag}) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        child: Container(
          height: 12,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: Container(
              height: 4,
              width: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFCCCCCC),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFutureMenuArea() {
    return Container(
      height: 60,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: const Row(
        children: [
          Icon(Icons.upcoming_outlined, color: Color(0xFF999999), size: 22),
          SizedBox(width: 12),
          Text(
            'Future Menu Area',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xFF666666),
            ),
          ),
          SizedBox(width: 16),
          Text(
            '(Reserved for future features)',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationArea() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE0E0E0)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Color(0xFF1A1A1A), size: 24),
                const SizedBox(width: 12),
                Text(
                  _currentSelectionLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Content - show specific content based on selection
          Expanded(
            child: _buildConfigContent(),
          ),
        ],
      ),
    );
  }

  /// Build content based on current selection
  Widget _buildConfigContent() {
    final mainItem = _menuItems[_selectedMainIndex];

    // LLMs Config > Status
    if (mainItem.id == 'llms_config' && _selectedSubIndex == 0) {
      return const LLMStatusContent();
    }

    // LLMs Config > Config
    if (mainItem.id == 'llms_config' && _selectedSubIndex == 1) {
      return const LLMConfigContent();
    }

    // Default placeholder content
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getConfigIcon(),
            size: 64,
            color: const Color(0xFFE0E0E0),
          ),
          const SizedBox(height: 16),
          Text(
            'Configuration for $_currentSelectionLabel',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Configuration options will appear here',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getConfigIcon() {
    final mainItem = _menuItems[_selectedMainIndex];
    switch (mainItem.id) {
      case 'dashboard':
        return Icons.dashboard_outlined;
      case 'cortex_route':
        return Icons.route_outlined;
      case 'llms_config':
        return Icons.memory_outlined;
      case 'global_setting':
        return Icons.settings_outlined;
      case 'repository':
        return Icons.folder_outlined;
      case 'billing':
        return Icons.payment_outlined;
      default:
        return Icons.settings_outlined;
    }
  }

  Widget _buildTestWindows() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF444444)),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.terminal, color: Color(0xFF00FF88), size: 20),
                SizedBox(width: 12),
                Text(
                  'TEST WINDOWS',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF00FF88),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          // Content
          const Expanded(
            child: Center(
              child: Text(
                'Test output will appear here',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF888888),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
