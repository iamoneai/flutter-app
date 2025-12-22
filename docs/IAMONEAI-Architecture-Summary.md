# IAMONEAI Architecture Summary
## User Chat Frontend & Backend Integration

**Generated:** 2025-12-21
**Purpose:** Comprehensive summary for wiring frontend-backend Generative UI Actions Protocol

---

## PART 1: FRONTEND (Flutter)

### 1.1 ChatService (`lib/user/services/chat_service.dart`)

**Class:** `ChatService`

**API Base URLs (HTTP onRequest endpoints):**
| Endpoint | URL |
|----------|-----|
| Pipeline Chat | `https://pipelinechat-qqkntitb3a-uc.a.run.app` |
| Save Memory Card | `https://savememorycard-qqkntitb3a-uc.a.run.app` |
| Save Selected Memories | `https://saveselectedmemories-qqkntitb3a-uc.a.run.app` |
| Resolve Conflict | `https://resolveconflict-qqkntitb3a-uc.a.run.app` |
| Save Relationships | `https://saverelationships-qqkntitb3a-uc.a.run.app` |
| Get Memory Details | `https://getmemorydetails-qqkntitb3a-uc.a.run.app` |
| Log Action Interaction | `https://logactioninteraction-qqkntitb3a-uc.a.run.app` |

**Public Methods:**

| Method | Description | Request Body | Response |
|--------|-------------|--------------|----------|
| `sendMessage(String message)` | Main chat endpoint | `{ message, iin }` | `ChatResponse` |
| `saveMemoryCard(MemoryCard card)` | Save completed memory card | `{ iin, card }` | `SaveCardResult` |
| `saveSelectedMemories({actionId, items})` | Save from Selection Grid | `{ iin, actionId, selectedIds, memories }` | `SaveSelectedResult` |
| `resolveConflict({actionId, memoryId, field, choice, newValue})` | Resolve data conflict | `{ iin, actionId, oldMemoryId, field, choice, newValue }` | `ResolveConflictResult` |
| `saveRelationships({actionId, connections})` | Save relationship graph | `{ iin, actionId, connections }` | `SaveRelationshipsResult` |
| `getMemoryDetails(String memoryId)` | Get timeline event details | `{ iin, memoryId }` | `MemoryDetails?` |
| `logActionInteraction({actionId, actionType, interaction, metadata})` | Analytics logging | `{ iin, actionId, actionType, interaction, metadata }` | void |

**Response Classes:**
- `ChatResponse` - Main pipeline response with `actions: List<AppAction>?`
- `SaveCardResult` - `{ success, memoryId?, error? }`
- `SaveSelectedResult` - `{ success, savedCount, savedIds, skippedCount, error? }`
- `ResolveConflictResult` - `{ success, action?, message?, error? }`
- `SaveRelationshipsResult` - `{ success, savedCount, savedIds, error? }`
- `MemoryDetails` - `{ id, type, content, slots, createdAt? }`

---

### 1.2 Chat Widget (`lib/user/widgets/chat_widget.dart`)

**Class:** `ChatWidget extends StatefulWidget`
**State:** `_ChatWidgetState`

**State Variables:**
- `List<ChatMessage> _messages` - Message history
- `bool _isLoading` - Loading indicator
- `ChatMessage? _selectedMessage` - Selected for debug panel
- `String? _expandedCardId` - Memory card being edited

**ChatMessage Model:**
```dart
class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? provider;
  final String? intent;
  final int? latencyMs;
  final int? memoriesUsed;
  final int? memoriesSaved;
  final Map<String, dynamic>? rawJson;
  List<AppAction>? actions;  // Actions Protocol

  // Convenience getters:
  List<RenderMemoryCardAction> get memoryCardActions;
  List<RenderSelectionGridAction> get selectionGridActions;
  List<RenderConflictResolverAction> get conflictActions;
  List<RenderTimelineAction> get timelineActions;
  List<RenderQuickRepliesAction> get quickRepliesActions;
  List<RenderRelationshipGraphAction> get relationshipGraphActions;
  bool get hasUIActions;
}
```

