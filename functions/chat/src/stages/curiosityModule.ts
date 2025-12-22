// IAMONEAI - Curiosity Module Stage (Stage 7)
// Config stored at: config/pipeline/stages/curiosity_module
// Purpose: Generate memory cards and check for missing required slots
// HYBRID mode: LLM suggests clarifications, Local decides if required

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import { GoogleGenerativeAI } from '@google/generative-ai';

const db = admin.firestore();
const secretManager = new SecretManagerServiceClient();

// Secret cache for API keys
const secretCache: Record<string, string> = {};

// ═══════════════════════════════════════════════════════════
// CONFIG INTERFACES
// ═══════════════════════════════════════════════════════════

type CuriosityLevel = 'always' | 'once' | 'ifVague' | 'never';
type IncompleteAction = 'ask' | 'savePartial' | 'reject';
type QuestionTone = 'casual' | 'friendly' | 'formal';
type CuriosityMode = 'local' | 'hybrid' | 'llm';

interface CuriosityBehavior {
  checkRequired: boolean;
  checkOptional: boolean;
  whenIncomplete: IncompleteAction;
  allowPartialAfter: number;
}

interface CuriosityLimits {
  maxQuestionsPerTurn: number;
  maxQuestionsPerMemory: number;
  questionTimeoutSeconds: number;
}

interface CuriosityStyle {
  tone: QuestionTone;
  combineRelated: boolean;
  includeContext: boolean;
}

interface CuriositySkip {
  explicitCommands: boolean;
  userSaysEnough: boolean;
  lowConfidence: boolean;
  lowConfidenceThreshold: number;
}

interface TypeCuriositySetting {
  level: CuriosityLevel;
  maxQuestions: number;
}

interface CuriosityModuleConfig {
  enabled: boolean;
  stageNumber: number;
  mode: CuriosityMode;  // 'local' | 'hybrid' | 'llm'
  behavior: CuriosityBehavior;
  limits: CuriosityLimits;
  style: CuriosityStyle;
  skip: CuriositySkip;
  typeSettings: Record<string, TypeCuriositySetting>;
}

// ═══════════════════════════════════════════════════════════
// SLOT INTERFACES (matches Stage 6 output)
// ═══════════════════════════════════════════════════════════

interface SlotConfig {
  id: string;
  label: string;
  icon: string;
  inputType: 'text' | 'dropdown' | 'datePicker' | 'timePicker' | 'chips' | 'toggle' | 'textarea';
  placeholder?: string;
  questionTemplate?: string;
  options?: string[];
}

interface SlotValue {
  value: any;
  filled: boolean;
  source?: 'extracted' | 'inferred' | 'user';
}

// ═══════════════════════════════════════════════════════════
// MEMORY INTERFACES
// ═══════════════════════════════════════════════════════════

interface ExtractedMemory {
  tempId: string;
  content: string;
  type: string;
  confidence: number;
  context?: string;
  tags?: string[];
  categories?: string[];
  tier?: string;

  // Structured slots from Stage 6
  slots: Record<string, SlotValue>;

  // Type config for UI
  typeConfig: {
    icon: string;
    name: string;
    color: string;
    requiredSlots: SlotConfig[];
    optionalSlots: SlotConfig[];
  };

  // Completeness from Stage 6
  complete: boolean;
  missingRequired: string[];

  // Legacy fields
  entities?: {
    people?: string[];
    places?: string[];
    dates?: string[];
  };
  schedule?: {
    date?: string;
    time?: string;
  };
  _extractionMethod?: string;
  _explicitCommand?: boolean;
  _originalMessage?: string;
}

// ═══════════════════════════════════════════════════════════
// MEMORY CARD INTERFACE (for Generative UI)
// ═══════════════════════════════════════════════════════════

interface MemoryCard {
  tempId: string;
  type: string;
  status: 'pending' | 'complete';

  // Display
  icon: string;
  title: string;
  subtitle: string;
  color: string;

  // Completeness
  complete: boolean;
  missingRequired: string[];

  // Full config for UI rendering
  typeConfig: {
    requiredSlots: SlotConfig[];
    optionalSlots: SlotConfig[];
  };

  // Current values
  slots: Record<string, { value: any; filled: boolean }>;
}

// ═══════════════════════════════════════════════════════════
// INPUT/OUTPUT INTERFACES
// ═══════════════════════════════════════════════════════════

// Conflict result from Stage 6.5
interface ConflictResult {
  hasConflict: boolean;
  conflictType: 'CONFLICT' | 'UPDATE' | 'ADDITION' | 'DUPLICATE' | 'NONE';
  confidence: number;
  reason: string;
  existingMemory: {
    id: string;
    content: string;
    type: string;
    slots?: Record<string, any>;
  } | null;
  extractedMemory: ExtractedMemory;
  needsClarification: boolean;
  autoResolved: boolean;
}

