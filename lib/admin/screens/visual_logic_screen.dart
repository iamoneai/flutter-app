// IAMONEAI - Visual Logic Builder Screen
// Three-panel layout with adjustable dividers for building logic pipelines

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../models/visual_builder_models.dart';
import '../services/node_template_service.dart';
import '../services/canvas_config_service.dart' as canvas_svc;
import '../services/pipeline_executor_service.dart' as executor;
import '../services/canvas_history_service.dart';
import '../services/canvas_validation_service.dart';
import '../models/visual_builder_models.dart';

/// Canvas tool modes
enum _CanvasTool {
  select,  // Default pointer/select tool
  pan,     // Hand tool for panning
  zoom,    // Zoom tool
}

class VisualLogicScreen extends StatefulWidget {
  const VisualLogicScreen({super.key});

  @override
  State<VisualLogicScreen> createState() => _VisualLogicScreenState();
}

class _VisualLogicScreenState extends State<VisualLogicScreen> {
  // Services
  final NodeTemplateService _templateService = NodeTemplateService();
  final canvas_svc.CanvasConfigService _canvasService = canvas_svc.CanvasConfigService();
  final executor.PipelineExecutorService _executor = executor.PipelineExecutorService();
  final CanvasHistoryService _history = CanvasHistoryService();
  final CanvasClipboard _clipboard = CanvasClipboard();
  final CanvasValidationService _validator = CanvasValidationService();

  // Validation state
  ValidationResult? _validationResult;
  bool _showValidationPanel = false;

  // Keyboard focus
  final FocusNode _canvasFocusNode = FocusNode();

  // Current canvas
  String? _currentCanvasId;
  bool _isSaving = false;

  // Execution state
  bool _isExecuting = false;
  bool _isStepMode = false;
  executor.ExecutionMode _executionMode = executor.ExecutionMode.simulated;
  final Map<String, executor.NodeExecutionState> _nodeExecutionStates = {};
  final List<executor.NodeExecutionResult> _executionTrace = [];
  Map<String, dynamic> _executionOutput = {};
  String _testInput = '{\n  "message": "Hello, how are you?",\n  "userId": "user_123"\n}';
  final TextEditingController _testInputController = TextEditingController();

  // Panel widths
  double _leftPanelWidth = 250;
  double _rightPanelWidth = 300;
  static const double _minPanelWidth = 200;
  static const double _maxLeftPanelWidth = 350;
  static const double _maxRightPanelWidth = 400;
  bool _isLeftPanelCollapsed = false;
  bool _isRightPanelCollapsed = false;

  // Test panel
  double _testPanelHeight = 250;
  static const double _minTestPanelHeight = 100;
  static const double _maxTestPanelHeight = 400;
  bool _isTestPanelCollapsed = true;

  // Canvas state
  double _zoom = 1.0;
  String _canvasName = 'Untitled Pipeline';
  bool _hasUnsavedChanges = false;
  Offset _canvasOffset = Offset.zero;
  int _nextId = 1;
  bool _showGrid = true;
  bool _showMinimap = false;

  // Canvas tool
  _CanvasTool _selectedTool = _CanvasTool.select;

  // Pan state
  bool _isPanning = false;
  bool _isSpacePressed = false;
  Offset _panStart = Offset.zero;
  Offset _panOffsetStart = Offset.zero;

  // Canvas elements
  List<_CanvasLane> _canvasLanes = [];
  List<_CanvasNode> _canvasNodes = [];
  List<_CanvasWire> _canvasWires = [];

  // Template loading state
  bool _isLoadingTemplates = true;
  Map<String, List<NodeTemplate>> _templatesByCategory = {};
  String _searchQuery = '';

  // Palette collapse state
  final Map<String, bool> _paletteGroups = {
    'lanes': true,
    'logic': true,
    'ai': false,
    'memory': false,
    'ui': false,
    'context': false,
  };

  // Selection state (multi-select support)
  final Set<String> _selectedNodeIds = {};
  final Set<String> _selectedWireIds = {};
  String? _selectedLaneId; // Lanes are single-select only

  // Rectangle selection state
  bool _isRectangleSelecting = false;
  Offset _rectangleSelectStart = Offset.zero;
  Offset _rectangleSelectEnd = Offset.zero;

  // Legacy single selection (for settings panel compatibility)
  String? get _selectedElementId => _selectedNodeIds.length == 1
      ? _selectedNodeIds.first
      : _selectedWireIds.length == 1
          ? _selectedWireIds.first
          : _selectedLaneId;
  String? get _selectedElementType {
    if (_selectedNodeIds.length == 1) return 'node';
    if (_selectedWireIds.length == 1) return 'wire';
    if (_selectedLaneId != null) return 'lane';
    return null;
  }

  // Wire drawing state
  bool _isDrawingWire = false;
  String? _wireStartNodeId;
  String? _wireStartPortKey;
  bool _wireStartIsOutput = true;
  Offset _wireEndPosition = Offset.zero;
  final GlobalKey _canvasKey = GlobalKey();