**Action Handler Methods:**
| Method | Purpose | Calls |
|--------|---------|-------|
| `_handleSaveCard(message, action, card)` | Save memory card | `chatService.saveMemoryCard()` |
| `_handleDeleteCard(message, action)` | Dismiss memory card | `chatService.logActionInteraction()` |
| `_handleSelectionSubmit(message, action, selected)` | Save selected memories | `chatService.saveSelectedMemories()` |
| `_handleConflictResolution(message, action, keepOld)` | Resolve conflict | `chatService.resolveConflict()` |
| `_handleRelationshipConfirm(message, action)` | Save relationships | `chatService.saveRelationships()` |
| `_handleQuickReply(reply)` | Send quick reply message | `_sendMessage()` |
| `_showEventDetails(event)` | Show timeline event dialog | Dialog UI |
| `_showToast(toast)` | Show toast notification | `ScaffoldMessenger.showSnackBar()` |

---

### 1.3 Action Models (`lib/user/models/action.dart`)

**Base Class:**
```dart
abstract class AppAction {
  final String tool;      // Action type identifier
  final String id;        // Unique action ID
  final Map<String, dynamic> params;
  final ActionMeta? meta;

  factory AppAction.fromJson(Map<String, dynamic> json);  // Switch on 'tool' field
}
```

**Action Types:**

| Class | Tool String | Params |
|-------|-------------|--------|
| `RenderMemoryCardAction` | `RENDER_MEMORY_CARD` | tempId, type, status, icon, title, subtitle, color, complete, missingRequired, typeConfig, slots |
| `RenderSelectionGridAction` | `RENDER_SELECTION_GRID` | title, subtitle?, items: SelectionItem[], submitLabel |
| `RenderConflictResolverAction` | `RENDER_CONFLICT_RESOLVER` | title, field, fieldLabel, icon, oldValue, newValue, oldMemoryId |
| `RenderTimelineAction` | `RENDER_TIMELINE` | title, events: TimelineEvent[] |
| `RenderRelationshipGraphAction` | `RENDER_RELATIONSHIP_GRAPH` | title, rootPerson, connections: RelationshipConnection[] |
| `RenderQuickRepliesAction` | `RENDER_QUICK_REPLIES` | replies: QuickReply[] |
| `ShowToastAction` | `SHOW_TOAST` | message, type, duration |
| `GenericAction` | (fallback) | Any params |

**Helper Classes:**
- `SelectionItem` - `{ id, icon, label, sublabel?, type, selected, memory }`
- `QuickReply` - `{ id, label, message, icon? }`
- `TimelineEvent` - `{ id, memoryId, icon, title, subtitle?, datetime, type }`
- `RelationshipConnection` - `{ id, to, relationship, metadata? }`
- `ActionMeta` - `{ priority?, dismissable?, timeout?, requiresResponse? }`

---

### 1.4 Action Widgets (`lib/user/widgets/action_widgets/`)

**Barrel Export:** `action_widgets.dart`

| Widget | File | Props |
|--------|------|-------|
| `MemoryBadge` | `memory_card_widget.dart` | `card: MemoryCard, onEdit, onDelete` |
| `MemoryCardExpanded` | `memory_card_expanded.dart` | `card: MemoryCard, onSave(MemoryCard), onCancel, onDelete` |
| `SelectionGridWidget` | `selection_grid_widget.dart` | `action: RenderSelectionGridAction, onSubmit(List<SelectionItem>), onCancel` |
| `ConflictResolverWidget` | `conflict_resolver_widget.dart` | `action: RenderConflictResolverAction, onKeepOld, onUpdate` |
| `TimelineWidget` | `timeline_widget.dart` | `action: RenderTimelineAction, onEventTap(TimelineEvent)` |
| `RelationshipGraphWidget` | `relationship_graph_widget.dart` | `action: RenderRelationshipGraphAction, onConfirm, onEdit` |
| `QuickRepliesWidget` | `quick_replies_widget.dart` | `action: RenderQuickRepliesAction, onReplyTap(QuickReply)` |

---

## PART 2: BACKEND (TypeScript Cloud Functions)

### 2.1 Index/Exports (`functions/chat/src/index.ts`)

**All Endpoints:**