interface CuriosityModuleInput {
  iin: string;
  extractedMemories: ExtractedMemory[];
  originalMessage: string;
  questionsAskedCount?: number;
  userDismissed?: boolean;
  intent?: string;
  // From Stage 6.5: Conflicts that need user clarification
  pendingConflicts?: ConflictResult[];
}

interface CuriosityModuleOutput {
  stage: string;
  stageNumber: number;

  // Pass-through
  memories: ExtractedMemory[];

  // Decision
  holdForClarification: boolean;

  // Memory cards for Generative UI
  memoryCards: MemoryCard[];

  // Conflict resolution cards (from Stage 6.5)
  conflictCards: ConflictCard[];

  // Fallback text questions (if UI not supported)
  questions: string[];

  // Analysis (legacy)
  action: 'ask' | 'proceed' | 'savePartial' | 'reject';
  completenessScore: number;

  // Conflicts summary
  conflicts: {
    count: number;
    pendingResolution: ConflictResult[];
  };

  config: {
    source: string;
    enabled: boolean;
    cardsGenerated: number;
    incompleteCount: number;
    conflictsDetected: number;
    behavior?: CuriosityBehavior;
    limits?: CuriosityLimits;
    style?: CuriosityStyle;
  };
  processingTime: string;
  timestamp: string;
}

// Conflict card for UI
interface ConflictCard {
  conflictId: string;
  type: 'CONFLICT' | 'UPDATE';
  existingMemory: {
    id: string;
    content: string;
    type: string;
  };
  newMemory: {
    tempId: string;
    content: string;
    type: string;
  };
  question: string;
  options: {
    id: string;
    label: string;
    action: 'replace' | 'keep_both' | 'discard';
  }[];
}

// ═══════════════════════════════════════════════════════════
// CONFIG LOADER
// ═══════════════════════════════════════════════════════════

async function getCuriosityModuleConfig(): Promise<CuriosityModuleConfig> {
  const defaults: CuriosityModuleConfig = {
    enabled: true,
    stageNumber: 7,
    mode: 'local',  // 'local' | 'hybrid' | 'llm' - start with local for safety
    behavior: {
      checkRequired: true,
      checkOptional: false,
      whenIncomplete: 'ask',
      allowPartialAfter: 3,
    },
    limits: {
      maxQuestionsPerTurn: 1,
      maxQuestionsPerMemory: 3,
      questionTimeoutSeconds: 60,
    },
    style: {
      tone: 'friendly',
      combineRelated: true,
      includeContext: true,
    },
    skip: {
      explicitCommands: true,
      userSaysEnough: true,
      lowConfidence: false,
      lowConfidenceThreshold: 0.5,
    },
    typeSettings: {
      event: { level: 'always', maxQuestions: 3 },
      todo: { level: 'always', maxQuestions: 2 },
      goal: { level: 'once', maxQuestions: 2 },
      relationship: { level: 'once', maxQuestions: 1 },
      preference: { level: 'never', maxQuestions: 0 },
      fact: { level: 'ifVague', maxQuestions: 1 },
    },
  };

  try {
    const doc = await db.collection('config').doc('pipeline')
      .collection('stages').doc('curiosity_module').get();

    if (!doc.exists) {
      console.log('[CURIOSITY] Config not found, using defaults');
      return defaults;
    }

    const data = doc.data() ?? {};
    const behavior = data.behavior ?? {};
    const limits = data.limits ?? {};
    const style = data.style ?? {};
    const skip = data.skip ?? {};

    const typeSettings: Record<string, TypeCuriositySetting> = {};
    const typeData = data.typeSettings ?? {};
    for (const [type, setting] of Object.entries(typeData)) {
      const s = setting as any;
      typeSettings[type] = {
        level: s.level ?? 'once',
        maxQuestions: s.maxQuestions ?? 2,
      };
    }

    return {
      enabled: data.enabled ?? defaults.enabled,
      stageNumber: data.stageNumber ?? defaults.stageNumber,
      mode: (data.mode as CuriosityMode) ?? defaults.mode,
      behavior: {
        checkRequired: behavior.checkRequired ?? defaults.behavior.checkRequired,
        checkOptional: behavior.checkOptional ?? defaults.behavior.checkOptional,
        whenIncomplete: behavior.whenIncomplete ?? defaults.behavior.whenIncomplete,
        allowPartialAfter: behavior.allowPartialAfter ?? defaults.behavior.allowPartialAfter,
      },
      limits: {
        maxQuestionsPerTurn: limits.maxQuestionsPerTurn ?? defaults.limits.maxQuestionsPerTurn,
        maxQuestionsPerMemory: limits.maxQuestionsPerMemory ?? defaults.limits.maxQuestionsPerMemory,
        questionTimeoutSeconds: limits.questionTimeoutSeconds ?? defaults.limits.questionTimeoutSeconds,
      },
      style: {
        tone: style.tone ?? defaults.style.tone,
        combineRelated: style.combineRelated ?? defaults.style.combineRelated,
        includeContext: style.includeContext ?? defaults.style.includeContext,
      },
      skip: {
        explicitCommands: skip.explicitCommands ?? defaults.skip.explicitCommands,
        userSaysEnough: skip.userSaysEnough ?? defaults.skip.userSaysEnough,
        lowConfidence: skip.lowConfidence ?? defaults.skip.lowConfidence,
        lowConfidenceThreshold: skip.lowConfidenceThreshold ?? defaults.skip.lowConfidenceThreshold,
      },
      typeSettings: Object.keys(typeSettings).length > 0 ? typeSettings : defaults.typeSettings,
    };
  } catch (error) {
    console.error('[CURIOSITY] Error loading config:', error);
    return defaults;
  }
}