  // Multi-node drag state
  Offset? _dragStartNodePosition;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _testInputController.text = _testInput;
    _history.onHistoryChange = (canUndo, canRedo) {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _testInputController.dispose();
    _canvasFocusNode.dispose();
    _executor.stop();
    _history.onHistoryChange = null;
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    try {
      final templates = await _templateService.getTemplatesByCategory();
      if (mounted) {
        setState(() {
          _templatesByCategory = templates;
          _isLoadingTemplates = false;
        });
      }
      debugPrint('Loaded templates: ${templates.keys.join(', ')}');
    } catch (e) {
      debugPrint('Error loading templates: $e');
      if (mounted) {
        setState(() => _isLoadingTemplates = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F5F5),
      child: Column(
        children: [
          // Header Toolbar
          _buildHeaderToolbar(),
          // Main content area
          Expanded(
            child: Column(
              children: [
                // Three-panel area
                Expanded(
                  child: Row(
                    children: [
                      // LEFT PANEL - Palette
                      _buildLeftPanel(),
                      // Left divider
                      _buildVerticalDivider(
                        onDrag: (delta) {
                          setState(() {
                            _leftPanelWidth = (_leftPanelWidth + delta)
                                .clamp(_minPanelWidth, _maxLeftPanelWidth);
                          });
                        },
                      ),
                      // MIDDLE PANEL - Canvas
                      Expanded(child: _buildCanvasPanel()),
                      // Right divider
                      _buildVerticalDivider(
                        onDrag: (delta) {
                          setState(() {
                            _rightPanelWidth = (_rightPanelWidth - delta)
                                .clamp(_minPanelWidth, _maxRightPanelWidth);
                          });
                        },
                      ),
                      // RIGHT PANEL - Settings
                      _buildRightPanel(),
                    ],
                  ),
                ),
                // Horizontal divider for test panel
                if (!_isTestPanelCollapsed)
                  _buildHorizontalDivider(
                    onDrag: (delta) {
                      setState(() {
                        _testPanelHeight = (_testPanelHeight - delta)
                            .clamp(_minTestPanelHeight, _maxTestPanelHeight);
                      });
                    },
                  ),
                // BOTTOM - Test Panel
                _buildTestPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // HEADER TOOLBAR
  // ============================================================================
  Widget _buildHeaderToolbar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Row(
        children: [
          // File menu
          PopupMenuButton<String>(
            tooltip: 'File Menu',
            offset: const Offset(0, 40),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_outlined, size: 16, color: Color(0xFF666666)),
                  SizedBox(width: 4),
                  Text('File', style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
                  Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF666666)),
                ],
              ),
            ),
            onSelected: (value) {
              switch (value) {
                case 'new':
                  _newCanvas();
                  break;
                case 'open':
                  _showOpenDialog();
                  break;
                case 'save':
                  _saveCanvas();
                  break;
                case 'save_as':
                  _showSaveAsDialog();
                  break;
                case 'snapshot':
                  _showSaveSnapshotDialog();
                  break;
                case 'snapshots':
                  _showSnapshotsDialog();
                  break;
                case 'export':
                  _exportPipeline();
                  break;
                case 'import':
                  _importPipeline();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [
                    Icon(Icons.add, size: 18, color: Color(0xFF666666)),
                    SizedBox(width: 8),
                    Text('New Canvas'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'open',
                child: Row(
                  children: [
                    Icon(Icons.folder_open, size: 18, color: Color(0xFF666666)),
                    SizedBox(width: 8),
                    Text('Open...'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'save',
                enabled: _hasUnsavedChanges,
                child: Row(
                  children: [
                    Icon(Icons.save, size: 18, color: _hasUnsavedChanges ? const Color(0xFF666666) : const Color(0xFFCCCCCC)),
                    const SizedBox(width: 8),
                    Text('Save', style: TextStyle(color: _hasUnsavedChanges ? null : const Color(0xFFCCCCCC))),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'save_as',
                child: Row(
                  children: [
                    Icon(Icons.save_as, size: 18, color: Color(0xFF666666)),
                    SizedBox(width: 8),
                    Text('Save As...'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'snapshot',
                enabled: _currentCanvasId != null,
                child: Row(
                  children: [
                    Icon(Icons.camera_alt_outlined, size: 18, color: _currentCanvasId != null ? const Color(0xFF666666) : const Color(0xFFCCCCCC)),
                    const SizedBox(width: 8),
                    Text('Save Snapshot...', style: TextStyle(color: _currentCanvasId != null ? null : const Color(0xFFCCCCCC))),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'snapshots',
                enabled: _currentCanvasId != null,
                child: Row(
                  children: [
                    Icon(Icons.history, size: 18, color: _currentCanvasId != null ? const Color(0xFF666666) : const Color(0xFFCCCCCC)),
                    const SizedBox(width: 8),
                    Text('View Snapshots...', style: TextStyle(color: _currentCanvasId != null ? null : const Color(0xFFCCCCCC))),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 18, color: Color(0xFF666666)),
                    SizedBox(width: 8),
                    Text('Export to JSON...'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.file_upload_outlined, size: 18, color: Color(0xFF666666)),
                    SizedBox(width: 8),
                    Text('Import from JSON...'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Divider
          Container(width: 1, height: 24, color: const Color(0xFFE0E0E0)),
          const SizedBox(width: 16),
          // Canvas name
          InkWell(
            onTap: _showRenameDialog,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_currentCanvasId != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.cloud_done, size: 14, color: Color(0xFF4CAF50)),
                    ),
                  Text(
                    _canvasName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  if (_hasUnsavedChanges)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Text('*', style: TextStyle(color: Colors.orange, fontSize: 16)),
                    ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF999999)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Divider
          Container(width: 1, height: 24, color: const Color(0xFFE0E0E0)),
          const SizedBox(width: 16),
          // Undo/Redo
          _buildToolbarButton(
            icon: Icons.undo,
            tooltip: _history.undoDescription != null
                ? 'Undo: ${_history.undoDescription} (Ctrl+Z)'
                : 'Undo (Ctrl+Z)',
            onPressed: _history.canUndo ? _performUndo : null,
          ),
          _buildToolbarButton(
            icon: Icons.redo,
            tooltip: _history.redoDescription != null
                ? 'Redo: ${_history.redoDescription} (Ctrl+Y)'
                : 'Redo (Ctrl+Y)',
            onPressed: _history.canRedo ? _performRedo : null,
          ),
          const SizedBox(width: 16),
          // Divider
          Container(width: 1, height: 24, color: const Color(0xFFE0E0E0)),
          const SizedBox(width: 16),
          // Zoom controls
          _buildToolbarButton(
            icon: Icons.remove,
            tooltip: 'Zoom Out (Mouse wheel)',
            onPressed: () => setState(() => _zoom = (_zoom - 0.1).clamp(0.25, 3.0)),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _zoom = 1.0;
              _canvasOffset = Offset.zero;
            }),
            child: Container(
              width: 60,
              alignment: Alignment.center,
              child: Tooltip(
                message: 'Click to reset view',
                child: Text(
                  '${(_zoom * 100).round()}%',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                ),
              ),
            ),
          ),
          _buildToolbarButton(
            icon: Icons.add,
            tooltip: 'Zoom In (Mouse wheel)',
            onPressed: () => setState(() => _zoom = (_zoom + 0.1).clamp(0.25, 3.0)),
          ),
          _buildToolbarButton(
            icon: Icons.fit_screen_outlined,
            tooltip: 'Zoom to Fit All',
            onPressed: _zoomToFit,
          ),
          _buildToolbarButton(
            icon: Icons.center_focus_strong_outlined,
            tooltip: 'Reset View (100%)',
            onPressed: () => setState(() {
              _zoom = 1.0;
              _canvasOffset = Offset.zero;
            }),
          ),
          const Spacer(),
          // Saving indicator
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Saving...', style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
                ],
              ),
            ),
          // Grid toggle
          _buildToolbarButton(
            icon: _showGrid ? Icons.grid_on : Icons.grid_off,
            tooltip: _showGrid ? 'Hide Grid' : 'Show Grid',
            onPressed: () => setState(() => _showGrid = !_showGrid),
            isActive: _showGrid,
          ),
          _buildToolbarButton(
            icon: _showMinimap ? Icons.map : Icons.map_outlined,
            tooltip: _showMinimap ? 'Hide Minimap' : 'Show Minimap',
            onPressed: () => setState(() => _showMinimap = !_showMinimap),
            isActive: _showMinimap,
          ),
          const SizedBox(width: 8),
          // Auto-layout button
          _buildToolbarButton(
            icon: Icons.auto_fix_high,
            tooltip: 'Auto Layout',
            onPressed: _canvasNodes.isEmpty ? null : _performAutoLayout,
          ),
          const SizedBox(width: 8),
          // Validate button
          _buildValidationButton(),
          const SizedBox(width: 16),
          // Divider
          Container(width: 1, height: 24, color: const Color(0xFFE0E0E0)),
          const SizedBox(width: 16),
          // Save button
          OutlinedButton.icon(
            onPressed: _hasUnsavedChanges && !_isSaving ? _saveCanvas : null,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
              side: const BorderSide(color: Color(0xFFCCCCCC)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
          // Run/Stop button
          ElevatedButton.icon(
            onPressed: _isExecuting
                ? _stopExecution
                : (_canvasNodes.isEmpty ? null : () => _runPipeline(stepMode: false)),
            icon: Icon(_isExecuting ? Icons.stop : Icons.play_arrow, size: 18),
            label: Text(_isExecuting ? 'Stop' : 'Run'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isExecuting ? Colors.red : const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
          const SizedBox(width: 16),
          // Help button
          _buildToolbarButton(
            icon: Icons.help_outline,
            tooltip: 'Keyboard Shortcuts',
            onPressed: _showKeyboardShortcuts,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    bool isActive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFE3F2FD) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 18,
            color: onPressed != null
                ? (isActive ? const Color(0xFF1976D2) : const Color(0xFF666666))
                : const Color(0xFFCCCCCC),
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required String label,
    required bool isSelected,
    VoidCallback? onTap,
    bool isLive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isLive ? const Color(0xFF2196F3) : const Color(0xFF666666))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLive && isSelected)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.cloud_outlined, size: 10, color: Colors.white),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF999999),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationButton() {
    final hasIssues = _validationResult != null &&
        (_validationResult!.errorCount > 0 || _validationResult!.warningCount > 0);
    final errorCount = _validationResult?.errorCount ?? 0;
    final warningCount = _validationResult?.warningCount ?? 0;

    Color iconColor = const Color(0xFF666666);
    if (errorCount > 0) {
      iconColor = Colors.red;
    } else if (warningCount > 0) {
      iconColor = Colors.orange;
    } else if (_validationResult != null && _validationResult!.isValid) {
      iconColor = Colors.green;
    }

    return Tooltip(
      message: hasIssues
          ? 'Validation: $errorCount error(s), $warningCount warning(s)'
          : 'Validate Pipeline',
      child: InkWell(
        onTap: _validateCanvas,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasIssues ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                size: 18,
                color: iconColor,
              ),
              if (hasIssues) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: errorCount > 0 ? Colors.red : Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${errorCount + warningCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // LEFT PANEL - Element Palette
  // ============================================================================
  Widget _buildLeftPanel() {
    // Collapsed state
    if (_isLeftPanelCollapsed) {
      return Container(
        width: 40,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(right: BorderSide(color: Color(0xFFE0E0E0))),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _isLeftPanelCollapsed = false),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF666666)),
              ),
            ),
            const RotatedBox(
              quarterTurns: 3,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'ELEMENTS',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: _leftPanelWidth,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with refresh button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _isLeftPanelCollapsed = true),
                  child: const Icon(Icons.chevron_left, size: 18, color: Color(0xFF999999)),
                ),
                const SizedBox(width: 4),
                const Text(
                  'ELEMENTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF999999),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (_isLoadingTemplates)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  InkWell(
                    onTap: () {
                      setState(() => _isLoadingTemplates = true);
                      _templateService.clearCache();
                      _loadTemplates();
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.refresh, size: 14, color: Color(0xFF999999)),
                    ),
                  ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search elements...',
                hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF999999)),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Element groups
          Expanded(
            child: _isLoadingTemplates
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      // Lanes section (static)
                      _buildLanesGroup(),
                      // Dynamic node categories from Firebase
                      ..._buildDynamicNodeGroups(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Build lanes group (static lane templates)
  Widget _buildLanesGroup() {
    final laneTemplates = NodeTemplateService.laneTemplates;
    final filteredLanes = _searchQuery.isEmpty
        ? laneTemplates
        : laneTemplates.where((l) => l.name.toLowerCase().contains(_searchQuery)).toList();

    if (filteredLanes.isEmpty && _searchQuery.isNotEmpty) return const SizedBox.shrink();

    final isExpanded = _paletteGroups['lanes'] ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Group header
        InkWell(
          onTap: () => setState(() => _paletteGroups['lanes'] = !isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: const Color(0xFF666666),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.view_stream, size: 14, color: Color(0xFF607D8B)),
                const SizedBox(width: 6),
                const Text(
                  'LANES',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF999999),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${filteredLanes.length}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF999999)),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Lane items
        if (isExpanded)
          ...filteredLanes.map((lane) => _buildLaneItem(lane)),
      ],
    );
  }

  /// Build lane palette item
  Widget _buildLaneItem(LaneTemplate lane) {
    return Draggable<Map<String, dynamic>>(
      data: {'type': 'lane', 'id': lane.id, 'template': lane},
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: lane.getColor(), width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(lane.icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(lane.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(lane.type.name.toUpperCase(), style: TextStyle(fontSize: 9, color: lane.getColor())),
                ],
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildLaneItemContent(lane),
      ),
      child: _buildLaneItemContent(lane),
    );
  }

  Widget _buildLaneItemContent(LaneTemplate lane) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          Text(lane.icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lane.name, style: const TextStyle(fontSize: 12, color: Color(0xFF1A1A1A))),
                Text(lane.description, style: const TextStyle(fontSize: 9, color: Color(0xFF999999)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: lane.getColor().withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(lane.type.name, style: TextStyle(fontSize: 8, color: lane.getColor(), fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.drag_indicator, size: 14, color: Color(0xFFCCCCCC)),
        ],
      ),
    );
  }

  /// Build dynamic node groups from Firebase templates
  List<Widget> _buildDynamicNodeGroups() {
    final widgets = <Widget>[];

    // Get sorted categories
    final sortedCategories = NodeTemplateService.categories
        .where((c) => c.id != 'lanes') // Exclude lanes, handled separately
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    for (final category in sortedCategories) {
      final templates = _templatesByCategory[category.id] ?? [];

      // Filter by search
      final filteredTemplates = _searchQuery.isEmpty
          ? templates
          : templates.where((t) =>
              t.name.toLowerCase().contains(_searchQuery) ||
              t.description.toLowerCase().contains(_searchQuery)
            ).toList();

      if (filteredTemplates.isEmpty && _searchQuery.isNotEmpty) continue;

      widgets.add(_buildNodeGroup(category, filteredTemplates));
    }

    return widgets;
  }

  /// Build a node category group
  Widget _buildNodeGroup(NodeCategoryInfo category, List<NodeTemplate> templates) {
    final isExpanded = _paletteGroups[category.id] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Group header
        InkWell(
          onTap: () => setState(() => _paletteGroups[category.id] = !isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: const Color(0xFF666666),
                ),
                const SizedBox(width: 6),
                Icon(category.icon, size: 14, color: category.getColor()),
                const SizedBox(width: 6),
                Text(
                  category.name,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF999999),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${templates.length}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF999999)),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Node items
        if (isExpanded)
          ...templates.map((template) => _buildNodeItem(template, category)),
      ],
    );
  }

  /// Build a node palette item with port preview
  Widget _buildNodeItem(NodeTemplate template, NodeCategoryInfo category) {
    return Draggable<Map<String, dynamic>>(
      data: {'type': 'node', 'id': template.id, 'template': template},
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(minWidth: 180),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: category.getColor(), width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(template.icon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(template.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              if (template.inputPorts.isNotEmpty || template.outputPorts.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Input ports
                    if (template.inputPorts.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('${template.inputPorts.length} in', style: const TextStyle(fontSize: 9, color: Color(0xFF666666))),
                        ],
                      ),
                    if (template.inputPorts.isNotEmpty && template.outputPorts.isNotEmpty)
                      const SizedBox(width: 12),
                    // Output ports
                    if (template.outputPorts.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('${template.outputPorts.length} out', style: const TextStyle(fontSize: 9, color: Color(0xFF666666))),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildNodeItemContent(template, category),
      ),
      child: _buildNodeItemContent(template, category),
    );
  }

  Widget _buildNodeItemContent(NodeTemplate template, NodeCategoryInfo category) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          Text(template.icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.name, style: const TextStyle(fontSize: 12, color: Color(0xFF1A1A1A))),
                Row(
                  children: [
                    if (template.inputPorts.isNotEmpty) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text('${template.inputPorts.length}', style: const TextStyle(fontSize: 9, color: Color(0xFF999999))),
                      const SizedBox(width: 6),
                    ],
                    if (template.outputPorts.isNotEmpty) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text('${template.outputPorts.length}', style: const TextStyle(fontSize: 9, color: Color(0xFF999999))),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.drag_indicator, size: 14, color: Color(0xFFCCCCCC)),
        ],
      ),
    );
  }

  // ============================================================================
  // MIDDLE PANEL - Canvas
  // ============================================================================
  Widget _buildCanvasPanel() {
    return Focus(
      focusNode: _canvasFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return DragTarget<Map<String, dynamic>>(
          onAcceptWithDetails: (details) {
            final data = details.data;
            final type = data['type'] as String?;
            final renderBox = context.findRenderObject() as RenderBox?;
            final screenPosition = renderBox?.globalToLocal(details.offset) ?? Offset.zero;
            // Convert screen position to canvas position (account for zoom/pan)
            final canvasPosition = _screenToCanvas(screenPosition);

            if (type == 'lane') {
              _createLaneFromDrop(data, canvasPosition);
            } else if (type == 'node') {
              _createNodeFromDrop(data, canvasPosition);
            }
          },
          builder: (context, candidateData, rejectedData) {
            final isDragOver = candidateData.isNotEmpty;
            final hasElements = _canvasLanes.isNotEmpty || _canvasNodes.isNotEmpty;

            return Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  // Mouse wheel zoom - zoom towards cursor position
                  final delta = event.scrollDelta.dy > 0 ? -0.1 : 0.1;
                  final newZoom = (_zoom + delta).clamp(0.25, 3.0);

                  if (newZoom != _zoom) {
                    // Get cursor position relative to canvas
                    final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
                    if (renderBox != null) {
                      final localPos = renderBox.globalToLocal(event.position);

                      // Calculate new offset to zoom towards cursor
                      final zoomFactor = newZoom / _zoom;
                      final newOffset = Offset(
                        localPos.dx - (localPos.dx - _canvasOffset.dx) * zoomFactor,
                        localPos.dy - (localPos.dy - _canvasOffset.dy) * zoomFactor,
                      );

                      setState(() {
                        _zoom = newZoom;
                        _canvasOffset = newOffset;
                      });
                    } else {
                      setState(() => _zoom = newZoom);
                    }
                  }
                }
              },
              child: MouseRegion(
                cursor: _isSpacePressed
                    ? (_isPanning ? SystemMouseCursors.grabbing : SystemMouseCursors.grab)
                    : SystemMouseCursors.basic,
                onHover: _isDrawingWire ? (event) {
                  final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
                  if (renderBox != null) {
                    setState(() {
                      // Convert screen position to canvas position (account for zoom/pan)
                      final localPos = renderBox.globalToLocal(event.position);
                      _wireEndPosition = _screenToCanvas(localPos);
                    });
                  }
                } : null,
                child: GestureDetector(
                  onTap: () {
                    if (_isDrawingWire) {
                      _cancelWireDrawing();
                    } else if (!_isSpacePressed) {
                      _clearSelection();
                    }
                  },
                  onPanStart: _isDrawingWire ? null : (details) {
                    if (_isSpacePressed) {
                      // Start panning
                      setState(() {
                        _isPanning = true;
                        _panStart = details.localPosition;
                        _panOffsetStart = _canvasOffset;
                      });
                    } else {
                      // Start rectangle selection
                      setState(() {
                        _isRectangleSelecting = true;
                        _rectangleSelectStart = _screenToCanvas(details.localPosition);
                        _rectangleSelectEnd = _screenToCanvas(details.localPosition);
                      });
                    }
                  },
                  onPanUpdate: _isDrawingWire ? null : (details) {
                    if (_isPanning) {
                      // Update pan offset
                      setState(() {
                        _canvasOffset = _panOffsetStart + (details.localPosition - _panStart);
                      });
                    } else if (_isRectangleSelecting) {
                      setState(() {
                        _rectangleSelectEnd = _screenToCanvas(details.localPosition);
                      });
                    }
                  },
                  onPanEnd: _isDrawingWire ? null : (details) {
                    if (_isPanning) {
                      setState(() => _isPanning = false);
                    } else if (_isRectangleSelecting) {
                      _selectNodesInRectangle();
                      setState(() {
                        _isRectangleSelecting = false;
                      });
                    }
                  },
                  child: Container(
                  key: _canvasKey,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    border: isDragOver
                        ? Border.all(color: const Color(0xFF2196F3), width: 2)
                        : _isDrawingWire
                            ? Border.all(color: const Color(0xFF4CAF50), width: 2)
                            : null,
                  ),
                  child: ClipRect(
                    child: Stack(
                      children: [
                        // Grid background (with offset) - conditionally shown
                        if (_showGrid)
                          CustomPaint(
                            size: Size.infinite,
                            painter: _GridPainter(zoom: _zoom, offset: _canvasOffset),
                          ),
                        // Canvas content (with zoom/pan transform)
                        Transform(
                          transform: Matrix4.identity()
                            ..translate(_canvasOffset.dx, _canvasOffset.dy)
                            ..scale(_zoom),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              if (!hasElements)
                                _buildEmptyCanvasPlaceholder(isDragOver)
                              else
                                ..._buildCanvasElements(constraints),
                              // Wire preview while drawing
                              if (_isDrawingWire)
                                CustomPaint(
                                  size: Size.infinite,
                                  painter: _WirePreviewPainter(
                                    startPosition: _getPortPosition(_wireStartNodeId!, _wireStartPortKey!, _wireStartIsOutput),
                                    endPosition: _wireEndPosition,
                                    isOutput: _wireStartIsOutput,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Drop zone indicator for lanes (in screen space)
                        if (isDragOver && candidateData.isNotEmpty)
                          _buildDropZoneIndicator(candidateData.first),
                        // Wire drawing indicator (in screen space)
                        if (_isDrawingWire)
                          Positioned(
                            top: 8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  'Click on a port to connect • ESC to cancel',
                                  style: TextStyle(color: Colors.white, fontSize: 11),
                                ),
                              ),
                            ),
                          ),
                        // Rectangle selection overlay (in canvas coordinates but drawn in screen space)
                        if (_isRectangleSelecting)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _SelectionRectPainter(
                                startPos: _canvasToScreen(_rectangleSelectStart),
                                endPos: _canvasToScreen(_rectangleSelectEnd),
                              ),
                            ),
                          ),
                        // Pan mode indicator
                        if (_isSpacePressed)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Pan Mode - Drag to move canvas',
                                style: TextStyle(color: Colors.white, fontSize: 11),
                              ),
                            ),
                          ),
                        // Minimap with viewport indicator (conditionally shown)
                        if (_showMinimap && hasElements && !_isDrawingWire)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: _buildMinimap(),
                          ),
                        // Canvas tools floating toolbar
                        Positioned(
                          left: 16,
                          bottom: 16,
                          child: _buildCanvasToolbar(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          },
          );
        },
      ),
    );
  }

  Widget _buildEmptyCanvasPlaceholder(bool isDragOver) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isDragOver ? Icons.add_circle_outline : Icons.dashboard_customize_outlined,
            size: 64,
            color: isDragOver ? const Color(0xFF2196F3) : const Color(0xFFE0E0E0),
          ),
          const SizedBox(height: 16),
          Text(
            isDragOver ? 'Drop element here' : 'Drag elements from the palette',
            style: TextStyle(
              fontSize: 14,
              color: isDragOver ? const Color(0xFF2196F3) : const Color(0xFF999999),
            ),
          ),
          if (!isDragOver) ...[
            const SizedBox(height: 8),
            const Text(
              'Start by adding a Lane, then add Nodes to it',
              style: TextStyle(fontSize: 12, color: Color(0xFFCCCCCC)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropZoneIndicator(Map<String, dynamic>? data) {
    if (data == null) return const SizedBox.shrink();
    final type = data['type'] as String?;

    if (type == 'lane') {
      // Show horizontal drop zone at bottom of existing lanes
      final y = _canvasLanes.isEmpty ? 20.0 : _canvasLanes.last.y + _canvasLanes.last.height + 10;
      return Positioned(
        left: 60,
        right: 16,
        top: y,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF2196F3), width: 2, style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF2196F3).withValues(alpha: 0.1),
          ),
          child: const Center(
            child: Text(
              'Drop lane here',
              style: TextStyle(color: Color(0xFF2196F3), fontSize: 12),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  List<Widget> _buildCanvasElements(BoxConstraints constraints) {
    final widgets = <Widget>[];

    // Render lanes
    for (final lane in _canvasLanes) {
      widgets.add(_buildCanvasLane(lane, constraints));
    }

    // Render nodes on top
    for (final node in _canvasNodes) {
      widgets.add(_buildCanvasNode(node));
    }

    // Render wires on top of everything
    for (final wire in _canvasWires) {
      widgets.add(_buildCanvasWire(wire));
    }

    return widgets;
  }

  Widget _buildCanvasLane(_CanvasLane lane, BoxConstraints constraints) {
    final isSelected = _selectedLaneId == lane.id;

    return Positioned(
      left: 0,
      right: 0,
      top: lane.y,
      height: lane.isCollapsed ? 40 : lane.height,
      child: GestureDetector(
        onTap: () => _selectElement(lane.id, 'lane'),
        child: Row(
          children: [
            // Lane header (left sidebar)
            Container(
              width: 50,
              decoration: BoxDecoration(
                color: lane.color.withValues(alpha: 0.15),
                border: Border(
                  right: BorderSide(color: lane.color, width: 3),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(lane.icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 4),
                  RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      lane.name,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: lane.color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _toggleLaneCollapse(lane.id),
                    child: Icon(
                      lane.isCollapsed ? Icons.expand_more : Icons.expand_less,
                      size: 16,
                      color: lane.color,
                    ),
                  ),
                ],
              ),
            ),
            // Lane content area
            Expanded(
              child: DragTarget<Map<String, dynamic>>(
                onWillAcceptWithDetails: (details) {
                  final type = details.data['type'] as String?;
                  return type == 'node';
                },
                onAcceptWithDetails: (details) {
                  final renderBox = context.findRenderObject() as RenderBox?;
                  final localPosition = renderBox?.globalToLocal(details.offset) ?? Offset.zero;
                  _createNodeInLane(details.data, lane.id, localPosition);
                },
                builder: (context, candidateData, rejectedData) {
                  final isNodeDragOver = candidateData.isNotEmpty;
                  return Container(
                    decoration: BoxDecoration(
                      color: isNodeDragOver
                          ? lane.color.withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.5),
                      border: Border(
                        top: BorderSide(
                          color: isSelected ? const Color(0xFF2196F3) : const Color(0xFFE0E0E0),
                          width: isSelected ? 2 : 1,
                        ),
                        bottom: BorderSide(
                          color: isSelected ? const Color(0xFF2196F3) : const Color(0xFFE0E0E0),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                    ),
                    child: lane.isCollapsed
                        ? Center(
                            child: Text(
                              '${lane.nodeIds.length} nodes',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                            ),
                          )
                        : Stack(
                            children: [
                              if (lane.nodeIds.isEmpty)
                                Center(
                                  child: Text(
                                    isNodeDragOver ? 'Drop node here' : 'Drag nodes into this lane',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isNodeDragOver ? lane.color : const Color(0xFFCCCCCC),
                                    ),
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

  Widget _buildCanvasNode(_CanvasNode node) {
    final isSelected = _isNodeSelected(node.id);

    return Positioned(
      left: node.x,
      top: node.y,
      child: Draggable<Map<String, dynamic>>(
        data: {'type': 'move_node', 'nodeId': node.id},
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: _buildNodeWidget(node, isSelected: false, isDragging: true),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: _buildNodeWidget(node, isSelected: isSelected),
        ),
        onDragStarted: () {
          // Store the original position for delta calculation
          _dragStartNodePosition = Offset(node.x, node.y);
          // If this node isn't selected, select it
          if (!_isNodeSelected(node.id)) {
            _selectElement(node.id, 'node');
          }
        },
        onDragEnd: (details) {
          final renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox != null && _dragStartNodePosition != null) {
            final localPosition = renderBox.globalToLocal(details.offset);
            // Calculate the delta from original position
            final delta = localPosition - _dragStartNodePosition!;
            _moveSelectedNodes(node.id, delta);
          }
          _dragStartNodePosition = null;
        },
        child: GestureDetector(
          onTap: () {
            final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
            _selectElement(node.id, 'node', addToSelection: isShiftPressed);
          },
          child: _buildNodeWidget(node, isSelected: isSelected),
        ),
      ),
    );
  }

  Widget _buildNodeWidget(_CanvasNode node, {bool isSelected = false, bool isDragging = false}) {
    // Get execution state for this node
    final executionState = _nodeExecutionStates[node.id] ?? executor.NodeExecutionState.idle;
    final stateColor = _getExecutionStateColor(executionState);
    final isRunning = executionState == executor.NodeExecutionState.running;
    final hasExecutionState = _nodeExecutionStates.containsKey(node.id);

    // Get validation state for this node
    final validationSeverity = _getNodeValidationSeverity(node.id);
    final hasValidationIssue = validationSeverity != null;

    // Determine border color based on selection, execution state, and validation
    Color borderColor;
    double borderWidth;
    if (isSelected) {
      borderColor = const Color(0xFF2196F3);
      borderWidth = 2;
    } else if (hasExecutionState && executionState != executor.NodeExecutionState.idle) {
      borderColor = stateColor;
      borderWidth = 2;
    } else if (hasValidationIssue) {
      borderColor = validationSeverity == ValidationSeverity.error
          ? Colors.red
          : validationSeverity == ValidationSeverity.warning
              ? Colors.orange
              : Colors.blue;
      borderWidth = 2;
    } else {
      borderColor = node.color;
      borderWidth = 1;
    }

    return Container(
      width: node.width,
      constraints: BoxConstraints(minHeight: node.height),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDragging ? 0.2 : 0.1),
            blurRadius: isDragging ? 8 : 4,
            offset: Offset(0, isDragging ? 4 : 2),
          ),
          if (isRunning)
            BoxShadow(
              color: stateColor.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Node header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: hasExecutionState && executionState != executor.NodeExecutionState.idle
                  ? stateColor.withValues(alpha: 0.15)
                  : node.color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Text(node.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Validation indicator
                if (hasValidationIssue && !hasExecutionState)
                  Tooltip(
                    message: _getNodeValidationIssues(node.id).map((i) => i.message).join('\n'),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: (validationSeverity == ValidationSeverity.error
                                ? Colors.red
                                : validationSeverity == ValidationSeverity.warning
                                    ? Colors.orange
                                    : Colors.blue)
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        validationSeverity == ValidationSeverity.error
                            ? Icons.error_outline
                            : validationSeverity == ValidationSeverity.warning
                                ? Icons.warning_amber
                                : Icons.info_outline,
                        size: 12,
                        color: validationSeverity == ValidationSeverity.error
                            ? Colors.red
                            : validationSeverity == ValidationSeverity.warning
                                ? Colors.orange
                                : Colors.blue,
                      ),
                    ),
                  ),
                // Execution state indicator
                if (hasExecutionState && executionState != executor.NodeExecutionState.idle)
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: stateColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: isRunning
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: Padding(
                              padding: EdgeInsets.all(3),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Icon(
                            _getExecutionStateIcon(executionState),
                            size: 12,
                            color: stateColor,
                          ),
                  ),
              ],
            ),
          ),
          // Ports
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Input ports (left)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: node.inputPorts.map((port) => _buildPortWidget(node, port, true)).toList(),
                ),
                const Spacer(),
                // Output ports (right)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: node.outputPorts.map((port) => _buildPortWidget(node, port, false)).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortWidget(_CanvasNode node, _CanvasPort port, bool isInput) {
    final isConnected = _isPortConnected(node.id, port.key, isInput);
    final isValidTarget = _isDrawingWire && _wireStartIsOutput != isInput && _wireStartNodeId != node.id;
    final isActiveSource = _isDrawingWire && _wireStartNodeId == node.id && _wireStartPortKey == port.key;

    return GestureDetector(
      onTap: () => _handlePortTap(node.id, port, isInput),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isInput) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: isValidTarget ? 14 : 10,
                  height: isValidTarget ? 14 : 10,
                  decoration: BoxDecoration(
                    color: isConnected ? Colors.green : (isValidTarget ? Colors.green.shade300 : Colors.green),
                    borderRadius: BorderRadius.circular(isValidTarget ? 7 : 5),
                    border: Border.all(
                      color: isValidTarget ? Colors.green.shade700 : Colors.white,
                      width: isValidTarget ? 2 : 1,
                    ),
                    boxShadow: isValidTarget ? [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ] : null,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                port.label,
                style: TextStyle(
                  fontSize: 9,
                  color: isValidTarget ? Colors.green.shade700 : const Color(0xFF666666),
                  fontWeight: isValidTarget ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (!isInput) ...[
                const SizedBox(width: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: isActiveSource ? 14 : (isValidTarget ? 14 : 10),
                  height: isActiveSource ? 14 : (isValidTarget ? 14 : 10),
                  decoration: BoxDecoration(
                    color: isConnected ? Colors.orange : (isActiveSource ? Colors.orange.shade300 : Colors.orange),
                    borderRadius: BorderRadius.circular(isActiveSource || isValidTarget ? 7 : 5),
                    border: Border.all(
                      color: isActiveSource ? Colors.orange.shade700 : Colors.white,
                      width: isActiveSource ? 2 : 1,
                    ),
                    boxShadow: isActiveSource ? [
                      BoxShadow(
                        color: Colors.orange.withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ] : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _isPortConnected(String nodeId, String portKey, bool isInput) {
    if (isInput) {
      return _canvasWires.any((w) => w.toNodeId == nodeId && w.toPortKey == portKey);
    } else {
      return _canvasWires.any((w) => w.fromNodeId == nodeId && w.fromPortKey == portKey);
    }
  }

  void _handlePortTap(String nodeId, _CanvasPort port, bool isInput) {
    if (!_isDrawingWire) {
      // Start drawing wire from output port
      if (!isInput) {
        setState(() {
          _isDrawingWire = true;
          _wireStartNodeId = nodeId;
          _wireStartPortKey = port.key;
          _wireStartIsOutput = true;
          _wireEndPosition = _getPortPosition(nodeId, port.key, true);
        });
      }
    } else {
      // Complete wire connection
      if (_wireStartIsOutput && isInput && _wireStartNodeId != nodeId) {
        _createWire(_wireStartNodeId!, _wireStartPortKey!, nodeId, port.key);
      }
      _cancelWireDrawing();
    }
  }

  void _createWire(String fromNodeId, String fromPortKey, String toNodeId, String toPortKey) {
    // Check if wire already exists
    final exists = _canvasWires.any((w) =>
      w.fromNodeId == fromNodeId && w.fromPortKey == fromPortKey &&
      w.toNodeId == toNodeId && w.toPortKey == toPortKey
    );
    if (exists) return;

    final wire = _CanvasWire(
      id: 'wire_${_nextId++}',
      fromNodeId: fromNodeId,
      fromPortKey: fromPortKey,
      toNodeId: toNodeId,
      toPortKey: toPortKey,
    );

    setState(() {
      _canvasWires.add(wire);
      _hasUnsavedChanges = true;
    });

    // Record for undo
    _history.recordAddWire(_wireToMap(wire));

    debugPrint('Created wire: $fromNodeId:$fromPortKey -> $toNodeId:$toPortKey');
  }

  void _cancelWireDrawing() {
    setState(() {
      _isDrawingWire = false;
      _wireStartNodeId = null;
      _wireStartPortKey = null;
    });
  }

  Offset _getPortPosition(String nodeId, String portKey, bool isOutput) {
    final node = _canvasNodes.firstWhere((n) => n.id == nodeId);

    // Calculate port Y position based on port index
    final ports = isOutput ? node.outputPorts : node.inputPorts;
    final portIndex = ports.indexWhere((p) => p.key == portKey);
    if (portIndex == -1) return Offset(node.x, node.y);

    // Node header is about 30px, ports start at y + 38, each port is about 16px apart
    final portY = node.y + 38 + (portIndex * 16);
    final portX = isOutput ? node.x + node.width : node.x;

    return Offset(portX, portY);
  }

  Widget _buildCanvasWire(_CanvasWire wire) {
    final isSelected = _isWireSelected(wire.id);
    final startPos = _getPortPosition(wire.fromNodeId, wire.fromPortKey, true);
    final endPos = _getPortPosition(wire.toNodeId, wire.toPortKey, false);

    return GestureDetector(
      onTap: () {
        final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
        _selectElement(wire.id, 'wire', addToSelection: isShiftPressed);
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: _WirePainter(
          startPosition: startPos,
          endPosition: endPos,
          isSelected: isSelected,
          color: wire.color,
        ),
      ),
    );
  }

  Widget _buildCanvasToolbar() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 44,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Select tool
            _buildToolButton(
              icon: Icons.near_me,
              isSelected: _selectedTool == _CanvasTool.select,
              tooltip: 'Select Tool (V)',
              onPressed: () => setState(() => _selectedTool = _CanvasTool.select),
            ),
            // Pan tool
            _buildToolButton(
              icon: Icons.pan_tool,
              isSelected: _selectedTool == _CanvasTool.pan,
              tooltip: 'Pan Tool (H)',
              onPressed: () => setState(() => _selectedTool = _CanvasTool.pan),
            ),
            // Zoom tool
            _buildToolButton(
              icon: Icons.zoom_in,
              isSelected: _selectedTool == _CanvasTool.zoom,
              tooltip: 'Zoom Tool (Z)',
              onPressed: () => setState(() => _selectedTool = _CanvasTool.zoom),
            ),
            const Divider(height: 8),
            // Zoom to fit
            _buildToolButton(
              icon: Icons.fit_screen,
              isSelected: false,
              tooltip: 'Zoom to Fit',
              onPressed: _zoomToFit,
            ),
            // Reset view
            _buildToolButton(
              icon: Icons.center_focus_strong,
              isSelected: false,
              tooltip: 'Reset View',
              onPressed: () => setState(() {
                _zoom = 1.0;
                _canvasOffset = Offset.zero;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required bool isSelected,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE3F2FD) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? const Color(0xFF1976D2) : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }

  Widget _buildMinimap() {
    // Get canvas size for viewport calculation
    final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    final canvasSize = renderBox?.size ?? const Size(800, 600);

    return GestureDetector(
      onTapDown: (details) {
        // Click on minimap to navigate
        _navigateFromMinimap(details.localPosition, const Size(150, 100), canvasSize);
      },
      onPanUpdate: (details) {
        // Drag on minimap to navigate
        _navigateFromMinimap(details.localPosition, const Size(150, 100), canvasSize);
      },
      child: Container(
        width: 150,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE0E0E0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CustomPaint(
            painter: _MinimapPainter(
              lanes: _canvasLanes,
              nodes: _canvasNodes,
              zoom: _zoom,
              offset: _canvasOffset,
              canvasSize: canvasSize,
            ),
          ),
        ),
      ),
    );
  }

  /// Navigate to a position based on minimap click
  void _navigateFromMinimap(Offset minimapPos, Size minimapSize, Size canvasSize) {
    if (_canvasLanes.isEmpty && _canvasNodes.isEmpty) return;

    // Calculate content bounds
    double maxX = 500;
    double maxY = 300;
    for (final lane in _canvasLanes) {
      maxY = (lane.y + lane.height) > maxY ? (lane.y + lane.height) : maxY;
    }
    for (final node in _canvasNodes) {
      maxX = (node.x + node.width) > maxX ? (node.x + node.width) : maxX;
      maxY = (node.y + node.height) > maxY ? (node.y + node.height) : maxY;
    }

    // Calculate scale
    final scaleX = minimapSize.width / maxX;
    final scaleY = minimapSize.height / maxY;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Convert minimap position to canvas position
    final canvasX = minimapPos.dx / scale;
    final canvasY = minimapPos.dy / scale;

    // Center the view on this position
    setState(() {
      _canvasOffset = Offset(
        (canvasSize.width / 2) - (canvasX * _zoom),
        (canvasSize.height / 2) - (canvasY * _zoom),
      );
    });
  }

  // ============================================================================
  // CANVAS ELEMENT CREATION
  // ============================================================================
  void _createLaneFromDrop(Map<String, dynamic> data, Offset position) {
    final template = data['template'] as LaneTemplate?;
    if (template == null) return;

    final y = _canvasLanes.isEmpty ? 20.0 : _canvasLanes.last.y + _canvasLanes.last.height + 10;

    final lane = _CanvasLane(
      id: 'lane_${_nextId++}',
      templateId: template.id,
      name: template.name,
      icon: template.icon,
      color: template.getColor(),
      type: template.type,
      role: template.defaultRole,
      y: y,
      height: 120,
    );

    setState(() {
      _canvasLanes.add(lane);
      _hasUnsavedChanges = true;
      _selectElement(lane.id, 'lane');
    });

    // Record for undo
    _history.recordAddLane(_laneToMap(lane));

    debugPrint('Created lane: ${lane.name} at y=$y');
  }

  void _createNodeFromDrop(Map<String, dynamic> data, Offset position) {
    final template = data['template'] as NodeTemplate?;
    if (template == null) return;

    // If no lanes exist, create a default lane first
    if (_canvasLanes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a Lane first, then add nodes to it'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Find which lane the node was dropped in
    _CanvasLane? targetLane;
    for (final lane in _canvasLanes) {
      if (position.dy >= lane.y && position.dy <= lane.y + lane.height) {
        targetLane = lane;
        break;
      }
    }

    // Default to last lane if not dropped in any lane
    targetLane ??= _canvasLanes.last;

    _createNodeInLane(data, targetLane.id, position);
  }

  void _createNodeInLane(Map<String, dynamic> data, String laneId, Offset position) {
    final template = data['template'] as NodeTemplate?;
    if (template == null) return;

    final lane = _canvasLanes.firstWhere((l) => l.id == laneId);

    // Calculate node position within lane
    final nodesInLane = _canvasNodes.where((n) => n.laneId == laneId).toList();
    final x = nodesInLane.isEmpty ? 70.0 : nodesInLane.last.x + nodesInLane.last.width + 20;
    final y = lane.y + 20;

    final node = _CanvasNode(
      id: 'node_${_nextId++}',
      templateId: template.id,
      name: template.name,
      icon: template.icon,
      color: _parseColor(template.color),
      category: template.category,
      laneId: laneId,
      x: x,
      y: y,
      inputPorts: template.inputPorts.map((p) => _CanvasPort(
        key: p.key,
        label: p.label,
        dataType: p.dataType,
        isInput: true,
        required: p.required,
      )).toList(),
      outputPorts: template.outputPorts.map((p) => _CanvasPort(
        key: p.key,
        label: p.label,
        dataType: p.dataType,
        isInput: false,
        required: p.required,
      )).toList(),
    );

    setState(() {
      _canvasNodes.add(node);
      lane.nodeIds.add(node.id);
      _hasUnsavedChanges = true;
      _selectElement(node.id, 'node');
    });

    // Record for undo
    _history.recordAddNode(_nodeToMap(node));

    debugPrint('Created node: ${node.name} in lane ${lane.name}');
  }

  Color _parseColor(String colorStr) {
    try {
      final hex = colorStr.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return const Color(0xFF666666);
    }
  }

  /// Convert screen coordinates to canvas coordinates (accounting for zoom/pan)
  Offset _screenToCanvas(Offset screenPos) {
    return Offset(
      (screenPos.dx - _canvasOffset.dx) / _zoom,
      (screenPos.dy - _canvasOffset.dy) / _zoom,
    );
  }

  /// Convert canvas coordinates to screen coordinates
  Offset _canvasToScreen(Offset canvasPos) {
    return Offset(
      canvasPos.dx * _zoom + _canvasOffset.dx,
      canvasPos.dy * _zoom + _canvasOffset.dy,
    );
  }

  void _moveNode(String nodeId, Offset newPosition) {
    final nodeIndex = _canvasNodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;

    setState(() {
      _canvasNodes[nodeIndex] = _canvasNodes[nodeIndex].copyWith(
        x: newPosition.dx.clamp(60, double.infinity),
        y: newPosition.dy.clamp(0, double.infinity),
      );
      _hasUnsavedChanges = true;
    });
  }

  /// Move all selected nodes by the given delta
  void _moveSelectedNodes(String draggedNodeId, Offset delta) {
    // If no nodes selected or only one, just move the dragged node
    if (_selectedNodeIds.isEmpty || (_selectedNodeIds.length == 1 && _selectedNodeIds.contains(draggedNodeId))) {
      final nodeIndex = _canvasNodes.indexWhere((n) => n.id == draggedNodeId);
      if (nodeIndex != -1) {
        final node = _canvasNodes[nodeIndex];
        setState(() {
          _canvasNodes[nodeIndex] = node.copyWith(
            x: (node.x + delta.dx).clamp(60, double.infinity),
            y: (node.y + delta.dy).clamp(0, double.infinity),
          );
          _hasUnsavedChanges = true;
        });
      }
      return;
    }

    // Move all selected nodes by the same delta
    setState(() {
      for (final nodeId in _selectedNodeIds) {
        final nodeIndex = _canvasNodes.indexWhere((n) => n.id == nodeId);
        if (nodeIndex != -1) {
          final node = _canvasNodes[nodeIndex];
          _canvasNodes[nodeIndex] = node.copyWith(
            x: (node.x + delta.dx).clamp(60, double.infinity),
            y: (node.y + delta.dy).clamp(0, double.infinity),
          );
        }
      }
      _hasUnsavedChanges = true;
    });
  }

  void _toggleLaneCollapse(String laneId) {
    final laneIndex = _canvasLanes.indexWhere((l) => l.id == laneId);
    if (laneIndex == -1) return;

    setState(() {
      _canvasLanes[laneIndex] = _canvasLanes[laneIndex].copyWith(
        isCollapsed: !_canvasLanes[laneIndex].isCollapsed,
      );
      // Recalculate Y positions for lanes below
      _recalculateLanePositions();
    });
  }

  void _recalculateLanePositions() {
    double currentY = 20;
    for (int i = 0; i < _canvasLanes.length; i++) {
      _canvasLanes[i] = _canvasLanes[i].copyWith(y: currentY);
      currentY += (_canvasLanes[i].isCollapsed ? 40 : _canvasLanes[i].height) + 10;
    }
  }

  void _selectElement(String id, String type, {bool addToSelection = false}) {
    setState(() {
      if (addToSelection) {
        // Toggle selection for multi-select
        if (type == 'node') {
          if (_selectedNodeIds.contains(id)) {
            _selectedNodeIds.remove(id);
          } else {
            _selectedNodeIds.add(id);
          }
          // Clear other selection types when adding nodes
          _selectedWireIds.clear();
          _selectedLaneId = null;
        } else if (type == 'wire') {
          if (_selectedWireIds.contains(id)) {
            _selectedWireIds.remove(id);
          } else {
            _selectedWireIds.add(id);
          }
          _selectedNodeIds.clear();
          _selectedLaneId = null;
        } else if (type == 'lane') {
          // Lanes don't support multi-select
          _selectedLaneId = id;
          _selectedNodeIds.clear();
          _selectedWireIds.clear();
        }
      } else {
        // Single selection - clear all and select new
        _selectedNodeIds.clear();
        _selectedWireIds.clear();
        _selectedLaneId = null;

        if (type == 'node') {
          _selectedNodeIds.add(id);
        } else if (type == 'wire') {
          _selectedWireIds.add(id);
        } else if (type == 'lane') {
          _selectedLaneId = id;
        }
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedNodeIds.clear();
      _selectedWireIds.clear();
      _selectedLaneId = null;
    });
  }

  bool _isNodeSelected(String nodeId) => _selectedNodeIds.contains(nodeId);
  bool _isWireSelected(String wireId) => _selectedWireIds.contains(wireId);
  bool _isLaneSelected(String laneId) => _selectedLaneId == laneId;

  int get _totalSelectedCount => _selectedNodeIds.length + _selectedWireIds.length + (_selectedLaneId != null ? 1 : 0);

  /// Select all nodes within the rectangle selection area
  void _selectNodesInRectangle() {
    // Calculate the normalized rectangle (handle dragging in any direction)
    final left = _rectangleSelectStart.dx < _rectangleSelectEnd.dx
        ? _rectangleSelectStart.dx
        : _rectangleSelectEnd.dx;
    final top = _rectangleSelectStart.dy < _rectangleSelectEnd.dy
        ? _rectangleSelectStart.dy
        : _rectangleSelectEnd.dy;
    final right = _rectangleSelectStart.dx > _rectangleSelectEnd.dx
        ? _rectangleSelectStart.dx
        : _rectangleSelectEnd.dx;
    final bottom = _rectangleSelectStart.dy > _rectangleSelectEnd.dy
        ? _rectangleSelectStart.dy
        : _rectangleSelectEnd.dy;

    final selectionRect = Rect.fromLTRB(left, top, right, bottom);

    // Find all nodes that intersect with the selection rectangle
    final nodesInRect = <String>[];
    for (final node in _canvasNodes) {
      final nodeRect = Rect.fromLTWH(node.x, node.y, node.width, node.height);
      if (selectionRect.overlaps(nodeRect)) {
        nodesInRect.add(node.id);
      }
    }

    // Check if Shift is pressed for additive selection
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    setState(() {
      if (!isShiftPressed) {
        // Clear existing selection if Shift is not pressed
        _selectedNodeIds.clear();
      }
      _selectedWireIds.clear();
      _selectedLaneId = null;

      // Add all nodes in the rectangle to selection
      _selectedNodeIds.addAll(nodesInRect);
    });
  }

  // ============================================================================
  // RIGHT PANEL - Settings
  // ============================================================================
  Widget _buildRightPanel() {
    // Collapsed state
    if (_isRightPanelCollapsed) {
      return Container(
        width: 40,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: Color(0xFFE0E0E0))),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _isRightPanelCollapsed = false),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.chevron_left, size: 20, color: Color(0xFF666666)),
              ),
            ),
            const RotatedBox(
              quarterTurns: 1,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'SETTINGS',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: _rightPanelWidth,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              children: [
                const Text(
                  'SETTINGS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF999999),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _isRightPanelCollapsed = true),
                  child: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
          // Settings content
          Expanded(
            child: _selectedElementId == null
                ? _buildCanvasSettings()
                : _buildElementSettings(),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'CANVAS SETTINGS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF999999),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          // Name field
          const Text('Name', style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
          const SizedBox(height: 4),
          TextField(
            controller: TextEditingController(text: _canvasName),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => setState(() {
              _canvasName = value;
              _hasUnsavedChanges = true;
            }),
          ),
          const SizedBox(height: 16),
          // Description field
          const Text('Description', style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
          const SizedBox(height: 4),
          TextField(
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Optional description...',
              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'DISPLAY OPTIONS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF999999),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          // Grid toggle
          _buildSettingToggle(label: 'Show Grid', value: true, onChanged: (v) {}),
          _buildSettingToggle(label: 'Snap to Grid', value: true, onChanged: (v) {}),
          _buildSettingToggle(label: 'Show Minimap', value: true, onChanged: (v) {}),
          const SizedBox(height: 16),
          // Grid size
          const Text('Grid Size', style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
          const SizedBox(height: 8),
          Slider(
            value: 20,
            min: 10,
            max: 50,
            divisions: 4,
            label: '20px',
            onChanged: (v) {},
          ),
        ],
      ),
    );
  }

  Widget _buildElementSettings() {
    if (_selectedElementType == 'lane') {
      return _buildLaneSettings();
    } else if (_selectedElementType == 'node') {
      return _buildNodeSettings();
    } else if (_selectedElementType == 'wire') {
      return _buildWireSettings();
    }
    return const Center(
      child: Text(
        'Select an element to configure',
        style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
      ),
    );
  }

  Widget _buildWireSettings() {
    final wire = _canvasWires.firstWhere(
      (w) => w.id == _selectedElementId,
      orElse: () => _canvasWires.first,
    );

    final fromNode = _canvasNodes.firstWhere((n) => n.id == wire.fromNodeId);
    final toNode = _canvasNodes.firstWhere((n) => n.id == wire.toNodeId);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF666666).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(Icons.linear_scale, size: 18, color: Color(0xFF666666)),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wire Connection',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'DATA FLOW',
                      style: TextStyle(fontSize: 10, color: Color(0xFF666666)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          // Connection Info
          const Text(
            'CONNECTION',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          // From
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FROM', style: TextStyle(fontSize: 9, color: Color(0xFF999999))),
                      Text(
                        fromNode.name,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        wire.fromPortKey,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF666666), fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
                Text(fromNode.icon, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
          // Arrow
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Icon(Icons.arrow_downward, color: Color(0xFFCCCCCC), size: 20),
            ),
          ),
          // To
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TO', style: TextStyle(fontSize: 9, color: Color(0xFF999999))),
                      Text(
                        toNode.name,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        wire.toPortKey,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF666666), fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
                Text(toNode.icon, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          // Statistics
          const Text(
            'DETAILS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          _buildStatRow('Wire ID', wire.id),
          _buildStatRow('From Node', wire.fromNodeId),
          _buildStatRow('To Node', wire.toNodeId),
          const SizedBox(height: 24),
          // Delete button
          OutlinedButton.icon(
            onPressed: () => _deleteWire(wire.id),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete Wire'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteWire(String wireId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Wire?'),
        content: const Text('This will disconnect the nodes. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _canvasWires.removeWhere((w) => w.id == wireId);
                _clearSelection();
                _hasUnsavedChanges = true;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildLaneSettings() {
    final lane = _canvasLanes.firstWhere(
      (l) => l.id == _selectedElementId,
      orElse: () => _canvasLanes.first,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with icon and type
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: lane.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text(lane.icon, style: const TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lane.type.name.toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: lane.color),
                    ),
                    Text(
                      lane.role.name,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF999999)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          // Lane name
          const Text(
            'LANE PROPERTIES',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          _buildPropertyTextField(
            label: 'Name',
            value: lane.name,
            onChanged: (value) => _updateLaneProperty(lane.id, 'name', value),
          ),
          const SizedBox(height: 12),
          _buildPropertySlider(
            label: 'Height',
            value: lane.height,
            min: 80,
            max: 300,
            divisions: 22,
            suffix: 'px',
            onChanged: (value) => _updateLaneProperty(lane.id, 'height', value),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          // Lane config based on type
          const Text(
            'EXECUTION CONFIG',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          if (lane.type == LaneType.rules) ...[
            _buildPropertyDropdown(
              label: 'Execution Mode',
              value: 'sequential',
              options: const ['sequential', 'parallel'],
              onChanged: (value) {},
            ),
            const SizedBox(height: 12),
            _buildPropertyDropdown(
              label: 'On Error',
              value: 'continue',
              options: const ['continue', 'stop', 'retry'],
              onChanged: (value) {},
            ),
          ] else if (lane.type == LaneType.llm) ...[
            _buildPropertyDropdown(
              label: 'Provider',
              value: 'groq',
              options: const ['groq', 'openai', 'anthropic', 'google'],
              onChanged: (value) {},
            ),
            const SizedBox(height: 12),
            _buildPropertyTextField(
              label: 'Model',
              value: 'llama-3.3-70b-versatile',
              onChanged: (value) {},
            ),
            const SizedBox(height: 12),
            _buildPropertySlider(
              label: 'Temperature',
              value: 0.3,
              min: 0,
              max: 1,
              divisions: 10,
              onChanged: (value) {},
            ),
          ] else if (lane.type == LaneType.database) ...[
            _buildPropertyDropdown(
              label: 'Primary Source',
              value: 'firestore',
              options: const ['firestore', 'redis', 'postgres'],
              onChanged: (value) {},
            ),
            const SizedBox(height: 12),
            _buildSettingToggle(
              label: 'Cache Results',
              value: true,
              onChanged: (value) {},
            ),
          ],
          const SizedBox(height: 12),
          _buildPropertySlider(
            label: 'Timeout',
            value: 500,
            min: 100,
            max: 10000,
            divisions: 99,
            suffix: 'ms',
            onChanged: (value) {},
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          // Statistics
          const Text(
            'STATISTICS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          _buildStatRow('Nodes', '${lane.nodeIds.length}'),
          _buildStatRow('ID', lane.id),
          const SizedBox(height: 24),
          // Delete button
          OutlinedButton.icon(
            onPressed: () => _deleteLane(lane.id),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete Lane'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeSettings() {
    final node = _canvasNodes.firstWhere(
      (n) => n.id == _selectedElementId,
      orElse: () => _canvasNodes.first,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with icon
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: node.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text(node.icon, style: const TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      node.category.name.toUpperCase(),
                      style: TextStyle(fontSize: 10, color: node.color),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          // Input Ports
          if (node.inputPorts.isNotEmpty) ...[
            const Text(
              'INPUT PORTS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            ...node.inputPorts.map((port) => _buildPortInfo(port, isInput: true)),
            const SizedBox(height: 16),
          ],
          // Output Ports
          if (node.outputPorts.isNotEmpty) ...[
            const Text(
              'OUTPUT PORTS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            ...node.outputPorts.map((port) => _buildPortInfo(port, isInput: false)),
            const SizedBox(height: 16),
          ],
          const Divider(),
          const SizedBox(height: 16),
          // Node properties
          const Text(
            'NODE PROPERTIES',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          _buildSettingToggle(
            label: 'Enabled',
            value: true,
            onChanged: (value) {},
          ),
          const SizedBox(height: 8),
          _buildPropertyTextField(
            label: 'Description',
            value: '',
            hint: 'Optional description...',
            maxLines: 2,
            onChanged: (value) {},
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          // Position info
          const Text(
            'POSITION',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999), letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildPropertyTextField(
                  label: 'X',
                  value: node.x.toStringAsFixed(0),
                  onChanged: (value) {
                    final x = double.tryParse(value);
                    if (x != null) _updateNodePosition(node.id, x, node.y);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPropertyTextField(
                  label: 'Y',
                  value: node.y.toStringAsFixed(0),
                  onChanged: (value) {
                    final y = double.tryParse(value);
                    if (y != null) _updateNodePosition(node.id, node.x, y);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Statistics
          _buildStatRow('ID', node.id),
          _buildStatRow('Template', node.templateId),
          if (node.laneId != null) _buildStatRow('Lane', node.laneId!),
          const SizedBox(height: 24),
          // Delete button
          OutlinedButton.icon(
            onPressed: () => _deleteNode(node.id),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete Node'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortInfo(_CanvasPort port, {required bool isInput}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isInput ? Colors.green : Colors.orange,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              port.label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              port.dataType.name,
              style: const TextStyle(fontSize: 9, color: Color(0xFF666666)),
            ),
          ),
          if (port.required) ...[
            const SizedBox(width: 4),
            const Text('*', style: TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildPropertyTextField({
    required String label,
    required String value,
    String? hint,
    int maxLines = 1,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF666666))),
        const SizedBox(height: 4),
        TextField(
          controller: TextEditingController(text: value),
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFCCCCCC)),
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
          ),
          style: const TextStyle(fontSize: 12),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildPropertySlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    String? suffix,
    required Function(double) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF666666))),
            Text(
              '${value.toStringAsFixed(value < 10 ? 1 : 0)}${suffix ?? ''}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF333333), fontWeight: FontWeight.w500),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: const Color(0xFF2196F3),
            inactiveTrackColor: const Color(0xFFE0E0E0),
            thumbColor: const Color(0xFF2196F3),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildPropertyDropdown({
    required String label,
    required String value,
    required List<String> options,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF666666))),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.expand_more, size: 18),
              style: const TextStyle(fontSize: 12, color: Color(0xFF333333)),
              items: options.map((opt) => DropdownMenuItem(
                value: opt,
                child: Text(opt),
              )).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF999999))),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, color: Color(0xFF666666), fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _updateLaneProperty(String laneId, String property, dynamic value) {
    final laneIndex = _canvasLanes.indexWhere((l) => l.id == laneId);
    if (laneIndex == -1) return;

    setState(() {
      switch (property) {
        case 'name':
          _canvasLanes[laneIndex] = _canvasLanes[laneIndex].copyWith(name: value as String);
          break;
        case 'height':
          _canvasLanes[laneIndex] = _canvasLanes[laneIndex].copyWith(height: value as double);
          _recalculateLanePositions();
          break;
      }
      _hasUnsavedChanges = true;
    });
  }

  void _updateNodePosition(String nodeId, double x, double y) {
    final nodeIndex = _canvasNodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;

    setState(() {
      _canvasNodes[nodeIndex] = _canvasNodes[nodeIndex].copyWith(x: x, y: y);
      _hasUnsavedChanges = true;
    });
  }

  void _deleteLane(String laneId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Lane?'),
        content: const Text('This will also delete all nodes within this lane. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                // Remove all nodes in this lane
                _canvasNodes.removeWhere((n) => n.laneId == laneId);
                // Remove the lane
                _canvasLanes.removeWhere((l) => l.id == laneId);
                // Recalculate positions
                _recalculateLanePositions();
                // Clear selection
                _clearSelection();
                _hasUnsavedChanges = true;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteNode(String nodeId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Node?'),
        content: const Text('This will also remove any connected wires. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                // Find the node to get its lane
                final node = _canvasNodes.firstWhere((n) => n.id == nodeId);
                // Remove from lane's nodeIds
                if (node.laneId != null) {
                  final lane = _canvasLanes.firstWhere((l) => l.id == node.laneId);
                  lane.nodeIds.remove(nodeId);
                }
                // Remove wires connected to this node
                _canvasWires.removeWhere((w) => w.fromNodeId == nodeId || w.toNodeId == nodeId);
                // Remove the node
                _canvasNodes.removeWhere((n) => n.id == nodeId);
                // Clear selection
                _clearSelection();
                _hasUnsavedChanges = true;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingToggle({
    required String label,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF2196F3),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // TEST PANEL
  // ============================================================================
  Widget _buildTestPanel() {
    if (_isTestPanelCollapsed) {
      return _buildCollapsedTestPanel();
    }

    return Container(
      height: _testPanelHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Column(
        children: [
          // Test panel header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFA),
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              children: [
                Icon(
                  _isExecuting ? Icons.play_circle : Icons.science_outlined,
                  size: 16,
                  color: _isExecuting ? const Color(0xFF4CAF50) : const Color(0xFF666666),
                ),
                const SizedBox(width: 8),
                Text(
                  _isExecuting ? 'RUNNING...' : 'TEST PANEL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _isExecuting ? const Color(0xFF4CAF50) : const Color(0xFF666666),
                    letterSpacing: 0.5,
                  ),
                ),
                if (_isExecuting) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                const Spacer(),
                // Execution mode toggle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: _executionMode == executor.ExecutionMode.live
                        ? const Color(0xFFE3F2FD)
                        : const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildModeButton(
                        label: 'Simulated',
                        isSelected: _executionMode == executor.ExecutionMode.simulated,
                        onTap: _isExecuting ? null : () {
                          setState(() {
                            _executionMode = executor.ExecutionMode.simulated;
                            _executor.setMode(executor.ExecutionMode.simulated);
                          });
                        },
                      ),
                      _buildModeButton(
                        label: 'Live',
                        isSelected: _executionMode == executor.ExecutionMode.live,
                        onTap: _isExecuting ? null : () {
                          setState(() {
                            _executionMode = executor.ExecutionMode.live;
                            _executor.setMode(executor.ExecutionMode.live);
                          });
                        },
                        isLive: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (_executionTrace.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearExecutionState,
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF999999),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.expand_more, size: 18),
                  onPressed: () => setState(() => _isTestPanelCollapsed = true),
                  tooltip: 'Collapse',
                  color: const Color(0xFF666666),
                ),
              ],
            ),
          ),
          // Test panel content
          Expanded(
            child: Row(
              children: [
                // Input section
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: Color(0xFFE0E0E0))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('INPUT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999))),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TextField(
                            controller: _testInputController,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            enabled: !_isExecuting,
                            decoration: InputDecoration(
                              hintText: '{\n  "message": "Hello",\n  "userId": "user_123"\n}',
                              hintStyle: const TextStyle(fontSize: 11, color: Color(0xFFCCCCCC), fontFamily: 'monospace'),
                              filled: true,
                              fillColor: _isExecuting ? const Color(0xFFEEEEEE) : const Color(0xFFFAFAFA),
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                              ),
                            ),
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (_isExecuting)
                              ElevatedButton.icon(
                                onPressed: _stopExecution,
                                icon: const Icon(Icons.stop, size: 16),
                                label: const Text('Stop'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              )
                            else
                              ElevatedButton.icon(
                                onPressed: _canvasNodes.isEmpty ? null : () => _runPipeline(stepMode: false),
                                icon: const Icon(Icons.play_arrow, size: 16),
                                label: const Text('Run'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CAF50),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            const SizedBox(width: 8),
                            if (_isExecuting && _isStepMode)
                              OutlinedButton.icon(
                                onPressed: _executor.isPaused ? _stepExecution : null,
                                icon: const Icon(Icons.skip_next, size: 16),
                                label: const Text('Next'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF2196F3),
                                  side: const BorderSide(color: Color(0xFF2196F3)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              )
                            else if (!_isExecuting)
                              OutlinedButton.icon(
                                onPressed: _canvasNodes.isEmpty ? null : () => _runPipeline(stepMode: true),
                                icon: const Icon(Icons.skip_next, size: 16),
                                label: const Text('Step'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF666666),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Execution trace
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: Color(0xFFE0E0E0))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Text('EXECUTION TRACE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999))),
                            const Spacer(),
                            if (_executionTrace.isNotEmpty)
                              Text(
                                '${_executionTrace.length} steps',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF999999)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFAFA),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE0E0E0)),
                            ),
                            child: _executionTrace.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Run a test to see execution trace',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(8),
                                    itemCount: _executionTrace.length,
                                    itemBuilder: (context, index) => _buildTraceItem(_executionTrace[index], index),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Output section
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('OUTPUT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF999999))),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFAFA),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE0E0E0)),
                            ),
                            child: _executionOutput.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Output will appear here',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
                                    ),
                                  )
                                : SingleChildScrollView(
                                    child: SelectableText(
                                      const JsonEncoder.withIndent('  ').convert(_executionOutput),
                                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF333333)),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTraceItem(executor.NodeExecutionResult result, int index) {
    final stateColor = _getExecutionStateColor(result.state);
    final stateIcon = _getExecutionStateIcon(result.state);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: stateColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(stateIcon, size: 12, color: stateColor),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.nodeName,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${result.duration.inMilliseconds}ms',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
          Text(
            '#${index + 1}',
            style: const TextStyle(fontSize: 9, color: Color(0xFFCCCCCC)),
          ),
        ],
      ),
    );
  }

  Color _getExecutionStateColor(executor.NodeExecutionState state) {
    switch (state) {
      case executor.NodeExecutionState.idle:
        return const Color(0xFF999999);
      case executor.NodeExecutionState.pending:
        return const Color(0xFFFF9800);
      case executor.NodeExecutionState.running:
        return const Color(0xFF2196F3);
      case executor.NodeExecutionState.completed:
        return const Color(0xFF4CAF50);
      case executor.NodeExecutionState.error:
        return const Color(0xFFF44336);
      case executor.NodeExecutionState.skipped:
        return const Color(0xFF9E9E9E);
    }
  }

  IconData _getExecutionStateIcon(executor.NodeExecutionState state) {
    switch (state) {
      case executor.NodeExecutionState.idle:
        return Icons.circle_outlined;
      case executor.NodeExecutionState.pending:
        return Icons.schedule;
      case executor.NodeExecutionState.running:
        return Icons.play_arrow;
      case executor.NodeExecutionState.completed:
        return Icons.check;
      case executor.NodeExecutionState.error:
        return Icons.error_outline;
      case executor.NodeExecutionState.skipped:
        return Icons.skip_next;
    }
  }

  Widget _buildCollapsedTestPanel() {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: InkWell(
        onTap: () => setState(() => _isTestPanelCollapsed = false),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.expand_less, size: 18, color: Color(0xFF666666)),
            SizedBox(width: 8),
            Text(
              'TEST PANEL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF666666),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // DIVIDERS
  // ============================================================================
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

  Widget _buildHorizontalDivider({required Function(double) onDrag}) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        child: Container(
          height: 8,
          color: Colors.transparent,
          child: Center(
            child: Container(
              height: 4,
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

  // ============================================================================
  // ACTIONS
  // ============================================================================
  void _showRenameDialog() {
    final controller = TextEditingController(text: _canvasName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Pipeline'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _canvasName = controller.text;
                _hasUnsavedChanges = true;
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // FILE OPERATIONS
  // ============================================================================

  void _newCanvas() {
    if (_hasUnsavedChanges) {
      _showUnsavedChangesDialog(() {
        _resetCanvas();
      });
    } else {
      _resetCanvas();
    }
  }

  void _resetCanvas() {
    setState(() {
      _currentCanvasId = null;
      _canvasName = 'Untitled Pipeline';
      _canvasLanes.clear();
      _canvasNodes.clear();
      _canvasWires.clear();
      _nextId = 1;
      _hasUnsavedChanges = false;
      _clearSelection();
    });
  }

  void _showOpenDialog() async {
    if (_hasUnsavedChanges) {
      _showUnsavedChangesDialog(() {
        _showCanvasPickerDialog();
      });
    } else {
      _showCanvasPickerDialog();
    }
  }

  void _showCanvasPickerDialog() async {
    final canvases = await _canvasService.getCanvases();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.folder_open, color: Color(0xFF2196F3)),
            SizedBox(width: 8),
            Text('Open Canvas'),
          ],
        ),
        content: SizedBox(
          width: 400,
          height: 300,
          child: canvases.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_off, size: 48, color: Color(0xFFCCCCCC)),
                      SizedBox(height: 16),
                      Text('No saved canvases', style: TextStyle(color: Color(0xFF999999))),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: canvases.length,
                  itemBuilder: (context, index) {
                    final canvas = canvases[index];
                    return ListTile(
                      leading: const Icon(Icons.dashboard_customize, color: Color(0xFF2196F3)),
                      title: Text(canvas.name),
                      subtitle: Text(
                        '${canvas.lanes.length} lanes, ${canvas.nodes.length} nodes • ${_formatDate(canvas.updatedAt)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _confirmDeleteCanvas(canvas.id, canvas.name, () {
                              Navigator.pop(context);
                              _showCanvasPickerDialog();
                            }),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _loadCanvas(canvas.id);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }

  void _confirmDeleteCanvas(String id, String name, VoidCallback onDeleted) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Canvas?'),
        content: Text('Are you sure you want to delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _canvasService.deleteCanvas(id);
              onDeleted();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Canvas deleted'), backgroundColor: Colors.orange),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCanvas(String id) async {
    final canvas = await _canvasService.getCanvas(id);
    if (canvas == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load canvas'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    setState(() {
      _currentCanvasId = canvas.id;
      _canvasName = canvas.name;
      _hasUnsavedChanges = false;

      // Convert lanes
      _canvasLanes = canvas.lanes.map((l) => _CanvasLane(
        id: l.id,
        templateId: l.templateId,
        name: l.name,
        icon: l.icon,
        color: _parseColor(l.color),
        type: LaneType.values.firstWhere((t) => t.name == l.type, orElse: () => LaneType.rules),
        role: LaneRole.values.firstWhere((r) => r.name == l.role, orElse: () => LaneRole.executor),
        y: l.y,
        height: l.height,
        isCollapsed: l.isCollapsed,
        nodeIds: List.from(l.nodeIds),
      )).toList();

      // Convert nodes
      _canvasNodes = canvas.nodes.map((n) => _CanvasNode(
        id: n.id,
        templateId: n.templateId,
        name: n.name,
        icon: n.icon,
        color: _parseColor(n.color),
        category: NodeCategory.values.firstWhere((c) => c.name == n.category, orElse: () => NodeCategory.logic),
        laneId: n.laneId,
        x: n.x,
        y: n.y,
        width: n.width,
        height: n.height,
        inputPorts: n.inputPorts.map((p) => _CanvasPort(
          key: p.key,
          label: p.label,
          dataType: PortDataType.values.firstWhere((d) => d.name == p.dataType, orElse: () => PortDataType.any),
          isInput: true,
          required: p.required,
        )).toList(),
        outputPorts: n.outputPorts.map((p) => _CanvasPort(
          key: p.key,
          label: p.label,
          dataType: PortDataType.values.firstWhere((d) => d.name == p.dataType, orElse: () => PortDataType.any),
          isInput: false,
          required: p.required,
        )).toList(),
      )).toList();

      // Convert wires
      _canvasWires = canvas.wires.map((w) => _CanvasWire(
        id: w.id,
        fromNodeId: w.fromNodeId,
        fromPortKey: w.fromPortKey,
        toNodeId: w.toNodeId,
        toPortKey: w.toPortKey,
        color: w.color != null ? _parseColor(w.color!) : const Color(0xFF666666),
      )).toList();

      // Update next ID
      _nextId = 1;
      for (final lane in _canvasLanes) {
        final num = int.tryParse(lane.id.split('_').last) ?? 0;
        if (num >= _nextId) _nextId = num + 1;
      }
      for (final node in _canvasNodes) {
        final num = int.tryParse(node.id.split('_').last) ?? 0;
        if (num >= _nextId) _nextId = num + 1;
      }
      for (final wire in _canvasWires) {
        final num = int.tryParse(wire.id.split('_').last) ?? 0;
        if (num >= _nextId) _nextId = num + 1;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded "${canvas.name}"'), backgroundColor: Colors.green),
      );
    }
  }

  /// Load a canvas directly from a CanvasConfig (used for snapshot restore)
  Future<void> _loadCanvasFromConfig(canvas_svc.CanvasConfig canvas) async {
    setState(() {
      _currentCanvasId = canvas.id;
      _canvasName = canvas.name;
      _hasUnsavedChanges = true; // Mark as unsaved since it's restored

      // Convert lanes
      _canvasLanes = canvas.lanes.map((l) => _CanvasLane(
        id: l.id,
        templateId: l.templateId,
        name: l.name,
        icon: l.icon,
        color: _parseColor(l.color),
        type: LaneType.values.firstWhere((t) => t.name == l.type, orElse: () => LaneType.rules),
        role: LaneRole.values.firstWhere((r) => r.name == l.role, orElse: () => LaneRole.executor),
        y: l.y,
        height: l.height,
        isCollapsed: l.isCollapsed,
        nodeIds: List.from(l.nodeIds),
      )).toList();

      // Convert nodes
      _canvasNodes = canvas.nodes.map((n) => _CanvasNode(
        id: n.id,
        templateId: n.templateId,
        name: n.name,
        icon: n.icon,
        color: _parseColor(n.color),
        category: NodeCategory.values.firstWhere((c) => c.name == n.category, orElse: () => NodeCategory.logic),
        laneId: n.laneId,
        x: n.x,
        y: n.y,
        width: n.width,
        height: n.height,
        inputPorts: n.inputPorts.map((p) => _CanvasPort(
          key: p.key,
          label: p.label,
          dataType: PortDataType.values.firstWhere((d) => d.name == p.dataType, orElse: () => PortDataType.any),
          isInput: true,
          required: p.required,
        )).toList(),
        outputPorts: n.outputPorts.map((p) => _CanvasPort(
          key: p.key,
          label: p.label,
          dataType: PortDataType.values.firstWhere((d) => d.name == p.dataType, orElse: () => PortDataType.any),
          isInput: false,
          required: p.required,
        )).toList(),
      )).toList();

      // Convert wires
      _canvasWires = canvas.wires.map((w) => _CanvasWire(
        id: w.id,
        fromNodeId: w.fromNodeId,
        fromPortKey: w.fromPortKey,
        toNodeId: w.toNodeId,
        toPortKey: w.toPortKey,
        color: w.color != null ? _parseColor(w.color!) : const Color(0xFF666666),
      )).toList();

      // Update next ID
      _nextId = 1;
      for (final lane in _canvasLanes) {
        final num = int.tryParse(lane.id.split('_').last) ?? 0;
        if (num >= _nextId) _nextId = num + 1;
      }
      for (final node in _canvasNodes) {
        final num = int.tryParse(node.id.split('_').last) ?? 0;
        if (num >= _nextId) _nextId = num + 1;
      }
      for (final wire in _canvasWires) {
        final num = int.tryParse(wire.id.split('_').last) ?? 0;
        if (num >= _nextId) _nextId = num + 1;
      }
    });
  }

  Future<void> _saveCanvas() async {
    if (_canvasName.isEmpty || _canvasName == 'Untitled Pipeline') {
      _showSaveAsDialog();
      return;
    }

    setState(() => _isSaving = true);

    try {
      final config = _buildCanvasConfig();
      final id = await _canvasService.saveCanvas(config);

      setState(() {
        _currentCanvasId = id;
        _hasUnsavedChanges = false;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Canvas saved'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showSaveAsDialog() {
    final controller = TextEditingController(text: _canvasName == 'Untitled Pipeline' ? '' : _canvasName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Canvas As'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Canvas Name',
            hintText: 'Enter a name for this canvas',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isEmpty) return;

              Navigator.pop(context);
              setState(() {
                _canvasName = controller.text;
                _currentCanvasId = null; // Create new
              });
              await _saveCanvas();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showKeyboardShortcuts() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.keyboard, color: Color(0xFF666666)),
            const SizedBox(width: 8),
            const Text('Keyboard Shortcuts'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildShortcutSection('General', [
                  ('Ctrl + S', 'Save canvas'),
                  ('Ctrl + Z', 'Undo'),
                  ('Ctrl + Y', 'Redo'),
                  ('Ctrl + Shift + Z', 'Redo'),
                  ('Delete / Backspace', 'Delete selected element'),
                  ('Escape', 'Cancel current action / Deselect'),
                ]),
                const SizedBox(height: 16),
                _buildShortcutSection('Navigation', [
                  ('Space + Drag', 'Pan canvas'),
                  ('Scroll Wheel', 'Zoom in/out'),
                  ('Click zoom %', 'Reset view'),
                  ('Fit All button', 'Zoom to fit all elements'),
                ]),
                const SizedBox(height: 16),
                _buildShortcutSection('Selection', [
                  ('Click', 'Select node or lane'),
                  ('Drag on canvas', 'Rectangle select'),
                  ('Ctrl + Click', 'Multi-select nodes'),
                ]),
                const SizedBox(height: 16),
                _buildShortcutSection('Wiring', [
                  ('Drag from port', 'Start wire connection'),
                  ('Release on port', 'Complete connection'),
                  ('Release on empty', 'Cancel wire'),
                ]),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutSection(String title, List<(String, String)> shortcuts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF666666),
          ),
        ),
        const SizedBox(height: 8),
        ...shortcuts.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Text(
                  s.$1,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                s.$2,
                style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
              ),
            ],
          ),
        )),
      ],
    );
  }

  canvas_svc.CanvasConfig _buildCanvasConfig() {
    return canvas_svc.CanvasConfig(
      id: _currentCanvasId ?? '',
      name: _canvasName,
      lanes: _canvasLanes.map((l) => canvas_svc.LaneConfig(
        id: l.id,
        templateId: l.templateId,
        name: l.name,
        icon: l.icon,
        color: '#${l.color.value.toRadixString(16).substring(2)}',
        type: l.type.name,
        role: l.role.name,
        y: l.y,
        height: l.height,
        isCollapsed: l.isCollapsed,
        nodeIds: l.nodeIds,
      )).toList(),
      nodes: _canvasNodes.map((n) => canvas_svc.NodeConfig(
        id: n.id,
        templateId: n.templateId,
        name: n.name,
        icon: n.icon,
        color: '#${n.color.value.toRadixString(16).substring(2)}',
        category: n.category.name,
        laneId: n.laneId,
        x: n.x,
        y: n.y,
        width: n.width,
        height: n.height,
        inputPorts: n.inputPorts.map((p) => canvas_svc.PortConfig(
          key: p.key,
          label: p.label,
          dataType: p.dataType.name,
          required: p.required,
        )).toList(),
        outputPorts: n.outputPorts.map((p) => canvas_svc.PortConfig(
          key: p.key,
          label: p.label,
          dataType: p.dataType.name,
          required: p.required,
        )).toList(),
        properties: n.properties,
      )).toList(),
      wires: _canvasWires.map((w) => canvas_svc.WireConfig(
        id: w.id,
        fromNodeId: w.fromNodeId,
        fromPortKey: w.fromPortKey,
        toNodeId: w.toNodeId,
        toPortKey: w.toPortKey,
        color: '#${w.color.value.toRadixString(16).substring(2)}',
      )).toList(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // ============================================================================
  // EXPORT / IMPORT
  // ============================================================================

  /// Export the current pipeline to a JSON file for download
  Future<void> _exportPipeline() async {
    if (_canvasNodes.isEmpty && _canvasLanes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to export - canvas is empty'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Build lane data
      final lanesData = _canvasLanes.map((l) {
        return <String, dynamic>{
          'id': l.id,
          'templateId': l.templateId,
          'name': l.name,
          'icon': l.icon,
          'color': '#${l.color.value.toRadixString(16).substring(2)}',
          'type': l.type.name,
          'role': l.role.name,
          'y': l.y,
          'height': l.height,
          'isCollapsed': l.isCollapsed,
          'nodeIds': l.nodeIds,
        };
      }).toList();

      // Build node data
      final nodesData = _canvasNodes.map((n) {
        final inputPortsData = n.inputPorts.map((p) {
          return <String, dynamic>{
            'key': p.key,
            'label': p.label,
            'dataType': p.dataType.name,
            'required': p.required,
          };
        }).toList();

        final outputPortsData = n.outputPorts.map((p) {
          return <String, dynamic>{
            'key': p.key,
            'label': p.label,
            'dataType': p.dataType.name,
            'required': p.required,
          };
        }).toList();

        return <String, dynamic>{
          'id': n.id,
          'templateId': n.templateId,
          'name': n.name,
          'icon': n.icon,
          'color': '#${n.color.value.toRadixString(16).substring(2)}',
          'category': n.category.name,
          'laneId': n.laneId,
          'x': n.x,
          'y': n.y,
          'width': n.width,
          'height': n.height,
          'inputPorts': inputPortsData,
          'outputPorts': outputPortsData,
          'properties': n.properties,
        };
      }).toList();

      // Build wire data
      final wiresData = _canvasWires.map((w) {
        return <String, dynamic>{
          'id': w.id,
          'fromNodeId': w.fromNodeId,
          'fromPortKey': w.fromPortKey,
          'toNodeId': w.toNodeId,
          'toPortKey': w.toPortKey,
          'color': '#${w.color.value.toRadixString(16).substring(2)}',
        };
      }).toList();

      // Build the export data
      final exportData = <String, dynamic>{
        'version': '1.0',
        'name': _canvasName,
        'exportedAt': DateTime.now().toIso8601String(),
        'canvas': <String, dynamic>{
          'lanes': lanesData,
          'nodes': nodesData,
          'wires': wiresData,
        },
        'settings': <String, dynamic>{
          'zoom': _zoom,
          'offset': <String, dynamic>{'x': _canvasOffset.dx, 'y': _canvasOffset.dy},
        },
      };

      // Convert to pretty JSON
      const encoder = JsonEncoder.withIndent('  ');
      final jsonString = encoder.convert(exportData);
      final bytes = utf8.encode(jsonString);

      // Generate filename
      final sanitizedName = _canvasName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final filename = '${sanitizedName}_$timestamp.json';

      // Save using file picker
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Pipeline',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(bytes),
      );

      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pipeline exported successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Import a pipeline from a JSON file
  Future<void> _importPipeline() async {
    // Warn about unsaved changes
    if (_hasUnsavedChanges) {
      _showUnsavedChangesDialog(() => _performImport());
      return;
    }
    await _performImport();
  }

  Future<void> _performImport() async {
    try {
      // Pick a file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        throw Exception('Could not read file data');
      }

      // Parse JSON
      final jsonString = utf8.decode(file.bytes!);
      final data = json.decode(jsonString) as Map<String, dynamic>;

      // Validate version
      final version = data['version'] as String?;
      if (version == null) {
        throw Exception('Invalid file format: missing version');
      }

      final canvasData = data['canvas'] as Map<String, dynamic>?;
      if (canvasData == null) {
        throw Exception('Invalid file format: missing canvas data');
      }

      // Import lanes
      final importedLanes = <_CanvasLane>[];
      final lanesData = canvasData['lanes'] as List<dynamic>? ?? [];
      for (final laneData in lanesData) {
        final l = laneData as Map<String, dynamic>;
        importedLanes.add(_CanvasLane(
          id: l['id'] as String,
          templateId: l['templateId'] as String? ?? '',
          name: l['name'] as String,
          icon: l['icon'] as String? ?? '',
          color: _parseColor(l['color'] as String? ?? '#666666'),
          type: _parseLaneTypeFromString(l['type'] as String? ?? 'rules'),
          role: _parseLaneRoleFromString(l['role'] as String? ?? 'executor'),
          y: (l['y'] as num?)?.toDouble() ?? 0,
          height: (l['height'] as num?)?.toDouble() ?? 120,
          isCollapsed: l['isCollapsed'] as bool? ?? false,
          nodeIds: List<String>.from(l['nodeIds'] ?? []),
        ));
      }

      // Import nodes
      final importedNodes = <_CanvasNode>[];
      final nodesData = canvasData['nodes'] as List<dynamic>? ?? [];
      for (final nodeData in nodesData) {
        final n = nodeData as Map<String, dynamic>;

        // Parse ports
        final inputPorts = <_CanvasPort>[];
        for (final p in (n['inputPorts'] as List<dynamic>? ?? [])) {
          final portData = p as Map<String, dynamic>;
          inputPorts.add(_CanvasPort(
            key: portData['key'] as String,
            label: portData['label'] as String,
            dataType: _parsePortDataTypeFromString(portData['dataType'] as String? ?? 'any'),
            isInput: true,
            required: portData['required'] as bool? ?? false,
          ));
        }

        final outputPorts = <_CanvasPort>[];
        for (final p in (n['outputPorts'] as List<dynamic>? ?? [])) {
          final portData = p as Map<String, dynamic>;
          outputPorts.add(_CanvasPort(
            key: portData['key'] as String,
            label: portData['label'] as String,
            dataType: _parsePortDataTypeFromString(portData['dataType'] as String? ?? 'any'),
            isInput: false,
            required: portData['required'] as bool? ?? false,
          ));
        }

        importedNodes.add(_CanvasNode(
          id: n['id'] as String,
          templateId: n['templateId'] as String? ?? '',
          name: n['name'] as String,
          icon: n['icon'] as String? ?? '',
          color: _parseColor(n['color'] as String? ?? '#666666'),
          category: _parseNodeCategoryFromString(n['category'] as String? ?? 'logic'),
          laneId: n['laneId'] as String?,
          x: (n['x'] as num?)?.toDouble() ?? 0,
          y: (n['y'] as num?)?.toDouble() ?? 0,
          width: (n['width'] as num?)?.toDouble() ?? 180,
          height: (n['height'] as num?)?.toDouble() ?? 80,
          inputPorts: inputPorts,
          outputPorts: outputPorts,
          properties: Map<String, dynamic>.from(n['properties'] ?? {}),
        ));
      }

      // Import wires
      final importedWires = <_CanvasWire>[];
      final wiresData = canvasData['wires'] as List<dynamic>? ?? [];
      for (final wireData in wiresData) {
        final w = wireData as Map<String, dynamic>;
        importedWires.add(_CanvasWire(
          id: w['id'] as String,
          fromNodeId: w['fromNodeId'] as String,
          fromPortKey: w['fromPortKey'] as String,
          toNodeId: w['toNodeId'] as String,
          toPortKey: w['toPortKey'] as String,
          color: _parseColor(w['color'] as String? ?? '#666666'),
        ));
      }

      // Apply imported data
      setState(() {
        _canvasLanes = importedLanes;
        _canvasNodes = importedNodes;
        _canvasWires = importedWires;
        _canvasName = data['name'] as String? ?? 'Imported Pipeline';
        _currentCanvasId = null; // It's a new canvas
        _hasUnsavedChanges = true;
        _clearSelection();
        _history.clear();

        // Restore view settings if present
        final settings = data['settings'] as Map<String, dynamic>?;
        if (settings != null) {
          _zoom = (settings['zoom'] as num?)?.toDouble() ?? 1.0;
          final offset = settings['offset'] as Map<String, dynamic>?;
          if (offset != null) {
            _canvasOffset = Offset(
              (offset['x'] as num?)?.toDouble() ?? 0,
              (offset['y'] as num?)?.toDouble() ?? 0,
            );
          }
        }

        // Update nextId to avoid conflicts
        int maxId = 0;
        for (final node in _canvasNodes) {
          final match = RegExp(r'node_(\d+)').firstMatch(node.id);
          if (match != null) {
            maxId = maxId > int.parse(match.group(1)!) ? maxId : int.parse(match.group(1)!);
          }
        }
        for (final wire in _canvasWires) {
          final match = RegExp(r'wire_(\d+)').firstMatch(wire.id);
          if (match != null) {
            maxId = maxId > int.parse(match.group(1)!) ? maxId : int.parse(match.group(1)!);
          }
        }
        for (final lane in _canvasLanes) {
          final match = RegExp(r'lane_(\d+)').firstMatch(lane.id);
          if (match != null) {
            maxId = maxId > int.parse(match.group(1)!) ? maxId : int.parse(match.group(1)!);
          }
        }
        _nextId = maxId + 1;
      });

      // Validate after import
      _validateCanvas();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported "${data['name']}" with ${importedNodes.length} nodes and ${importedWires.length} wires'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Import error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper methods for parsing enum values from strings (for import)
  LaneType _parseLaneTypeFromString(String typeStr) {
    return LaneType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => LaneType.rules,
    );
  }

  LaneRole _parseLaneRoleFromString(String roleStr) {
    return LaneRole.values.firstWhere(
      (r) => r.name == roleStr,
      orElse: () => LaneRole.executor,
    );
  }

  NodeCategory _parseNodeCategoryFromString(String categoryStr) {
    return NodeCategory.values.firstWhere(
      (c) => c.name == categoryStr,
      orElse: () => NodeCategory.logic,
    );
  }

  PortDataType _parsePortDataTypeFromString(String dataTypeStr) {
    return PortDataType.values.firstWhere(
      (t) => t.name == dataTypeStr,
      orElse: () => PortDataType.any,
    );
  }

  // ============================================================================
  // SNAPSHOTS / VERSION HISTORY
  // ============================================================================

  void _showSaveSnapshotDialog() {
    if (_currentCanvasId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please save the canvas first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final controller = TextEditingController(
      text: 'Snapshot ${DateTime.now().toIso8601String().split('T')[0]}',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.camera_alt_outlined, size: 24),
            SizedBox(width: 8),
            Text('Save Snapshot'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create a named snapshot of the current canvas state. '
              'You can restore this snapshot later.',
              style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Snapshot Name',
                hintText: 'e.g., "Before refactor" or "v1.0"',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              if (controller.text.isEmpty) return;

              Navigator.pop(context);

              try {
                final config = _buildCanvasConfig();
                await _canvasService.saveSnapshot(
                  canvasId: _currentCanvasId!,
                  snapshotName: controller.text,
                  canvas: config,
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Snapshot "${controller.text}" saved'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to save snapshot: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Snapshot'),
          ),
        ],
      ),
    );
  }

  void _showSnapshotsDialog() async {
    if (_currentCanvasId == null) return;

    final snapshots = await _canvasService.getSnapshots(_currentCanvasId!);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history, size: 24),
            SizedBox(width: 8),
            Text('Snapshots'),
          ],
        ),
        content: SizedBox(
          width: 400,
          height: 300,
          child: snapshots.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_off_outlined, size: 48, color: Color(0xFFCCCCCC)),
                      SizedBox(height: 8),
                      Text('No snapshots yet', style: TextStyle(color: Color(0xFF999999))),
                      SizedBox(height: 4),
                      Text('Use "Save Snapshot" to create one', style: TextStyle(fontSize: 12, color: Color(0xFFCCCCCC))),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: snapshots.length,
                  itemBuilder: (context, index) {
                    final snapshot = snapshots[index];
                    final ago = _formatTimeAgo(snapshot.createdAt);

                    return ListTile(
                      leading: const Icon(Icons.camera_alt_outlined),
                      title: Text(snapshot.name),
                      subtitle: Text(ago, style: const TextStyle(fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.restore, color: Color(0xFF2196F3)),
                            tooltip: 'Restore',
                            onPressed: () => _restoreSnapshot(snapshot),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'Delete',
                            onPressed: () => _deleteSnapshot(snapshot),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    if (diff.inHours > 0) return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes} minute${diff.inMinutes > 1 ? 's' : ''} ago';
    return 'Just now';
  }

  void _restoreSnapshot(canvas_svc.CanvasSnapshot snapshot) async {
    Navigator.pop(context); // Close snapshots dialog

    // Confirm restore
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Snapshot?'),
        content: Text(
          'This will replace the current canvas with "${snapshot.name}". '
          'Any unsaved changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3)),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final restoredConfig = await _canvasService.restoreFromSnapshot(
        canvasId: _currentCanvasId!,
        snapshotId: snapshot.id,
      );

      if (restoredConfig == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Snapshot not found'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      // Load the restored canvas
      await _loadCanvasFromConfig(restoredConfig);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restored "${snapshot.name}"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to restore: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _deleteSnapshot(canvas_svc.CanvasSnapshot snapshot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Snapshot?'),
        content: Text('Are you sure you want to delete "${snapshot.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Close the snapshots dialog first
    Navigator.pop(context);

    try {
      await _canvasService.deleteSnapshot(
        canvasId: _currentCanvasId!,
        snapshotId: snapshot.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snapshot deleted'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showUnsavedChangesDialog(VoidCallback onDiscard) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. Do you want to save before continuing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDiscard();
            },
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _saveCanvas();
              onDiscard();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // PIPELINE EXECUTION
  // ============================================================================

  Future<void> _runPipeline({required bool stepMode}) async {
    if (_canvasNodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add some nodes to the canvas first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Parse input JSON
    Map<String, dynamic> input;
    try {
      input = json.decode(_testInputController.text) as Map<String, dynamic>;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid JSON input: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Convert canvas nodes to executable nodes
    final executableNodes = _canvasNodes.map((node) => executor.ExecutableNode(
      id: node.id,
      name: node.name,
      templateId: node.templateId,
      inputNodeIds: _canvasWires
          .where((w) => w.toNodeId == node.id)
          .map((w) => w.fromNodeId)
          .toList(),
      outputNodeIds: _canvasWires
          .where((w) => w.fromNodeId == node.id)
          .map((w) => w.toNodeId)
          .toList(),
    )).toList();

    // Convert canvas wires to executable wires
    final executableWires = _canvasWires.map((wire) => executor.ExecutableWire(
      fromNodeId: wire.fromNodeId,
      fromPortKey: wire.fromPortKey,
      toNodeId: wire.toNodeId,
      toPortKey: wire.toPortKey,
    )).toList();

    // Clear previous state
    setState(() {
      _isExecuting = true;
      _isStepMode = stepMode;
      _executionTrace.clear();
      _executionOutput.clear();
      _nodeExecutionStates.clear();
    });

    // Execute pipeline
    final result = await _executor.execute(
      nodes: executableNodes,
      wires: executableWires,
      input: input,
      stepMode: stepMode,
      onNodeStateChange: (nodeId, state, result) {
        if (mounted) {
          setState(() {
            _nodeExecutionStates[nodeId] = state;
            if (result != null) {
              _executionTrace.add(result);
            }
          });
        }
      },
    );

    // Update final state
    if (mounted) {
      setState(() {
        _isExecuting = false;
        _executionOutput = result.finalOutput;
      });

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pipeline completed in ${result.totalDuration.inMilliseconds}ms'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pipeline error: ${result.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _stopExecution() {
    _executor.stop();
    setState(() {
      _isExecuting = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pipeline stopped'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _stepExecution() {
    _executor.step();
  }

  void _clearExecutionState() {
    _executor.reset();
    setState(() {
      _isExecuting = false;
      _isStepMode = false;
      _executionTrace.clear();
      _executionOutput.clear();
      _nodeExecutionStates.clear();
    });
  }

  // ============================================================================
  // UNDO/REDO & CLIPBOARD
  // ============================================================================

  void _performUndo() {
    final operation = _history.undo();
    if (operation == null) return;

    setState(() {
      _applyOperation(operation, isUndo: true);
      _hasUnsavedChanges = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Undo: ${operation.description}'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF666666),
      ),
    );
  }

  void _performRedo() {
    final operation = _history.redo();
    if (operation == null) return;

    setState(() {
      _applyOperation(operation, isUndo: false);
      _hasUnsavedChanges = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Redo: ${operation.description}'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF666666),
      ),
    );
  }

  void _applyOperation(CanvasOperation operation, {required bool isUndo}) {
    final state = isUndo ? operation.beforeState : operation.afterState;
    final reverseState = isUndo ? operation.afterState : operation.beforeState;

    switch (operation.type) {
      case CanvasOperationType.addNode:
        if (isUndo) {
          // Remove the node
          _canvasNodes.removeWhere((n) => n.id == operation.elementId);
          // Also remove any wires connected to this node
          _canvasWires.removeWhere((w) =>
              w.fromNodeId == operation.elementId || w.toNodeId == operation.elementId);
        } else {
          // Restore the node
          _canvasNodes.add(_nodeFromMap(reverseState));
        }
        break;

      case CanvasOperationType.removeNode:
        if (isUndo) {
          // Restore the node
          _canvasNodes.add(_nodeFromMap(state));
        } else {
          // Remove the node
          _canvasNodes.removeWhere((n) => n.id == operation.elementId);
        }
        break;

      case CanvasOperationType.moveNode:
        final node = _canvasNodes.firstWhere(
          (n) => n.id == operation.elementId,
          orElse: () => _canvasNodes.first,
        );
        if (node.id == operation.elementId) {
          node.x = (state['x'] as num).toDouble();
          node.y = (state['y'] as num).toDouble();
        }
        break;

      case CanvasOperationType.addWire:
        if (isUndo) {
          _canvasWires.removeWhere((w) => w.id == operation.elementId);
        } else {
          _canvasWires.add(_wireFromMap(reverseState));
        }
        break;

      case CanvasOperationType.removeWire:
        if (isUndo) {
          _canvasWires.add(_wireFromMap(state));
        } else {
          _canvasWires.removeWhere((w) => w.id == operation.elementId);
        }
        break;

      case CanvasOperationType.addLane:
        if (isUndo) {
          _canvasLanes.removeWhere((l) => l.id == operation.elementId);
        } else {
          _canvasLanes.add(_laneFromMap(reverseState));
        }
        break;

      case CanvasOperationType.removeLane:
        if (isUndo) {
          _canvasLanes.add(_laneFromMap(state));
        } else {
          _canvasLanes.removeWhere((l) => l.id == operation.elementId);
        }
        break;

      case CanvasOperationType.updateNodeProperties:
      case CanvasOperationType.moveLane:
      case CanvasOperationType.updateLaneProperties:
      case CanvasOperationType.multipleOperations:
        // These operation types are reserved for future use.
        // Main undo/redo operations (add/remove/move) are fully implemented.
        break;
    }
  }

  _CanvasNode _nodeFromMap(Map<String, dynamic> map) {
    return _CanvasNode(
      id: map['id'] as String,
      templateId: map['templateId'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String,
      color: Color(map['color'] as int),
      category: NodeCategory.values.firstWhere(
        (c) => c.name == map['category'],
        orElse: () => NodeCategory.logic,
      ),
      laneId: map['laneId'] as String?,
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      width: (map['width'] as num?)?.toDouble() ?? 180,
      height: (map['height'] as num?)?.toDouble() ?? 80,
      inputPorts: (map['inputPorts'] as List<dynamic>? ?? [])
          .map((p) => _CanvasPort(
                key: p['key'] as String,
                label: p['label'] as String,
                dataType: PortDataType.values.firstWhere(
                  (d) => d.name == p['dataType'],
                  orElse: () => PortDataType.any,
                ),
                isInput: true,
                required: p['required'] as bool? ?? false,
              ))
          .toList(),
      outputPorts: (map['outputPorts'] as List<dynamic>? ?? [])
          .map((p) => _CanvasPort(
                key: p['key'] as String,
                label: p['label'] as String,
                dataType: PortDataType.values.firstWhere(
                  (d) => d.name == p['dataType'],
                  orElse: () => PortDataType.any,
                ),
                isInput: false,
                required: p['required'] as bool? ?? false,
              ))
          .toList(),
      properties: Map<String, dynamic>.from(map['properties'] ?? {}),
    );
  }

  Map<String, dynamic> _nodeToMap(_CanvasNode node) {
    return {
      'id': node.id,
      'templateId': node.templateId,
      'name': node.name,
      'icon': node.icon,
      'color': node.color.toARGB32(),
      'category': node.category.name,
      'laneId': node.laneId,
      'x': node.x,
      'y': node.y,
      'width': node.width,
      'height': node.height,
      'inputPorts': node.inputPorts
          .map((p) => {
                'key': p.key,
                'label': p.label,
                'dataType': p.dataType.name,
                'required': p.required,
              })
          .toList(),
      'outputPorts': node.outputPorts
          .map((p) => {
                'key': p.key,
                'label': p.label,
                'dataType': p.dataType.name,
                'required': p.required,
              })
          .toList(),
      'properties': node.properties,
    };
  }

  _CanvasWire _wireFromMap(Map<String, dynamic> map) {
    return _CanvasWire(
      id: map['id'] as String,
      fromNodeId: map['fromNodeId'] as String,
      fromPortKey: map['fromPortKey'] as String,
      toNodeId: map['toNodeId'] as String,
      toPortKey: map['toPortKey'] as String,
      color: map['color'] != null ? Color(map['color'] as int) : const Color(0xFF666666),
    );
  }

  Map<String, dynamic> _wireToMap(_CanvasWire wire) {
    return {
      'id': wire.id,
      'fromNodeId': wire.fromNodeId,
      'fromPortKey': wire.fromPortKey,
      'toNodeId': wire.toNodeId,
      'toPortKey': wire.toPortKey,
      'color': wire.color.toARGB32(),
    };
  }

  _CanvasLane _laneFromMap(Map<String, dynamic> map) {
    return _CanvasLane(
      id: map['id'] as String,
      templateId: map['templateId'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String,
      color: Color(map['color'] as int),
      type: LaneType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => LaneType.rules,
      ),
      role: LaneRole.values.firstWhere(
        (r) => r.name == map['role'],
        orElse: () => LaneRole.executor,
      ),
      y: (map['y'] as num?)?.toDouble() ?? 0,
      height: (map['height'] as num?)?.toDouble() ?? 120,
      isCollapsed: map['isCollapsed'] as bool? ?? false,
      nodeIds: List<String>.from(map['nodeIds'] ?? []),
    );
  }

  Map<String, dynamic> _laneToMap(_CanvasLane lane) {
    return {
      'id': lane.id,
      'templateId': lane.templateId,
      'name': lane.name,
      'icon': lane.icon,
      'color': lane.color.toARGB32(),
      'type': lane.type.name,
      'role': lane.role.name,
      'y': lane.y,
      'height': lane.height,
      'isCollapsed': lane.isCollapsed,
      'nodeIds': lane.nodeIds,
    };
  }

  void _copySelection() {
    if (_selectedNodeIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select one or more nodes to copy'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    // Get all selected nodes
    final selectedNodes = _canvasNodes
        .where((n) => _selectedNodeIds.contains(n.id))
        .toList();

    if (selectedNodes.isEmpty) return;

    // Get wires that connect selected nodes to each other
    final selectedWires = _canvasWires
        .where((w) =>
            _selectedNodeIds.contains(w.fromNodeId) &&
            _selectedNodeIds.contains(w.toNodeId))
        .toList();

    // Find the origin (top-left of selection bounds)
    double minX = double.infinity;
    double minY = double.infinity;
    for (final node in selectedNodes) {
      if (node.x < minX) minX = node.x;
      if (node.y < minY) minY = node.y;
    }

    // Copy the selected nodes and their connecting wires
    _clipboard.copy(
      nodes: selectedNodes.map((n) => _nodeToMap(n)).toList(),
      wires: selectedWires.map((w) => _wireToMap(w)).toList(),
      origin: Offset(minX, minY),
    );

    final nodeCount = selectedNodes.length;
    final wireCount = selectedWires.length;
    final message = wireCount > 0
        ? '$nodeCount node${nodeCount > 1 ? 's' : ''} and $wireCount wire${wireCount > 1 ? 's' : ''} copied'
        : '$nodeCount node${nodeCount > 1 ? 's' : ''} copied';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF666666),
      ),
    );
  }

  void _pasteFromClipboard() {
    if (!_clipboard.hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to paste'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    // Paste at an offset from the original position
    final result = _clipboard.paste(
      targetPosition: const Offset(50, 50),
      generateId: () => 'node_${_nextId++}',
    );

    if (result == null) return;

    setState(() {
      for (final nodeMap in result.nodes) {
        final node = _nodeFromMap(nodeMap);
        _canvasNodes.add(node);
        _history.recordAddNode(_nodeToMap(node));
      }
      for (final wireMap in result.wires) {
        final wire = _wireFromMap(wireMap);
        _canvasWires.add(wire);
        _history.recordAddWire(_wireToMap(wire));
      }
      _hasUnsavedChanges = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pasted ${result.nodes.length} node(s)'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF666666),
      ),
    );
  }

  void _deleteSelection() {
    if (_totalSelectedCount == 0) return;

    setState(() {
      // Delete all selected nodes and their connected wires
      for (final nodeId in _selectedNodeIds.toList()) {
        final nodeIndex = _canvasNodes.indexWhere((n) => n.id == nodeId);
        if (nodeIndex != -1) {
          final node = _canvasNodes[nodeIndex];
          _history.recordRemoveNode(_nodeToMap(node));
          _canvasNodes.removeAt(nodeIndex);
          // Remove connected wires
          final connectedWires = _canvasWires
              .where((w) => w.fromNodeId == node.id || w.toNodeId == node.id)
              .toList();
          for (final wire in connectedWires) {
            _history.recordRemoveWire(_wireToMap(wire));
            _canvasWires.remove(wire);
          }
        }
      }

      // Delete all selected wires
      for (final wireId in _selectedWireIds.toList()) {
        final wireIndex = _canvasWires.indexWhere((w) => w.id == wireId);
        if (wireIndex != -1) {
          final wire = _canvasWires[wireIndex];
          _history.recordRemoveWire(_wireToMap(wire));
          _canvasWires.removeAt(wireIndex);
        }
      }

      // Delete selected lane (only one at a time)
      if (_selectedLaneId != null) {
        final laneIndex = _canvasLanes.indexWhere((l) => l.id == _selectedLaneId);
        if (laneIndex != -1) {
          final lane = _canvasLanes[laneIndex];
          _history.recordRemoveLane(_laneToMap(lane));
          _canvasLanes.removeAt(laneIndex);
        }
      }

      // Clear selection
      _selectedNodeIds.clear();
      _selectedWireIds.clear();
      _selectedLaneId = null;
      _hasUnsavedChanges = true;
    });
  }

  // Keyboard shortcut handler
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Track Space key for panning
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent && !_isSpacePressed) {
        setState(() => _isSpacePressed = true);
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        setState(() {
          _isSpacePressed = false;
          _isPanning = false;
        });
        return KeyEventResult.handled;
      }
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Ctrl+Z - Undo
    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _performRedo();
      } else {
        _performUndo();
      }
      return KeyEventResult.handled;
    }

    // Ctrl+Y - Redo
    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyY) {
      _performRedo();
      return KeyEventResult.handled;
    }

    // Ctrl+C - Copy
    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyC) {
      _copySelection();
      return KeyEventResult.handled;
    }

    // Ctrl+V - Paste
    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyV) {
      _pasteFromClipboard();
      return KeyEventResult.handled;
    }

    // Ctrl+S - Save
    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyS) {
      if (_hasUnsavedChanges && !_isSaving) {
        _saveCanvas();
      }
      return KeyEventResult.handled;
    }

    // Delete/Backspace - Delete selection
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteSelection();
      return KeyEventResult.handled;
    }

    // Escape - Clear selection
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clearSelection();
      if (_isDrawingWire) {
        setState(() {
          _isDrawingWire = false;
          _wireStartNodeId = null;
          _wireStartPortKey = null;
        });
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ============================================================================
  // ZOOM & PAN
  // ============================================================================

  /// Zoom to fit all content in the canvas
  void _zoomToFit() {
    if (_canvasLanes.isEmpty && _canvasNodes.isEmpty) return;

    // Get the canvas size from the key
    final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final canvasSize = renderBox.size;

    // Calculate bounds of all content
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = 0;
    double maxY = 0;

    for (final lane in _canvasLanes) {
      minY = lane.y < minY ? lane.y : minY;
      maxY = (lane.y + lane.height) > maxY ? (lane.y + lane.height) : maxY;
    }

    for (final node in _canvasNodes) {
      minX = node.x < minX ? node.x : minX;
      minY = node.y < minY ? node.y : minY;
      maxX = (node.x + node.width) > maxX ? (node.x + node.width) : maxX;
      maxY = (node.y + node.height) > maxY ? (node.y + node.height) : maxY;
    }

    // If no content, reset
    if (minX == double.infinity) {
      setState(() {
        _zoom = 1.0;
        _canvasOffset = Offset.zero;
      });
      return;
    }

    // Add padding
    const padding = 40.0;
    minX -= padding;
    minY -= padding;
    maxX += padding;
    maxY += padding;

    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;

    // Calculate zoom to fit
    final zoomX = canvasSize.width / contentWidth;
    final zoomY = canvasSize.height / contentHeight;
    final newZoom = (zoomX < zoomY ? zoomX : zoomY).clamp(0.25, 3.0);

    // Calculate offset to center content
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    final offsetX = (canvasSize.width / 2) - (centerX * newZoom);
    final offsetY = (canvasSize.height / 2) - (centerY * newZoom);

    setState(() {
      _zoom = newZoom;
      _canvasOffset = Offset(offsetX, offsetY);
    });
  }

  // ============================================================================
  // VALIDATION & AUTO-LAYOUT
  // ============================================================================

  void _validateCanvas() {
    // Convert canvas nodes to validation nodes
    final validationNodes = _canvasNodes.map((node) => ValidationNode(
      id: node.id,
      name: node.name,
      templateId: node.templateId,
      inputPorts: node.inputPorts.map((p) => ValidationPort(
        key: p.key,
        label: p.label,
        required: p.required,
      )).toList(),
      outputPorts: node.outputPorts.map((p) => ValidationPort(
        key: p.key,
        label: p.label,
        required: p.required,
      )).toList(),
    )).toList();

    // Convert canvas wires to validation wires
    final validationWires = _canvasWires.map((wire) => ValidationWire(
      id: wire.id,
      fromNodeId: wire.fromNodeId,
      fromPortKey: wire.fromPortKey,
      toNodeId: wire.toNodeId,
      toPortKey: wire.toPortKey,
    )).toList();

    // Run validation
    final result = _validator.validate(
      nodes: validationNodes,
      wires: validationWires,
    );

    setState(() {
      _validationResult = result;
      if (result.issues.isNotEmpty) {
        _showValidationPanel = true;
      }
    });

    // Show summary snackbar
    if (result.isValid && result.issues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pipeline is valid'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else if (result.errorCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Found ${result.errorCount} error(s) and ${result.warningCount} warning(s)'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () => setState(() => _showValidationPanel = true),
          ),
        ),
      );
    } else if (result.warningCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Found ${result.warningCount} warning(s)'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _performAutoLayout() {
    if (_canvasNodes.isEmpty) return;

    // Convert to validation format for the algorithm
    final validationNodes = _canvasNodes.map((node) => ValidationNode(
      id: node.id,
      name: node.name,
      templateId: node.templateId,
      inputPorts: [],
      outputPorts: [],
    )).toList();

    final validationWires = _canvasWires.map((wire) => ValidationWire(
      id: wire.id,
      fromNodeId: wire.fromNodeId,
      fromPortKey: wire.fromPortKey,
      toNodeId: wire.toNodeId,
      toPortKey: wire.toPortKey,
    )).toList();

    // Calculate new positions
    final layout = CanvasAutoLayout();
    final positions = layout.calculateLayout(
      nodes: validationNodes,
      wires: validationWires,
    );

    // Apply new positions with history recording
    setState(() {
      for (final node in _canvasNodes) {
        final newPos = positions[node.id];
        if (newPos != null) {
          final oldX = node.x;
          final oldY = node.y;
          node.x = newPos.x;
          node.y = newPos.y;
          // Record for undo (batch this later for better UX)
          if (oldX != newPos.x || oldY != newPos.y) {
            _history.recordMoveNode(node.id, oldX, oldY, newPos.x, newPos.y);
          }
        }
      }
      _hasUnsavedChanges = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Auto-layout applied'),
        backgroundColor: Color(0xFF666666),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// Get validation severity for a node (for visual indicators)
  ValidationSeverity? _getNodeValidationSeverity(String nodeId) {
    return _validationResult?.getHighestSeverityForElement(nodeId);
  }

  /// Get validation issues for a node
  List<ValidationIssue> _getNodeValidationIssues(String nodeId) {
    return _validationResult?.getIssuesForElement(nodeId) ?? [];
  }
}

// ============================================================================
// HELPER CLASSES
// ============================================================================

/// Canvas lane representation
class _CanvasLane {
  final String id;
  final String templateId;
  final String name;
  final String icon;
  final Color color;
  final LaneType type;
  final LaneRole role;
  double y;
  double height;
  bool isCollapsed;
  final List<String> nodeIds; // Nodes in this lane

  _CanvasLane({
    required this.id,
    required this.templateId,
    required this.name,
    required this.icon,
    required this.color,
    required this.type,
    required this.role,
    this.y = 0,
    this.height = 120,
    this.isCollapsed = false,
    List<String>? nodeIds,
  }) : nodeIds = nodeIds ?? [];

  _CanvasLane copyWith({
    String? name,
    double? y,
    double? height,
    bool? isCollapsed,
    List<String>? nodeIds,
  }) {
    return _CanvasLane(
      id: id,
      templateId: templateId,
      name: name ?? this.name,
      icon: icon,
      color: color,
      type: type,
      role: role,
      y: y ?? this.y,
      height: height ?? this.height,
      isCollapsed: isCollapsed ?? this.isCollapsed,
      nodeIds: nodeIds ?? List.from(this.nodeIds),
    );
  }
}

/// Canvas node representation
class _CanvasNode {
  final String id;
  final String templateId;
  final String name;
  final String icon;
  final Color color;
  final NodeCategory category;
  String? laneId; // Which lane this node belongs to
  double x;
  double y;
  double width;
  double height;
  final List<_CanvasPort> inputPorts;
  final List<_CanvasPort> outputPorts;
  Map<String, dynamic> properties;

  _CanvasNode({
    required this.id,
    required this.templateId,
    required this.name,
    required this.icon,
    required this.color,
    required this.category,
    this.laneId,
    this.x = 0,
    this.y = 0,
    this.width = 180,
    this.height = 80,
    required this.inputPorts,
    required this.outputPorts,
    Map<String, dynamic>? properties,
  }) : properties = properties ?? {};

  _CanvasNode copyWith({
    String? laneId,
    double? x,
    double? y,
    Map<String, dynamic>? properties,
  }) {
    return _CanvasNode(
      id: id,
      templateId: templateId,
      name: name,
      icon: icon,
      color: color,
      category: category,
      laneId: laneId ?? this.laneId,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width,
      height: height,
      inputPorts: inputPorts,
      outputPorts: outputPorts,
      properties: properties ?? Map.from(this.properties),
    );
  }
}

/// Canvas port representation
class _CanvasPort {
  final String key;
  final String label;
  final PortDataType dataType;
  final bool isInput;
  final bool required;

  const _CanvasPort({
    required this.key,
    required this.label,
    required this.dataType,
    required this.isInput,
    this.required = false,
  });
}

/// Canvas wire representation
class _CanvasWire {
  final String id;
  final String fromNodeId;
  final String fromPortKey;
  final String toNodeId;
  final String toPortKey;
  final Color color;

  const _CanvasWire({
    required this.id,
    required this.fromNodeId,
    required this.fromPortKey,
    required this.toNodeId,
    required this.toPortKey,
    this.color = const Color(0xFF666666),
  });
}

/// Grid painter for canvas background
class _GridPainter extends CustomPainter {
  final double zoom;
  final double gridSize;
  final Offset offset;

  _GridPainter({this.zoom = 1.0, this.gridSize = 20, this.offset = Offset.zero});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8E8E8)
      ..strokeWidth = 1;

    final scaledGridSize = gridSize * zoom;

    // Calculate starting positions based on offset
    final startX = offset.dx % scaledGridSize;
    final startY = offset.dy % scaledGridSize;

    // Draw vertical lines
    for (double x = startX; x < size.width; x += scaledGridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines
    for (double y = startY; y < size.height; y += scaledGridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.zoom != zoom ||
        oldDelegate.gridSize != gridSize ||
        oldDelegate.offset != offset;
  }
}

/// Selection rectangle painter for marquee selection
class _SelectionRectPainter extends CustomPainter {
  final Offset startPos;
  final Offset endPos;

  _SelectionRectPainter({required this.startPos, required this.endPos});

  @override
  void paint(Canvas canvas, Size size) {
    final left = startPos.dx < endPos.dx ? startPos.dx : endPos.dx;
    final top = startPos.dy < endPos.dy ? startPos.dy : endPos.dy;
    final width = (startPos.dx - endPos.dx).abs();
    final height = (startPos.dy - endPos.dy).abs();

    final rect = Rect.fromLTWH(left, top, width, height);

    // Draw fill
    final fillPaint = Paint()
      ..color = const Color(0x202196F3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = const Color(0xFF2196F3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SelectionRectPainter oldDelegate) {
    return oldDelegate.startPos != startPos || oldDelegate.endPos != endPos;
  }
}

/// Minimap painter showing overview of canvas elements
class _MinimapPainter extends CustomPainter {
  final List<_CanvasLane> lanes;
  final List<_CanvasNode> nodes;
  final double zoom;
  final Offset offset;
  final Size canvasSize;

  _MinimapPainter({
    required this.lanes,
    required this.nodes,
    this.zoom = 1.0,
    this.offset = Offset.zero,
    this.canvasSize = const Size(800, 600),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (lanes.isEmpty && nodes.isEmpty) return;

    // Calculate scale to fit all elements
    double maxX = 500;
    double maxY = 300;
    for (final lane in lanes) {
      maxY = (lane.y + lane.height).clamp(maxY, double.infinity);
    }
    for (final node in nodes) {
      maxX = (node.x + node.width).clamp(maxX, double.infinity);
      maxY = (node.y + node.height).clamp(maxY, double.infinity);
    }

    final scaleX = size.width / maxX;
    final scaleY = size.height / maxY;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    // Draw lanes
    for (final lane in lanes) {
      final paint = Paint()
        ..color = lane.color.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(0, lane.y * scale, size.width, lane.height * scale),
        paint,
      );
    }

    // Draw nodes
    for (final node in nodes) {
      final paint = Paint()
        ..color = node.color
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(
          node.x * scale,
          node.y * scale,
          node.width * scale,
          node.height * scale,
        ),
        paint,
      );
    }

    // Draw viewport rectangle
    final viewportPaint = Paint()
      ..color = const Color(0xFF2196F3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Calculate viewport in canvas coordinates
    final viewX = -offset.dx / zoom;
    final viewY = -offset.dy / zoom;
    final viewWidth = canvasSize.width / zoom;
    final viewHeight = canvasSize.height / zoom;

    // Convert to minimap coordinates
    final viewportRect = Rect.fromLTWH(
      viewX * scale,
      viewY * scale,
      viewWidth * scale,
      viewHeight * scale,
    );

    canvas.drawRect(viewportRect, viewportPaint);

    // Draw semi-transparent fill for viewport
    final viewportFillPaint = Paint()
      ..color = const Color(0x102196F3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(viewportRect, viewportFillPaint);
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.lanes.length != lanes.length ||
        oldDelegate.nodes.length != nodes.length ||
        oldDelegate.zoom != zoom ||
        oldDelegate.offset != offset ||
        oldDelegate.canvasSize != canvasSize;
  }
}

/// Wire painter for rendering bezier curves between nodes
class _WirePainter extends CustomPainter {
  final Offset startPosition;
  final Offset endPosition;
  final bool isSelected;
  final Color color;
  final bool isExecuting;
  final bool showFlow;

  _WirePainter({
    required this.startPosition,
    required this.endPosition,
    this.isSelected = false,
    this.color = const Color(0xFF666666),
    this.isExecuting = false,
    this.showFlow = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Determine wire color based on state
    Color wireColor = color;
    if (isSelected) {
      wireColor = const Color(0xFF2196F3);
    } else if (isExecuting) {
      wireColor = const Color(0xFF4CAF50);
    }

    final paint = Paint()
      ..color = wireColor
      ..strokeWidth = isSelected ? 3 : 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Smart control point calculation
    final dx = endPosition.dx - startPosition.dx;
    final dy = endPosition.dy - startPosition.dy;
    final distance = (dx.abs() + dy.abs()) / 2;

    // Adjust control points based on direction
    double cp1x, cp1y, cp2x, cp2y;

    if (dx >= 0) {
      // Normal left-to-right flow
      final controlOffset = (distance * 0.4).clamp(30.0, 150.0);
      cp1x = startPosition.dx + controlOffset;
      cp1y = startPosition.dy;
      cp2x = endPosition.dx - controlOffset;
      cp2y = endPosition.dy;
    } else {
      // Backwards connection - create a loop
      final loopHeight = (dy.abs() * 0.5).clamp(40.0, 100.0);
      final controlOffset = (distance * 0.3).clamp(30.0, 80.0);
      cp1x = startPosition.dx + controlOffset;
      cp1y = startPosition.dy + (dy > 0 ? loopHeight : -loopHeight);
      cp2x = endPosition.dx - controlOffset;
      cp2y = endPosition.dy + (dy > 0 ? loopHeight : -loopHeight);
    }

    final path = Path()
      ..moveTo(startPosition.dx, startPosition.dy)
      ..cubicTo(cp1x, cp1y, cp2x, cp2y, endPosition.dx, endPosition.dy);

    // Draw glow for selected or executing wire
    if (isSelected || isExecuting) {
      final glowPaint = Paint()
        ..color = wireColor.withValues(alpha: 0.3)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawPath(path, glowPaint);
    }

    // Draw main wire
    canvas.drawPath(path, paint);

    // Draw flow dots for executing wires
    if (isExecuting || showFlow) {
      _drawFlowIndicators(canvas, path, wireColor);
    }

    // Draw arrow at end
    _drawArrow(canvas, endPosition, cp2x, cp2y, wireColor);
  }

  void _drawFlowIndicators(Canvas canvas, Path path, Color dotColor) {
    final metrics = path.computeMetrics().first;
    final length = metrics.length;

    // Draw 3 dots along the path
    for (int i = 0; i < 3; i++) {
      final t = (i + 1) / 4.0;
      final tangent = metrics.getTangentForOffset(length * t);
      if (tangent != null) {
        final dotPaint = Paint()
          ..color = dotColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(tangent.position, 3, dotPaint);
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset position, double fromX, double fromY, Color arrowColor) {
    // Calculate arrow direction based on curve end tangent
    final angle = (position.dy - fromY).abs() < 0.1
        ? 0.0
        : (fromY - position.dy).sign * 0.2;

    final paint = Paint()
      ..color = arrowColor
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(position.dx, position.dy)
      ..lineTo(position.dx - 10, position.dy - 5 + angle * 10)
      ..lineTo(position.dx - 6, position.dy)
      ..lineTo(position.dx - 10, position.dy + 5 + angle * 10)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WirePainter oldDelegate) {
    return oldDelegate.startPosition != startPosition ||
        oldDelegate.endPosition != endPosition ||
        oldDelegate.isSelected != isSelected ||
        oldDelegate.isExecuting != isExecuting;
  }

  @override
  bool hitTest(Offset position) {
    // Check if position is near the bezier curve
    const hitTolerance = 10.0;

    // Simple bounding box check first
    final minX = startPosition.dx < endPosition.dx ? startPosition.dx : endPosition.dx;
    final maxX = startPosition.dx > endPosition.dx ? startPosition.dx : endPosition.dx;
    final minY = startPosition.dy < endPosition.dy ? startPosition.dy : endPosition.dy;
    final maxY = startPosition.dy > endPosition.dy ? startPosition.dy : endPosition.dy;

    if (position.dx < minX - hitTolerance ||
        position.dx > maxX + hitTolerance ||
        position.dy < minY - hitTolerance ||
        position.dy > maxY + hitTolerance) {
      return false;
    }

    // Check distance to curve (simplified)
    final dx = (endPosition.dx - startPosition.dx).abs();
    final controlOffset = dx * 0.5;

    // Sample points along the curve
    for (double t = 0; t <= 1; t += 0.05) {
      final curvePoint = _bezierPoint(t, startPosition, endPosition, controlOffset);
      final distance = (position - curvePoint).distance;
      if (distance < hitTolerance) {
        return true;
      }
    }

    return false;
  }

  Offset _bezierPoint(double t, Offset start, Offset end, double controlOffset) {
    final t1 = 1 - t;
    final p0 = start;
    final p1 = Offset(start.dx + controlOffset, start.dy);
    final p2 = Offset(end.dx - controlOffset, end.dy);
    final p3 = end;

    return Offset(
      t1 * t1 * t1 * p0.dx + 3 * t1 * t1 * t * p1.dx + 3 * t1 * t * t * p2.dx + t * t * t * p3.dx,
      t1 * t1 * t1 * p0.dy + 3 * t1 * t1 * t * p1.dy + 3 * t1 * t * t * p2.dy + t * t * t * p3.dy,
    );
  }
}

/// Wire preview painter while drawing a new connection
class _WirePreviewPainter extends CustomPainter {
  final Offset startPosition;
  final Offset endPosition;
  final bool isOutput;

  _WirePreviewPainter({
    required this.startPosition,
    required this.endPosition,
    this.isOutput = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isOutput ? Colors.orange : Colors.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Dashed line effect
    final dashPaint = Paint()
      ..color = (isOutput ? Colors.orange : Colors.green).withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Calculate control points for bezier curve
    final dx = (endPosition.dx - startPosition.dx).abs();
    final controlOffset = dx * 0.5;

    final path = Path()
      ..moveTo(startPosition.dx, startPosition.dy)
      ..cubicTo(
        startPosition.dx + controlOffset,
        startPosition.dy,
        endPosition.dx - controlOffset,
        endPosition.dy,
        endPosition.dx,
        endPosition.dy,
      );

    // Draw glow effect
    final glowPaint = Paint()
      ..color = (isOutput ? Colors.orange : Colors.green).withValues(alpha: 0.2)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, glowPaint);

    canvas.drawPath(path, paint);

    // Draw endpoint circle
    final circlePaint = Paint()
      ..color = isOutput ? Colors.green : Colors.orange
      ..style = PaintingStyle.fill;

    canvas.drawCircle(endPosition, 6, circlePaint);

    final circleBorderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(endPosition, 6, circleBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _WirePreviewPainter oldDelegate) {
    return oldDelegate.startPosition != startPosition ||
        oldDelegate.endPosition != endPosition;
  }
}