| Export Name | Type | Purpose |
|-------------|------|---------|
| `health` | onRequest | Health check endpoint |
| `chat` | onRequest | Legacy direct LLM chat |
| `pipelineChat` | onRequest | Main 12-stage pipeline (from orchestrator) |
| `pipelineChatDebug` | onRequest | Pipeline with debug mode |
| `saveMemoryCard` | onRequest | Save memory card from Generative UI |
| `saveSelectedMemories` | onRequest | Save from Selection Grid |
| `resolveConflict` | onRequest | Resolve memory conflict |
| `saveRelationships` | onRequest | Save from Relationship Graph |
| `getMemoryDetails` | onRequest | Get timeline event memory |
| `logActionInteraction` | onRequest | Log analytics |
| `getGenerativeUIAnalytics` | onRequest | Admin analytics dashboard |
| `testInputAnalysis` | onRequest | Stage 1 test |
| `testClassifier` | onRequest | Stage 2 test |
| `testConfidenceGate` | onRequest | Stage 3 test (from stages/confidenceGate) |
| `testIntentResolution` | onRequest | Stage 4 test |
| `testMemoryQuery` | onRequest | Stage 5 test |
| `testMemoryExtraction` | onRequest | Stage 6 test |
| `testCuriosityModule` | onRequest | Stage 7 test |
| `testTrustEvaluation` | onRequest | Stage 8 test |
| `testSaveDecision` | onRequest | Stage 9 test |
| `testContextInjection` | onRequest | Stage 10 test |
| `testLLMResponse` | onRequest | Stage 11 test |
| `testPostResponseLog` | onRequest | Stage 12 test |

---

### 2.2 Pipeline Orchestrator (`functions/chat/src/pipeline/orchestrator.ts`)

**Input Interface:**
```typescript
interface PipelineInput {
  iin: string;
  message: string;
  conversationId?: string;
  sessionId?: string;
  conversationHistory?: Array<{ role: string; content: string }>;
  userProfile?: any;
  provider?: string;
  model?: string;
}
```

**Output Interface:**
```typescript
interface PipelineResult {
  success: boolean;
  response: string;
  iin: string;
  conversationId?: string;
  stages?: StageResult[];
  stageSummary?: { name: string; timeMs: number; success: boolean }[];
  totalTimeMs: number;
  memoriesUsed: number;
  memoriesSaved: number;
  intent?: string;
  provider?: string;
  error?: string;
  debug?: any;
  timestamp: string;

  // Actions Protocol
  actions?: AnyAction[];
}
```

**Action Types (AnyAction union):**
```typescript
type AnyAction =
  | RenderMemoryCardAction
  | RenderSelectionGridAction
  | RenderConflictResolverAction
  | RenderRelationshipGraphAction
  | RenderTimelineAction
  | RenderQuickRepliesAction
  | ShowToastAction;
```

---

### 2.3 Actions Builder (`buildActions` function)

**Stage → Action Mapping:**

| Stage | Output Property | Action Created |
|-------|-----------------|----------------|
| Stage 5: Memory Query | `timelineAction` | `RenderTimelineAction` |
| Stage 6: Memory Extraction | `selectionGridAction` | `RenderSelectionGridAction` |
| Stage 6: Memory Extraction | `relationshipGraphAction` | `RenderRelationshipGraphAction` |
| Stage 7: Curiosity Module | `memoryCards[]` | `RenderMemoryCardAction` (one per card) |
| Stage 9: Save Decision | `conflictResolverAction` | `RenderConflictResolverAction` |
| Stage 9: Save Decision | `conflicts[]` (fallback) | `RenderConflictResolverAction` (one per conflict) |
| Stage 10: Context Injection | `quickRepliesAction` | `RenderQuickRepliesAction` |
| Post-save (auto) | (when memoriesSaved > 0) | `ShowToastAction` (success) |

---

### 2.4 Save Endpoints