// ═══════════════════════════════════════════════════════════
// LLM HELPERS FOR HYBRID MODE
// ═══════════════════════════════════════════════════════════

/**
 * Get secret from Secret Manager (with caching)
 */
async function getSecret(name: string): Promise<string> {
  if (secretCache[name]) {
    return secretCache[name];
  }

  const projectId = process.env.GCLOUD_PROJECT || 'app-iamoneai-c36ec';
  const [version] = await secretManager.accessSecretVersion({
    name: `projects/${projectId}/secrets/${name}/versions/latest`,
  });

  const payload = version.payload?.data?.toString() || '';
  secretCache[name] = payload;
  return payload;
}

/**
 * LLM Suggestion for ambiguity/vagueness detection
 */
interface LLMSuggestion {
  slotId: string;
  issue: 'ambiguous' | 'vague' | 'missing' | 'incomplete';
  question: string;
  reason: string;
  priority: 'high' | 'medium' | 'low';
  resolvedValue?: string;  // For date resolution like "next tuesday" → "2025-12-24"
}

interface LLMAnalysisResult {
  suggestions: LLMSuggestion[];
  resolvedSlots: Record<string, string>;  // slotId → resolved value
  analysis: string;  // Brief explanation
}

/**
 * Build the prompt for LLM ambiguity detection
 */
function buildAmbiguityDetectionPrompt(
  memory: ExtractedMemory,
  originalMessage: string,
  currentDate: string
): string {
  const slots = memory.slots || {};
  const slotSummary = Object.entries(slots)
    .map(([key, val]) => `  - ${key}: ${val?.value ?? 'null'} (filled: ${val?.filled ?? false})`)
    .join('\n');

  return `You are an AI assistant analyzing a memory extraction for ambiguity and missing information.

TODAY'S DATE: ${currentDate}

ORIGINAL USER MESSAGE:
"${originalMessage}"

EXTRACTED MEMORY:
- Type: ${memory.type}
- Content: ${memory.content}
- Slots:
${slotSummary}

REQUIRED SLOTS for ${memory.type}: ${memory.typeConfig?.requiredSlots?.map(s => s.id).join(', ') || 'none defined'}

YOUR TASK:
1. Check if any filled slots have AMBIGUOUS or VAGUE values
2. For DATE slots: resolve relative dates (e.g., "next tuesday" → actual date based on today)
3. For TIME slots: check if time is needed but missing
4. Identify any critical missing information

RESPOND IN THIS EXACT JSON FORMAT:
{
  "suggestions": [
    {
      "slotId": "when_date",
      "issue": "ambiguous",
      "question": "Which Tuesday do you mean - December 24th or December 31st?",
      "reason": "The date 'tuesday' is ambiguous without specifying which week",
      "priority": "high",
      "resolvedValue": "2025-12-24"
    }
  ],
  "resolvedSlots": {
    "when_date": "2025-12-24"
  },
  "analysis": "Brief explanation of what was found"
}

RULES:
- Only include suggestions for actual issues, not hypotheticals
- priority: "high" for required slots, "medium" for optional but useful, "low" for nice-to-have
- resolvedValue: Only include if you can confidently resolve (e.g., "next tuesday" from today)
- If no issues found, return empty suggestions array
- Be concise in questions - they will be shown to the user

JSON RESPONSE:`;
}

/**
 * Call LLM for ambiguity detection (Gemini)
 */
