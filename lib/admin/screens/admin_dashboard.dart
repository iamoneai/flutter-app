// IAMONEAI - Admin Dashboard
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'admin_login_screen.dart';
import '../widgets/llm_status_content.dart';
import '../models/admin_profile.dart';
import '../services/admin_profile_service.dart';
import 'visual_logic_screen.dart';

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
  final _profileService = AdminProfileService();
  final _testInputController = TextEditingController();
  final _scrollController = ScrollController();

  // Admin profile
  AdminProfile? _adminProfile;
  bool _isLoadingProfile = true;
  bool _isEditingProfile = false;
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _iinController = TextEditingController();

  // Test panel state
  String _selectedLLM = 'groq';
  String _selectedModel = 'llama-3.3-70b-versatile';
  bool _isTestRunning = false;
  String _testOutput = '';
  String _testRawJson = '';
  int? _testLatency;
  bool _llmsOk = false;
  double _testPanelSplitRatio = 0.5;

  // Menu items (reorderable)
  List<MenuItem> _menuItems = [
    const MenuItem(
      id: 'visual_logic',
      label: 'Visual Logic',
      icon: Icons.account_tree_outlined,
      subItems: [],
    ),
    const MenuItem(
      id: 'llms_config',
      label: 'LLMs Config',
      icon: Icons.memory_outlined,
      subItems: ['Status', 'Metrics'],
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
  bool _isTestWindowsCollapsed = false;


  // LLM options for test panel
  final Map<String, List<String>> _llmModels = {
    'groq': ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant', 'mixtral-8x7b-32768'],
    'gemini': ['gemini-2.0-flash', 'gemini-1.5-pro', 'gemini-1.5-flash'],
    'claude': ['claude-3-opus', 'claude-3-sonnet', 'claude-3-haiku'],
    'openai': ['gpt-4o', 'gpt-4-turbo', 'gpt-3.5-turbo'],
    'llama3': ['llama-3-8b-instruct', 'llama-3-70b-instruct'],
    'nemotron': ['nemotron-mini-4b-instruct'],
  };

  @override
  void initState() {
    super.initState();
    _loadAdminProfile();
  }

  @override
  void dispose() {
    _testInputController.dispose();
    _scrollController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _iinController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isLoadingProfile = true);

    try {
      final profile = await _profileService.getProfile(user.uid);

      setState(() {
        _adminProfile = profile;
        _firstNameController.text = profile?.firstName ?? '';
        _lastNameController.text = profile?.lastName ?? '';
        _iinController.text = profile?.iin ?? '';
        _isLoadingProfile = false;
      });
    } catch (e) {
      setState(() => _isLoadingProfile = false);
      debugPrint('Error loading admin profile: $e');
    }
  }

  Future<void> _saveAdminProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final profile = await _profileService.updateProfile(
        uid: user.uid,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
      );

      setState(() {
        _adminProfile = profile;
        _isEditingProfile = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _runTest() async {
    if (_testInputController.text.trim().isEmpty) return;

    setState(() {
      _isTestRunning = true;
      _testOutput = 'Sending RAW request to $_selectedLLM...';
      _testRawJson = '';
      _testLatency = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      // Use admin IIN as user ID
      final userId = _adminProfile?.iin ?? _auth.currentUser?.uid ?? 'anonymous';

      // RAW LLM test - direct to llm/raw endpoint (no chat history, no processing)
      final response = await http.post(
        Uri.parse('https://iamoneai-gateway-427305522394.us-central1.run.app/api/llm/raw'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-ID': userId,
        },
        body: jsonEncode({
          'prompt': _testInputController.text.trim(),
          'model': _selectedLLM,
          'max_tokens': 1024,
          'temperature': 0.7,
        }),
      );

      stopwatch.stop();
      final latency = stopwatch.elapsedMilliseconds;

      final rawJson = response.body;
      final encoder = const JsonEncoder.withIndent('  ');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final formattedJson = encoder.convert(data);

        setState(() {
          _testOutput = data['response'] ?? data['text'] ?? 'No response text';
          _testRawJson = formattedJson;
          _testLatency = data['latency_ms'] ?? latency;
          _llmsOk = true;
          _isTestRunning = false;
        });
      } else {
        setState(() {
          _testOutput = 'Error: ${response.statusCode}';
          _testRawJson = rawJson;
          _llmsOk = false;
          _isTestRunning = false;
        });
      }
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _testOutput = 'Error: $e';
        _testRawJson = '{"error": "$e"}';
        _llmsOk = false;
        _isTestRunning = false;
      });
    }
  }

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
          // User info with profile
          InkWell(
            onTap: () => setState(() => _isEditingProfile = true),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white70, size: 20),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _adminProfile?.displayName ?? user?.email ?? 'Admin',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (_adminProfile?.iin != null)
                        Text(
                          'IIN: ${_adminProfile!.iin}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit, color: Colors.white54, size: 14),
                ],
              ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                size: 18,
                color: isSelected
                    ? const Color(0xFF1A1A1A)
                    : const Color(0xFF666666),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
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

    final mainItem = _menuItems[_selectedMainIndex];

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
              mainItem.label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF999999),
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Show regular submenu
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
    final mainItem = _menuItems[_selectedMainIndex];
    final isFullScreenPage = mainItem.id == 'visual_logic';

    // Visual Logic has its own full-screen layout
    if (isFullScreenPage) {
      return Expanded(child: _buildConfigurationArea());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight - 92; // Minus future menu area

        if (_isTestWindowsCollapsed) {
          // Collapsed mode: show only a thin bar
          return Column(
            children: [
              _buildFutureMenuArea(),
              Expanded(child: _buildConfigurationArea()),
              _buildCollapsedTestBar(),
            ],
          );
        }

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
                  _testWindowsHeightRatio = newRatio.clamp(0.1, 0.85);
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

  /// Collapsed test bar
  Widget _buildCollapsedTestBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _isTestWindowsCollapsed = false),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Color(0xFF00FF88), size: 18),
                const SizedBox(width: 10),
                const Text(
                  'RAW TEST',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF00FF88),
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                // LLMs OK indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _llmsOk ? const Color(0xFF1B4D1B) : const Color(0xFF4A4A4A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _llmsOk ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: _llmsOk ? const Color(0xFF00FF88) : Colors.white54,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _llmsOk ? 'LLMs OK' : 'LLMs',
                        style: TextStyle(
                          fontSize: 11,
                          color: _llmsOk ? const Color(0xFF00FF88) : Colors.white54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // IIN indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _adminProfile?.iin != null
                        ? const Color(0xFF4A4A4A)
                        : const Color(0xFF4D1B1B),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _adminProfile?.iin != null ? Icons.badge : Icons.warning_amber,
                        color: _adminProfile?.iin != null ? Colors.amber : const Color(0xFFFF6B6B),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _adminProfile?.iin != null
                            ? 'IIN: ${_adminProfile!.iin}'
                            : 'IIN (missing)',
                        style: TextStyle(
                          fontSize: 11,
                          color: _adminProfile?.iin != null
                              ? Colors.white70
                              : const Color(0xFFFF6B6B),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.expand_less, color: Colors.white54, size: 20),
                const Text(
                  'Expand',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
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
          Spacer(),
        ],
      ),
    );
  }

  Widget _buildConfigurationArea() {
    final mainItem = _menuItems[_selectedMainIndex];
    // Full-screen pages have their own header
    final isFullScreenPage = mainItem.id == 'visual_logic';

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
          // Header (hide for pages with their own header)
          if (!isFullScreenPage)
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
            child: ClipRRect(
              borderRadius: isFullScreenPage
                  ? BorderRadius.circular(12)
                  : const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
              child: _buildConfigContent(),
            ),
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

    // Visual Logic Builder (main menu item)
    if (mainItem.id == 'visual_logic') {
      return const VisualLogicScreen();
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
          // Header with LLM selector and status indicators
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF444444)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Color(0xFF00FF88), size: 18),
                const SizedBox(width: 10),
                const Text(
                  'RAW TEST',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF00FF88),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 16),
                // LLM Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3D3D3D),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedLLM,
                      dropdownColor: const Color(0xFF3D3D3D),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
                      items: _llmModels.keys.map((llm) {
                        return DropdownMenuItem(
                          value: llm,
                          child: Text(llm.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedLLM = value;
                            _selectedModel = _llmModels[value]!.first;
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Model Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3D3D3D),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedModel,
                      dropdownColor: const Color(0xFF3D3D3D),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
                      items: (_llmModels[_selectedLLM] ?? []).map((model) {
                        return DropdownMenuItem(
                          value: model,
                          child: Text(model, style: const TextStyle(fontSize: 11)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedModel = value);
                        }
                      },
                    ),
                  ),
                ),
                const Spacer(),
                // LLMs OK indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _llmsOk ? const Color(0xFF1B4D1B) : const Color(0xFF4A4A4A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _llmsOk ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: _llmsOk ? const Color(0xFF00FF88) : Colors.white54,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _llmsOk ? 'LLMs OK' : 'LLMs',
                        style: TextStyle(
                          fontSize: 11,
                          color: _llmsOk ? const Color(0xFF00FF88) : Colors.white54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // IIN indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _adminProfile?.iin != null
                        ? const Color(0xFF4A4A4A)
                        : const Color(0xFF4D1B1B),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _adminProfile?.iin != null ? Icons.badge : Icons.warning_amber,
                        color: _adminProfile?.iin != null ? Colors.amber : const Color(0xFFFF6B6B),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _adminProfile?.iin != null
                            ? 'IIN: ${_adminProfile!.iin}'
                            : 'IIN (missing)',
                        style: TextStyle(
                          fontSize: 11,
                          color: _adminProfile?.iin != null
                              ? Colors.white70
                              : const Color(0xFFFF6B6B),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                if (_testLatency != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A4A4A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_testLatency}ms',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF00FF88),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // Collapse button
                InkWell(
                  onTap: () => setState(() => _isTestWindowsCollapsed = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A4A4A),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.expand_more, color: Colors.white54, size: 16),
                        SizedBox(width: 2),
                        Text(
                          'Collapse',
                          style: TextStyle(fontSize: 10, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Split panels: Left (Input/Response) and Right (JSON)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final leftWidth = constraints.maxWidth * _testPanelSplitRatio;
                final rightWidth = constraints.maxWidth * (1 - _testPanelSplitRatio);

                return Row(
                  children: [
                    // LEFT PANEL - Input and Response
                    SizedBox(
                      width: leftWidth - 4,
                      child: _buildLeftTestPanel(),
                    ),
                    // Vertical divider
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            final newRatio = _testPanelSplitRatio +
                                (details.delta.dx / constraints.maxWidth);
                            _testPanelSplitRatio = newRatio.clamp(0.3, 0.7);
                          });
                        },
                        child: Container(
                          width: 8,
                          color: const Color(0xFF444444),
                          child: Center(
                            child: Container(
                              width: 2,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF666666),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // RIGHT PANEL - JSON
                    SizedBox(
                      width: rightWidth - 4,
                      child: _buildRightTestPanel(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Left panel: Input field, Run button, Response
  Widget _buildLeftTestPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Input row
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFF444444)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _testInputController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Enter test prompt...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF3D3D3D),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _runTest(),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isTestRunning ? null : _runTest,
                icon: _isTestRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: Text(_isTestRunning ? 'Running...' : 'Run'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00AA66),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
        ),
        // Response header with copy button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF363636),
            border: Border(
              bottom: BorderSide(color: Color(0xFF444444)),
            ),
          ),
          child: Row(
            children: [
              const Text(
                'RESPONSE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white54,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  if (_testOutput.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: _testOutput));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Response copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A4A4A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, color: Colors.white54, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Copy',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Response output
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _testOutput.isEmpty ? 'Response will appear here...' : _testOutput,
              style: TextStyle(
                fontSize: 13,
                color: _testOutput.isEmpty ? const Color(0xFF666666) : Colors.white,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Right panel: Full JSON output
  Widget _buildRightTestPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // JSON header with copy button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFF363636),
            border: Border(
              bottom: BorderSide(color: Color(0xFF444444)),
            ),
          ),
          child: Row(
            children: [
              const Text(
                'RAW JSON',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white54,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  if (_testRawJson.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: _testRawJson));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('JSON copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A4A4A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, color: Colors.white54, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Copy',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // JSON output
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _testRawJson.isEmpty ? '{\n  "status": "waiting for test..."\n}' : _testRawJson,
              style: TextStyle(
                fontSize: 12,
                color: _testRawJson.isEmpty ? const Color(0xFF666666) : const Color(0xFF88CCFF),
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Email (read-only)
              TextField(
                controller: TextEditingController(text: _adminProfile?.email ?? _auth.currentUser?.email ?? ''),
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFFF5F5F5),
                  suffixIcon: Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                ),
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Email cannot be changed',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              // First Name (editable)
              TextField(
                controller: _firstNameController,
                decoration: const InputDecoration(
                  labelText: 'First Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Last Name (editable)
              TextField(
                controller: _lastNameController,
                decoration: const InputDecoration(
                  labelText: 'Last Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // IIN (read-only)
              TextField(
                controller: _iinController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'IIN (Identification Number)',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFFF5F5F5),
                  suffixIcon: Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                  helperText: 'IIN is assigned automatically and cannot be changed',
                ),
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Reset to original values
              _firstNameController.text = _adminProfile?.firstName ?? '';
              _lastNameController.text = _adminProfile?.lastName ?? '';
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveAdminProfile();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    // Show profile dialog if editing
    if (_isEditingProfile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showProfileDialog();
        setState(() => _isEditingProfile = false);
      });
    }

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
                // Resizable divider between Column B and right side
                if (_hasSubItems && !_isColumnBCollapsed)
                  _buildVerticalDivider(
                    onDrag: (delta) {
                      setState(() {
                        _columnBWidth = (_columnBWidth + delta).clamp(150, 320);
                      });
                    },
                  ),
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
}