| Endpoint | Request Body | Firestore Path | Response |
|----------|--------------|----------------|----------|
| `saveMemoryCard` | `{ iin, card: { type, slots, title, tempId } }` | `memories/{auto-id}` | `{ success, memoryId, type, timestamp }` |
| `saveSelectedMemories` | `{ iin, actionId, selectedIds[], memories[] }` | `memories/{iin}/items/{auto-id}` | `{ success, savedCount, savedMemories[], skippedCount }` |
| `resolveConflict` | `{ iin, actionId, choice, oldMemoryId, newValue?, field? }` | `memories/{iin}/items/{oldMemoryId}` (update) | `{ success, action, message }` |
| `saveRelationships` | `{ iin, actionId, connections[] }` | `memories/{iin}/items/{auto-id}` | `{ success, savedCount, savedRelationships[] }` |
| `getMemoryDetails` | `{ iin, memoryId }` | `memories/{iin}/items/{memoryId}` (read) | `{ success, memory: { id, type, content, slots, createdAt, updatedAt } }` |
| `logActionInteraction` | `{ iin, actionId, actionType, interaction, metadata?, timestamp? }` | `analytics/generativeUI/interactions/{auto-id}` | `{ success }` |

---

## PART 3: FIRESTORE STRUCTURE

### 3.1 Memories Collection

**User Memories:** `memories/{iin}/items/{memoryId}`
```
{
  id: string,
  iin: string,
  type: string,           // 'fact', 'relationship', 'event', etc.
  content: string,
  slots: {
    [slotId]: { value: any, filled: boolean }
  },
  source: string,         // 'generative_ui', 'selection_grid', 'relationship_graph'
  status: 'active' | 'archived',
  tier: 'working' | 'long_term',
  relevance: number,
  context: 'personal' | 'work' | etc.,
  createdAt: Timestamp,
  updatedAt: Timestamp,
  // Optional source tracking:
  selectionGridActionId?: string,
  relationshipGraphActionId?: string,
  conflictResolvedAt?: Timestamp,
  conflictActionId?: string,
}
```

**Legacy Flat Structure:** `memories/{auto-id}` (from saveMemoryCard)
```
{
  iin: string,
  type: string,
  source: 'generative_ui',
  title: string,
  data: { [slotId]: value },
  createdAt: Timestamp,
  updatedAt: Timestamp,
  status: 'active',
  confidence: number,
  tempId?: string,
}
```

### 3.2 Config Collections

**Generative UI Actions:** `config/generativeUI/actions/{ACTION_TYPE}`
```
{
  enabled: boolean,
  name: string,
  description: string,
  icon: string (emoji),
  triggeredBy: string,
  triggeredByStage: number,
  settings: { ... action-specific settings ... },
  updatedAt: Timestamp,
}
```

**Pipeline Orchestrator:** `config/pipeline/settings/orchestrator`
```
{
  master: { pipelineEnabled, maintenanceMode, ... },
  stages: { inputAnalysis: bool, classifier: bool, ... },
  execution: { executionMode, stopOnFirstError, ... },
  errorHandling: { ... },
  performance: { timeoutMs, ... },
  debug: { enableDebugMode, ... },
  fallback: { defaultProvider, ... },
  notifications: { ... },
}
```

### 3.3 Analytics Collection

**Action Interactions:** `analytics/generativeUI/interactions/{auto-id}`
```
{
  iin: string,
  actionId: string,
  actionType: string,     // 'RENDER_MEMORY_CARD', 'RENDER_SELECTION_GRID', etc.
  interaction: string,    // 'viewed', 'completed', 'dismissed', 'error', 'save', 'cancel'
  metadata: { ... },
  timestamp: string (ISO),
  createdAt: Timestamp,
}
```

---

## PART 4: GAP ANALYSIS

### 4.1 Connection Status: Frontend → Backend

| Action Type | Chat Widget Handler | ChatService Method | Backend Endpoint | Status |
|-------------|--------------------|--------------------|------------------|--------|
| RENDER_MEMORY_CARD | `_handleSaveCard()` | `saveMemoryCard()` | `saveMemoryCard` | ✅ CONNECTED |
| RENDER_SELECTION_GRID | `_handleSelectionSubmit()` | `saveSelectedMemories()` | `saveSelectedMemories` | ✅ CONNECTED |
| RENDER_CONFLICT_RESOLVER | `_handleConflictResolution()` | `resolveConflict()` | `resolveConflict` | ✅ CONNECTED |
| RENDER_RELATIONSHIP_GRAPH | `_handleRelationshipConfirm()` | `saveRelationships()` | `saveRelationships` | ✅ CONNECTED |
| RENDER_TIMELINE | `_showEventDetails()` | `getMemoryDetails()` | `getMemoryDetails` | ✅ CONNECTED |
| RENDER_QUICK_REPLIES | `_handleQuickReply()` | `sendMessage()` | `pipelineChat` | ✅ CONNECTED |
| SHOW_TOAST | `_showToast()` | N/A (UI only) | N/A | ✅ CONNECTED |