async function analyzeMemoryWithLLM(
  memory: ExtractedMemory,
  originalMessage: string
): Promise<LLMAnalysisResult> {
  const startTime = Date.now();

  try {
    // Get API key
    const apiKey = await getSecret('gemini-api-key');
    if (!apiKey) {
      console.error('[CURIOSITY-LLM] No API key found');
      return { suggestions: [], resolvedSlots: {}, analysis: 'API key not available' };
    }

    // Build prompt with current date
    const currentDate = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
    const prompt = buildAmbiguityDetectionPrompt(memory, originalMessage, currentDate);

    // Call Gemini
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
      model: 'gemini-2.0-flash-exp',
      generationConfig: {
        temperature: 0.2,  // Low temperature for structured analysis
        maxOutputTokens: 500,
        topP: 0.9,
      },
    });

    const result = await model.generateContent(prompt);
    const responseText = result.response.text();

    console.log(`[CURIOSITY-LLM] Response in ${Date.now() - startTime}ms`);

    // Parse JSON response
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      console.error('[CURIOSITY-LLM] Could not parse JSON from response');
      return { suggestions: [], resolvedSlots: {}, analysis: 'Failed to parse LLM response' };
    }

    const parsed = JSON.parse(jsonMatch[0]) as LLMAnalysisResult;

    // Validate and sanitize
    const sanitized: LLMAnalysisResult = {
      suggestions: Array.isArray(parsed.suggestions)
        ? parsed.suggestions.filter(s =>
            s && typeof s.slotId === 'string' && typeof s.question === 'string'
          ).map(s => ({
            slotId: s.slotId,
            issue: s.issue || 'ambiguous',
            question: s.question,
            reason: s.reason || '',
            priority: s.priority || 'medium',
            resolvedValue: s.resolvedValue,
          }))
        : [],
      resolvedSlots: typeof parsed.resolvedSlots === 'object' && parsed.resolvedSlots !== null
        ? parsed.resolvedSlots
        : {},
      analysis: parsed.analysis || '',
    };

    console.log(`[CURIOSITY-LLM] Found ${sanitized.suggestions.length} suggestions`);
    return sanitized;

  } catch (error: any) {
    console.error('[CURIOSITY-LLM] Error:', error.message);
    return { suggestions: [], resolvedSlots: {}, analysis: `Error: ${error.message}` };
  }
}

/**
 * LOCAL DECISION: Decide which LLM suggestions to act on
 * This is where LOCAL owns control in HYBRID mode
 */
function decideOnSuggestions(
  suggestions: LLMSuggestion[],
  memory: ExtractedMemory,
  config: CuriosityModuleConfig,
  questionsAskedCount: number
): { questionsToAsk: LLMSuggestion[]; slotsToResolve: Record<string, string> } {
  const questionsToAsk: LLMSuggestion[] = [];
  const slotsToResolve: Record<string, string> = {};

  const requiredSlotIds = (memory.typeConfig?.requiredSlots || []).map(s => s.id);
  const maxQuestions = config.limits.maxQuestionsPerTurn;

  for (const suggestion of suggestions) {
    // Skip if we've already asked too many questions
    if (questionsToAsk.length >= maxQuestions) {
      console.log(`[CURIOSITY-LOCAL] Skipping suggestion for ${suggestion.slotId} - max questions reached`);
      continue;
    }

    // Skip if user has been asked too many questions overall
    if (questionsAskedCount + questionsToAsk.length >= config.behavior.allowPartialAfter) {
      console.log(`[CURIOSITY-LOCAL] Skipping suggestion for ${suggestion.slotId} - user fatigue limit`);
      continue;
    }

    const isRequired = requiredSlotIds.includes(suggestion.slotId);

    // DECISION LOGIC (LOCAL owns this):
    // 1. High priority + required slot → MUST ASK
    // 2. Has resolved value → AUTO-RESOLVE, don't ask
    // 3. Medium priority + required → ASK
    // 4. Low priority or optional → SKIP (don't bother user)

    if (suggestion.resolvedValue) {
      // LLM was able to resolve (e.g., "next tuesday" → "2025-12-24")
      slotsToResolve[suggestion.slotId] = suggestion.resolvedValue;
      console.log(`[CURIOSITY-LOCAL] Auto-resolving ${suggestion.slotId} → ${suggestion.resolvedValue}`);
    } else if (suggestion.priority === 'high' && isRequired) {
      // Critical ambiguity in required slot - must ask
      questionsToAsk.push(suggestion);
      console.log(`[CURIOSITY-LOCAL] Will ask about ${suggestion.slotId} (high priority, required)`);
    } else if (suggestion.priority === 'medium' && isRequired) {
      // Medium priority but required - ask
      questionsToAsk.push(suggestion);
      console.log(`[CURIOSITY-LOCAL] Will ask about ${suggestion.slotId} (medium priority, required)`);
    } else {
      // Low priority or optional - skip
      console.log(`[CURIOSITY-LOCAL] Skipping ${suggestion.slotId} (${suggestion.priority} priority, ${isRequired ? 'required' : 'optional'})`);
    }
  }

  return { questionsToAsk, slotsToResolve };
}

// ═══════════════════════════════════════════════════════════
// CARD BUILDING HELPERS
// ═══════════════════════════════════════════════════════════

function capitalize(str: string | null | undefined): string {
  if (!str) return '';
  return str.charAt(0).toUpperCase() + str.slice(1);
}

function buildTitle(memory: ExtractedMemory): string {
  const slots = memory.slots || {};

  switch (memory.type) {
    case 'event':
      return capitalize(slots.what?.value) || 'Event';

    case 'relationship':
      return capitalize(slots.person_name?.value) || 'Person';

    case 'preference':
      return capitalize(slots.what?.value) || 'Preference';

    case 'todo':
      const task = slots.task?.value || '';
      return capitalize(task.substring(0, 30)) || 'Task';

    case 'goal':
      const goal = slots.goal?.value || '';
      return capitalize(goal.substring(0, 30)) || 'Goal';

    case 'fact':
      return capitalize(slots.subject?.value) || 'Fact';

    default:
      return capitalize(memory.type);
  }
}

function buildSubtitle(memory: ExtractedMemory): string {
  const slots = memory.slots || {};

  switch (memory.type) {
    case 'event':
      const date = slots.when_date?.value || '';
      const time = slots.when_time?.value || '';
      if (date && time) return `${date} at ${time}`;
      if (date) return date;
      return 'No date set';

    case 'relationship':
      return capitalize(slots.relationship_type?.value) || '';

    case 'preference':
      return slots.sentiment?.value || '';

    case 'todo':
      return slots.due_date?.value || '';

    case 'goal':
      return slots.target_date?.value || '';

    case 'fact':
      const value = slots.value?.value || '';
      return value.substring(0, 40);

    default:
      return '';
  }
}

function buildMemoryCard(memory: ExtractedMemory): MemoryCard {
  // Convert slots to simpler format for the card
  // DEFENSIVE: Filter out invalid slot keys (undefined, null, empty string)
  const cardSlots: Record<string, { value: any; filled: boolean }> = {};
  const rawSlots = memory.slots || {};

  for (const [key, val] of Object.entries(rawSlots)) {
    // Skip invalid keys
    if (!key || key === 'undefined' || key === 'null') {
      console.warn(`[CURIOSITY] Skipping invalid slot key: "${key}"`);
      continue;
    }

    // DEFENSIVE: Handle null/undefined val
    if (val === null || val === undefined) {
      cardSlots[key] = { value: null, filled: false };
    } else {
      cardSlots[key] = {
        value: val.value ?? null,
        filled: val.filled ?? false,
      };
    }
  }

  // DEFENSIVE: Ensure memory has required properties
  const safeMemory = {
    tempId: memory.tempId || `temp_${Date.now()}`,
    type: memory.type || 'unknown',
    complete: memory.complete ?? false,
    missingRequired: Array.isArray(memory.missingRequired) ? memory.missingRequired : [],
    typeConfig: memory.typeConfig || { icon: '📝', name: 'Unknown', color: '#607D8B', requiredSlots: [], optionalSlots: [] },
  };

  return {
    tempId: safeMemory.tempId,
    type: safeMemory.type,
    status: safeMemory.complete ? 'complete' : 'pending',

    icon: safeMemory.typeConfig.icon || '📝',
    title: buildTitle(memory),
    subtitle: buildSubtitle(memory),
    color: safeMemory.typeConfig.color || '#607D8B',

    complete: safeMemory.complete,
    missingRequired: safeMemory.missingRequired,

    typeConfig: {
      requiredSlots: Array.isArray(safeMemory.typeConfig.requiredSlots) ? safeMemory.typeConfig.requiredSlots : [],
      optionalSlots: Array.isArray(safeMemory.typeConfig.optionalSlots) ? safeMemory.typeConfig.optionalSlots : [],
    },

    slots: cardSlots,
  };
}

// ═══════════════════════════════════════════════════════════
// QUESTION GENERATION
// ═══════════════════════════════════════════════════════════

function generateQuestions(memory: ExtractedMemory): string[] {
  const questions: string[] = [];

  // DEFENSIVE: Handle missing/invalid missingRequired
  const missingRequired = Array.isArray(memory.missingRequired) ? memory.missingRequired : [];
  if (missingRequired.length === 0) {
    return questions;
  }

  // DEFENSIVE: Handle missing typeConfig
  const requiredSlots = Array.isArray(memory.typeConfig?.requiredSlots) ? memory.typeConfig.requiredSlots : [];
  const slots = memory.slots || {};

  for (const slotId of missingRequired) {
    // DEFENSIVE: Skip invalid slot IDs
    if (!slotId || slotId === 'undefined' || slotId === 'null') {
      console.warn(`[CURIOSITY] Skipping invalid missing slot ID: "${slotId}"`);
      continue;
    }

    const slotConfig = requiredSlots.find(s => s?.id === slotId);

    if (slotConfig?.questionTemplate) {
      // Replace placeholders like {what} with actual values
      let question = slotConfig.questionTemplate;

      for (const [key, val] of Object.entries(slots)) {
        // DEFENSIVE: Skip invalid keys and null values
        if (!key || key === 'undefined' || !val) continue;
        if (val.filled && val.value) {
          question = question.replace(`{${key}}`, String(val.value));
        }
      }

      questions.push(question);
    } else {
      // Default question
      const label = slotConfig?.label || slotId;
      questions.push(`What is the ${label.toLowerCase()}?`);
    }
  }

  return questions;
}

// ═══════════════════════════════════════════════════════════
// COMPLETENESS CALCULATION
// ═══════════════════════════════════════════════════════════