### 4.2 Actions Flow Verification

**Pipeline Response → ChatResponse.actions[] → ChatMessage.actions → Widget Rendering → Callbacks → API:**

1. ✅ `PipelineResult.actions[]` built by `buildActions()` in orchestrator
2. ✅ `ChatResponse.fromPipelineJson()` parses `json['actions']` into `List<AppAction>`
3. ✅ `ChatMessage.actions` populated from `ChatResponse.actions`
4. ✅ `_buildAllActionWidgets()` iterates by action type
5. ✅ Each widget receives callback functions
6. ✅ Callbacks call appropriate `ChatService` methods

### 4.3 Firestore Path Consistency

| Action | Frontend Expects | Backend Writes | Match |
|--------|------------------|----------------|-------|
| Selection Grid | `memories/{iin}/items/{id}` | `memories/{iin}/items/{docRef.id}` | ✅ |
| Relationships | `memories/{iin}/items/{id}` | `memories/{iin}/items/{docRef.id}` | ✅ |
| Conflict Resolve | `memories/{iin}/items/{oldMemoryId}` | `memories/{iin}/items/{oldMemoryId}` | ✅ |
| Memory Card | ⚠️ Uses flat `memories/{id}` | `memories/{auto-id}` (flat) | ⚠️ INCONSISTENT |
| Analytics | `analytics/generativeUI/interactions` | `analytics/generativeUI/interactions` | ✅ |

### 4.4 Identified Gaps

| Gap | Severity | Description | Recommendation |
|-----|----------|-------------|----------------|
| Memory Card Path | Medium | `saveMemoryCard` uses flat `memories/{id}` instead of `memories/{iin}/items/{id}` | Migrate to nested structure for consistency |
| MemoryCard IIN | Low | Frontend MemoryCard model doesn't include IIN field | Backend extracts from request body, acceptable |
| Analytics Metadata | Low | Some widgets don't pass rich metadata to `logActionInteraction` | Enhance for better analytics |

### 4.5 Stage → Action Completeness

| Stage | Action Type | Backend Emits | Frontend Handles |
|-------|-------------|---------------|------------------|
| Stage 5 (Memory Query) | RENDER_TIMELINE | ✅ `timelineAction` | ✅ `TimelineWidget` |
| Stage 6 (Memory Extraction) | RENDER_SELECTION_GRID | ✅ `selectionGridAction` | ✅ `SelectionGridWidget` |
| Stage 6 (Memory Extraction) | RENDER_RELATIONSHIP_GRAPH | ✅ `relationshipGraphAction` | ✅ `RelationshipGraphWidget` |
| Stage 7 (Curiosity Module) | RENDER_MEMORY_CARD | ✅ `memoryCards[]` | ✅ `MemoryBadge/Expanded` |
| Stage 9 (Save Decision) | RENDER_CONFLICT_RESOLVER | ✅ `conflictResolverAction` | ✅ `ConflictResolverWidget` |
| Stage 10 (Context Injection) | RENDER_QUICK_REPLIES | ✅ `quickRepliesAction` | ✅ `QuickRepliesWidget` |
| Auto (post-save) | SHOW_TOAST | ✅ `createToastAction()` | ✅ `_showToast()` |

---

## Summary

The IAMONEAI Generative UI Actions Protocol is **fully wired end-to-end**:

1. **Backend generates actions** via `buildActions()` based on stage outputs
2. **Frontend parses actions** via `AppAction.fromJson()` factory
3. **Widgets render actions** via `_buildAllActionWidgets()` dispatcher
4. **User interactions** trigger appropriate `ChatService` methods
5. **Save endpoints** persist data to Firestore
6. **Analytics** logged via `logActionInteraction`

**One inconsistency to address:** The `saveMemoryCard` endpoint uses a flat `memories/{id}` path instead of the nested `memories/{iin}/items/{id}` structure used by other endpoints.