function calculateCompletenessScore(memories: ExtractedMemory[]): number {
  // DEFENSIVE: Handle null/undefined/empty
  if (!Array.isArray(memories) || memories.length === 0) return 1;

  let totalScore = 0;

  for (const memory of memories) {
    // DEFENSIVE: Skip null/undefined memories
    if (!memory) continue;

    const requiredSlots = Array.isArray(memory.typeConfig?.requiredSlots) ? memory.typeConfig.requiredSlots : [];
    const missingRequired = Array.isArray(memory.missingRequired) ? memory.missingRequired : [];
    const missingCount = missingRequired.length;
    const requiredCount = requiredSlots.length;

    if (requiredCount === 0) {
      totalScore += 1;
    } else {
      const filledRequired = Math.max(0, requiredCount - missingCount);
      totalScore += filledRequired / requiredCount;
    }
  }

  return memories.length > 0 ? totalScore / memories.length : 1;
}

// ═══════════════════════════════════════════════════════════
// MAIN PROCESSING
// ═══════════════════════════════════════════════════════════

async function processCuriosityModule(
  input: CuriosityModuleInput
): Promise<CuriosityModuleOutput> {
  const startTime = Date.now();

  // Load config
  const config = await getCuriosityModuleConfig();

  console.log(`[CURIOSITY] Mode: ${config.mode}, Enabled: ${config.enabled}`);

  // DEFENSIVE: Validate input
  const safeInput = {
    iin: input.iin || 'unknown',
    extractedMemories: Array.isArray(input.extractedMemories) ? input.extractedMemories.filter(m => m != null) : [],
    originalMessage: input.originalMessage || '',
    questionsAskedCount: input.questionsAskedCount ?? 0,
    userDismissed: input.userDismissed ?? false,
    intent: input.intent || undefined,
    pendingConflicts: Array.isArray(input.pendingConflicts) ? input.pendingConflicts : [],
  };

  // Log if there are conflicts from Stage 6.5
  if (safeInput.pendingConflicts.length > 0) {
    console.log(`[CURIOSITY] Received ${safeInput.pendingConflicts.length} conflicts from Stage 6.5`);
  }

  // If disabled, pass through
  if (!config.enabled) {
    return {
      stage: 'Curiosity Module',
      stageNumber: 7,
      memories: safeInput.extractedMemories,
      holdForClarification: false,
      memoryCards: [],
      conflictCards: [],
      questions: [],
      action: 'proceed',
      completenessScore: 1,
      conflicts: {
        count: safeInput.pendingConflicts.length,
        pendingResolution: safeInput.pendingConflicts,
      },
      config: {
        source: 'config/pipeline/stages/curiosity_module',
        enabled: false,
        cardsGenerated: 0,
        incompleteCount: 0,
        conflictsDetected: safeInput.pendingConflicts.length,
      },
      processingTime: `${Date.now() - startTime}ms`,
      timestamp: new Date().toISOString(),
    };
  }

  // If no memories AND no conflicts to process, return early
  if (safeInput.extractedMemories.length === 0 && safeInput.pendingConflicts.length === 0) {
    console.log('[CURIOSITY] No memories or conflicts to process');
    return {
      stage: 'Curiosity Module',
      stageNumber: 7,
      memories: [],
      holdForClarification: false,
      memoryCards: [],
      conflictCards: [],
      questions: [],
      action: 'proceed',
      completenessScore: 1,
      conflicts: {
        count: 0,
        pendingResolution: [],
      },
      config: {
        source: 'config/pipeline/stages/curiosity_module',
        enabled: config.enabled,
        cardsGenerated: 0,
        incompleteCount: 0,
        conflictsDetected: 0,
      },
      processingTime: `${Date.now() - startTime}ms`,
      timestamp: new Date().toISOString(),
    };
  }

  const memoryCards: MemoryCard[] = [];
  const conflictCards: ConflictCard[] = [];
  const allQuestions: string[] = [];
  let holdForClarification = false;

  // ═══════════════════════════════════════════════════════════
  // PROCESS CONFLICTS FROM STAGE 6.5
  // ═══════════════════════════════════════════════════════════
  if (safeInput.pendingConflicts.length > 0) {
    console.log(`[CURIOSITY] Processing ${safeInput.pendingConflicts.length} conflicts`);

    for (const conflict of safeInput.pendingConflicts) {
      if (!conflict.existingMemory || !conflict.extractedMemory) continue;

      const conflictCard: ConflictCard = {
        conflictId: `conflict_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`,
        type: conflict.conflictType === 'UPDATE' ? 'UPDATE' : 'CONFLICT',
        existingMemory: {
          id: conflict.existingMemory.id,
          content: conflict.existingMemory.content,
          type: conflict.existingMemory.type,
        },
        newMemory: {
          tempId: conflict.extractedMemory.tempId,
          content: conflict.extractedMemory.content,
          type: conflict.extractedMemory.type,
        },
        question: conflict.conflictType === 'UPDATE'
          ? `I remember "${conflict.existingMemory.content}". Did this change to "${conflict.extractedMemory.content}"?`
          : `I have conflicting information: "${conflict.existingMemory.content}" vs "${conflict.extractedMemory.content}". Which is correct?`,
        options: [
          { id: 'replace', label: 'Update to new', action: 'replace' },
          { id: 'keep_both', label: 'Keep both', action: 'keep_both' },
          { id: 'discard', label: 'Keep old, discard new', action: 'discard' },
        ],
      };

      conflictCards.push(conflictCard);

      // Add fallback text question
      allQuestions.push(conflictCard.question);

      // Conflicts always need clarification
      holdForClarification = true;

      console.log(`[CURIOSITY] Created conflict card: ${conflict.conflictType} - "${conflict.existingMemory.content}" vs "${conflict.extractedMemory.content}"`);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // PROCESS BASED ON MODE
  // ═══════════════════════════════════════════════════════════

  if (config.mode === 'local') {
    // LOCAL MODE: Use only local slot checking (current behavior)
    console.log('[CURIOSITY] Running in LOCAL mode');

    for (const memory of safeInput.extractedMemories) {
      try {
        // Build card with defensive coding
        const card = buildMemoryCard(memory);
        memoryCards.push(card);

        console.log(`[CURIOSITY] ${card.icon} ${card.title}: complete=${card.complete}, missing=${card.missingRequired.join(',') || 'none'}`);

        // If any required slots missing, hold for clarification
        if (!card.complete && card.missingRequired.length > 0) {
          holdForClarification = true;

          // Generate fallback questions
          const questions = generateQuestions(memory);
          allQuestions.push(...questions);
        }
      } catch (err: any) {
        console.error(`[CURIOSITY] Error processing memory: ${err.message}`);
        // Continue with other memories
      }
    }

  } else if (config.mode === 'hybrid') {
    // ═══════════════════════════════════════════════════════════
    // HYBRID MODE: LLM suggests clarifications, LOCAL decides
    // ═══════════════════════════════════════════════════════════
    console.log('[CURIOSITY] Running in HYBRID mode');

    for (const memory of safeInput.extractedMemories) {
      try {
        // Step 1: Build card with local slot checking
        const card = buildMemoryCard(memory);
        memoryCards.push(card);

        console.log(`[CURIOSITY-HYBRID] ${card.icon} ${card.title}: complete=${card.complete}, missing=${card.missingRequired.join(',') || 'none'}`);

        // Step 2: Local check - any missing required slots?
        const hasLocalIssues = !card.complete && card.missingRequired.length > 0;

        // Step 3: LLM analysis for ambiguity/vagueness
        console.log('[CURIOSITY-HYBRID] Calling LLM for ambiguity detection...');
        const llmAnalysis = await analyzeMemoryWithLLM(memory, safeInput.originalMessage);

        console.log(`[CURIOSITY-HYBRID] LLM analysis: ${llmAnalysis.suggestions.length} suggestions, analysis: ${llmAnalysis.analysis}`);

        // Step 4: LOCAL DECISION - what to do with LLM suggestions
        const { questionsToAsk, slotsToResolve } = decideOnSuggestions(
          llmAnalysis.suggestions,
          memory,
          config,
          safeInput.questionsAskedCount
        );

        // Step 5: Apply auto-resolved slots (e.g., "next tuesday" → "2025-12-24")
        if (Object.keys(slotsToResolve).length > 0) {
          console.log('[CURIOSITY-HYBRID] Auto-resolving slots:', slotsToResolve);
          for (const [slotId, resolvedValue] of Object.entries(slotsToResolve)) {
            if (memory.slots && memory.slots[slotId]) {
              memory.slots[slotId] = {
                value: resolvedValue,
                filled: true,
                source: 'llm_resolved' as any,
              };
              // Update card slot too
              if (card.slots[slotId]) {
                card.slots[slotId] = { value: resolvedValue, filled: true };
              }
              // Remove from missing if it was missing
              const missingIdx = card.missingRequired.indexOf(slotId);
              if (missingIdx > -1) {
                card.missingRequired.splice(missingIdx, 1);
              }
            }
          }
          // Recalculate completeness
          card.complete = card.missingRequired.length === 0;
          card.status = card.complete ? 'complete' : 'pending';
        }

        // Step 6: Add LLM-suggested questions (filtered by local decision)
        if (questionsToAsk.length > 0) {
          holdForClarification = true;
          for (const q of questionsToAsk) {
            allQuestions.push(q.question);
            // Add to missingRequired if not already there
            if (!card.missingRequired.includes(q.slotId)) {
              card.missingRequired.push(q.slotId);
            }
          }
          card.complete = false;
          card.status = 'pending';
          console.log(`[CURIOSITY-HYBRID] Will ask ${questionsToAsk.length} questions from LLM suggestions`);
        }

        // Step 7: Also add local-detected missing slots (if LLM missed them)
        if (hasLocalIssues) {
          const localQuestions = generateQuestions(memory);
          for (const lq of localQuestions) {
            if (!allQuestions.includes(lq)) {
              allQuestions.push(lq);
            }
          }
          holdForClarification = true;
        }

      } catch (err: any) {
        console.error(`[CURIOSITY-HYBRID] Error processing memory: ${err.message}`);
        // Fallback to local-only on error
        try {
          const card = buildMemoryCard(memory);
          if (!memoryCards.find(c => c.tempId === card.tempId)) {
            memoryCards.push(card);
          }
          if (!card.complete && card.missingRequired.length > 0) {
            holdForClarification = true;
            const questions = generateQuestions(memory);
            allQuestions.push(...questions);
          }
        } catch (fallbackErr: any) {
          console.error(`[CURIOSITY-HYBRID] Fallback also failed: ${fallbackErr.message}`);
        }
      }
    }

  } else if (config.mode === 'llm') {
    // LLM MODE: Full LLM-driven curiosity
    // TODO: Implement full LLM curiosity module
    console.log('[CURIOSITY] Running in LLM mode (not yet implemented, falling back to local)');

    for (const memory of safeInput.extractedMemories) {
      try {
        const card = buildMemoryCard(memory);
        memoryCards.push(card);

        console.log(`[CURIOSITY] ${card.icon} ${card.title}: complete=${card.complete}, missing=${card.missingRequired.join(',') || 'none'}`);

        if (!card.complete && card.missingRequired.length > 0) {
          holdForClarification = true;
          const questions = generateQuestions(memory);
          allQuestions.push(...questions);
        }

        // TODO: LLM-only mode would:
        // - Send memory to LLM with context
        // - LLM decides what clarifications are needed
        // - LLM generates natural questions
        // - No local slot-based checks

      } catch (err: any) {
        console.error(`[CURIOSITY] Error processing memory: ${err.message}`);
      }
    }

  } else {
    // Unknown mode - default to local
    console.warn(`[CURIOSITY] Unknown mode: ${config.mode}, defaulting to local`);

    for (const memory of safeInput.extractedMemories) {
      try {
        const card = buildMemoryCard(memory);
        memoryCards.push(card);

        if (!card.complete && card.missingRequired.length > 0) {
          holdForClarification = true;
          const questions = generateQuestions(memory);
          allQuestions.push(...questions);
        }
      } catch (err: any) {
        console.error(`[CURIOSITY] Error processing memory: ${err.message}`);
      }
    }
  }

  // Limit questions per turn
  const limitedQuestions = allQuestions.slice(0, config.limits.maxQuestionsPerTurn);

  // Calculate overall completeness
  const completenessScore = calculateCompletenessScore(safeInput.extractedMemories);

  // Determine action
  let action: 'ask' | 'proceed' | 'savePartial' | 'reject' = 'proceed';
  if (holdForClarification) {
    action = config.behavior.whenIncomplete;
  }

  const incompleteCount = memoryCards.filter(c => !c.complete).length;

  console.log(`[CURIOSITY] Generated ${memoryCards.length} memory cards, ${conflictCards.length} conflict cards, ${incompleteCount} incomplete, holdForClarification=${holdForClarification}, mode=${config.mode}`);

  return {
    stage: 'Curiosity Module',
    stageNumber: 7,
    memories: safeInput.extractedMemories,
    holdForClarification,
    memoryCards,
    conflictCards,
    questions: limitedQuestions,
    action,
    completenessScore,
    conflicts: {
      count: safeInput.pendingConflicts.length,
      pendingResolution: safeInput.pendingConflicts,
    },
    config: {
      source: 'config/pipeline/stages/curiosity_module',
      enabled: config.enabled,
      cardsGenerated: memoryCards.length,
      incompleteCount,
      conflictsDetected: conflictCards.length,
      behavior: config.behavior,
      limits: config.limits,
      style: config.style,
    },
    processingTime: `${Date.now() - startTime}ms`,
    timestamp: new Date().toISOString(),
  };
}

// ═══════════════════════════════════════════════════════════
// HTTP ENDPOINT
// ═══════════════════════════════════════════════════════════

export const testCuriosityModule = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    const { iin, memories, extractedMemories, originalMessage, questionsAskedCount, userDismissed, intent } = req.body;

    if (!iin) {
      res.status(400).json({ error: 'IIN is required' });
      return;
    }

    // Support both 'memories' and 'extractedMemories' field names
    const memoryArray = extractedMemories || memories;

    if (!memoryArray || !Array.isArray(memoryArray) || memoryArray.length === 0) {
      res.status(400).json({ error: 'Memories array is required (use extractedMemories or memories field)' });
      return;
    }

    console.log(`[CURIOSITY] Processing ${memoryArray.length} memories for IIN: ${iin}`);

    const result = await processCuriosityModule({
      iin,
      extractedMemories: memoryArray,
      originalMessage: originalMessage ?? '',
      questionsAskedCount,
      userDismissed,
      intent,
    });

    res.status(200).json({
      input: {
        iin,
        memoryCount: memoryArray.length,
        questionsAskedCount: questionsAskedCount ?? 0,
        userDismissed: userDismissed ?? false,
      },
      ...result,
    });
  } catch (error: any) {
    console.error('[CURIOSITY] Error:', error);
    res.status(500).json({
      error: error.message ?? 'Internal server error',
    });
  }
});

export { processCuriosityModule, getCuriosityModuleConfig };
