// IAMONEAI - Pipeline Orchestrator with Full Dynamic Configuration
// Config stored at: config/pipeline/settings/orchestrator

import { onRequest, Request } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { Response } from 'express';

// Import all stage processors with their actual export names
import { processConfidenceGate } from '../stages/confidenceGate';
import { processIntentResolution } from '../stages/intentResolution';
import { queryMemories } from '../stages/memoryQuery';
import { extractMemories } from '../stages/memoryExtraction';
import { checkConflicts } from '../stages/conflictCheck';
import { processCuriosityModule } from '../stages/curiosityModule';
import { processTrustEvaluation } from '../stages/trustEvaluation';
import { makeSaveDecision } from '../stages/saveDecision';
import { buildContextPrompt } from '../stages/contextInjection';
import { generateLLMResponse } from '../stages/llmResponse';
import { processPostResponseLog } from '../stages/postResponseLog';

// Import Actions Protocol
import {
  RenderMemoryCardAction,
  RenderSelectionGridAction,
  RenderConflictResolverAction,
  RenderRelationshipGraphAction,
  RenderTimelineAction,
  RenderQuickRepliesAction,
  ShowToastAction,
  createMemoryCardAction,
  createConflictResolverAction,
  createToastAction,
} from '../types/actions';

// Union type for all action types
type AnyAction =
  | RenderMemoryCardAction
  | RenderSelectionGridAction
  | RenderConflictResolverAction
  | RenderRelationshipGraphAction
  | RenderTimelineAction
  | RenderQuickRepliesAction
  | ShowToastAction;

const db = admin.firestore();

// ═══════════════════════════════════════════════════════════
// CONFIG INTERFACES
// ═══════════════════════════════════════════════════════════

interface OrchestratorConfig {
  master: {
    pipelineEnabled: boolean;
    maintenanceMode: boolean;
    maintenanceMessage: string;
    allowedIINsDuringMaintenance: string[];
    requireAuthentication: boolean;
    maxRequestsPerMinute: number;
    enableRateLimiting: boolean;
  };
  stages: {
    inputAnalysis: boolean;
    classifier: boolean;
    confidenceGate: boolean;
    intentResolution: boolean;
    memoryQuery: boolean;
    memoryExtraction: boolean;
    conflictCheck: boolean;      // Stage 6.5: Conflict Detection
    curiosityModule: boolean;
    trustEvaluation: boolean;
    saveDecision: boolean;
    contextInjection: boolean;
    llmResponse: boolean;
    postResponseLog: boolean;
  };
  execution: {
    executionMode: string;
    stopOnFirstError: boolean;
    skipDisabledStages: boolean;
    requiredStages: string[];
  };
  errorHandling: {
    continueOnStageError: boolean;
    fallbackToBasicResponse: boolean;
    logAllErrors: boolean;
    logToCloudLogging: boolean;
    maxRetries: number;
    retryDelayMs: number;
    criticalStages: string[];
    errorResponseMessage: string;
  };
  performance: {
    timeoutMs: number;
    stageTimeoutMs: number;
    llmTimeoutMs: number;
    enableCaching: boolean;
    cacheTTLSeconds: number;
    maxConcurrentRequests: number;
  };
  debug: {
    enableDebugMode: boolean;
    includeStageDetails: boolean;
    includeTimings: boolean;
    includeMemoryDetails: boolean;
    includeLLMDetails: boolean;
    logRequestPayloads: boolean;
    logResponsePayloads: boolean;
    debugIINs: string[];
  };
  fallback: {
    defaultProvider: string;
    defaultModel: string;
    defaultTemperature: number;
    fallbackProvider: string;
    fallbackModel: string;
    useFallbackOnError: boolean;
    useFallbackOnTimeout: boolean;
    genericErrorResponse: string;
    maintenanceResponse: string;
    rateLimitResponse: string;
  };
  notifications: {
    enableNotifications: boolean;
    notifyOnError: boolean;
    notifyOnSlowResponse: boolean;
    slowResponseThresholdMs: number;
    notifyOnHighErrorRate: boolean;
    highErrorRateThreshold: number;
  };
}

// ═══════════════════════════════════════════════════════════
// CONFIG LOADER
// ═══════════════════════════════════════════════════════════

async function getOrchestratorConfig(): Promise<OrchestratorConfig> {
  const doc = await db.collection('config').doc('pipeline')
    .collection('settings').doc('orchestrator').get();

  if (!doc.exists) {
    console.log('Orchestrator config not found, using defaults');
  }

  const data = doc.data() ?? {};

  return {
    master: {
      pipelineEnabled: data.master?.pipelineEnabled ?? true,
      maintenanceMode: data.master?.maintenanceMode ?? false,
      maintenanceMessage: data.master?.maintenanceMessage ?? 'System is under maintenance.',
      allowedIINsDuringMaintenance: data.master?.allowedIINsDuringMaintenance ?? [],
      requireAuthentication: data.master?.requireAuthentication ?? true,
      maxRequestsPerMinute: data.master?.maxRequestsPerMinute ?? 60,
      enableRateLimiting: data.master?.enableRateLimiting ?? true,
    },
    stages: {
      inputAnalysis: data.stages?.inputAnalysis ?? true,
      classifier: data.stages?.classifier ?? true,
      confidenceGate: data.stages?.confidenceGate ?? true,
      intentResolution: data.stages?.intentResolution ?? true,
      memoryQuery: data.stages?.memoryQuery ?? true,
      memoryExtraction: data.stages?.memoryExtraction ?? true,
      conflictCheck: data.stages?.conflictCheck ?? true,
      curiosityModule: data.stages?.curiosityModule ?? true,
      trustEvaluation: data.stages?.trustEvaluation ?? true,
      saveDecision: data.stages?.saveDecision ?? true,
      contextInjection: data.stages?.contextInjection ?? true,
      llmResponse: data.stages?.llmResponse ?? true,
      postResponseLog: data.stages?.postResponseLog ?? true,
    },
    execution: {
      executionMode: data.execution?.executionMode ?? 'sequential',
      stopOnFirstError: data.execution?.stopOnFirstError ?? false,
      skipDisabledStages: data.execution?.skipDisabledStages ?? true,
      requiredStages: data.execution?.requiredStages ?? ['llmResponse'],
    },
    errorHandling: {
      continueOnStageError: data.errorHandling?.continueOnStageError ?? true,
      fallbackToBasicResponse: data.errorHandling?.fallbackToBasicResponse ?? true,
      logAllErrors: data.errorHandling?.logAllErrors ?? true,
      logToCloudLogging: data.errorHandling?.logToCloudLogging ?? true,
      maxRetries: data.errorHandling?.maxRetries ?? 1,
      retryDelayMs: data.errorHandling?.retryDelayMs ?? 500,
      criticalStages: data.errorHandling?.criticalStages ?? ['llmResponse', 'contextInjection'],
      errorResponseMessage: data.errorHandling?.errorResponseMessage ?? "I'm sorry, something went wrong. Please try again.",
    },
    performance: {
      timeoutMs: data.performance?.timeoutMs ?? 30000,
      stageTimeoutMs: data.performance?.stageTimeoutMs ?? 5000,
      llmTimeoutMs: data.performance?.llmTimeoutMs ?? 20000,
      enableCaching: data.performance?.enableCaching ?? true,
      cacheTTLSeconds: data.performance?.cacheTTLSeconds ?? 300,
      maxConcurrentRequests: data.performance?.maxConcurrentRequests ?? 100,
    },
    debug: {
      enableDebugMode: data.debug?.enableDebugMode ?? false,
      includeStageDetails: data.debug?.includeStageDetails ?? false,
      includeTimings: data.debug?.includeTimings ?? true,
      includeMemoryDetails: data.debug?.includeMemoryDetails ?? false,
      includeLLMDetails: data.debug?.includeLLMDetails ?? false,
      logRequestPayloads: data.debug?.logRequestPayloads ?? false,
      logResponsePayloads: data.debug?.logResponsePayloads ?? false,
      debugIINs: data.debug?.debugIINs ?? [],
    },
    fallback: {
      defaultProvider: data.fallback?.defaultProvider ?? 'gemini',
      defaultModel: data.fallback?.defaultModel ?? 'gemini-1.5-flash',
      defaultTemperature: data.fallback?.defaultTemperature ?? 0.7,
      fallbackProvider: data.fallback?.fallbackProvider ?? 'gemini',
      fallbackModel: data.fallback?.fallbackModel ?? 'gemini-1.5-flash',
      useFallbackOnError: data.fallback?.useFallbackOnError ?? true,
      useFallbackOnTimeout: data.fallback?.useFallbackOnTimeout ?? true,
      genericErrorResponse: data.fallback?.genericErrorResponse ?? "I'm sorry, something went wrong. Please try again.",
      maintenanceResponse: data.fallback?.maintenanceResponse ?? "The system is currently under maintenance. Please try again later.",
      rateLimitResponse: data.fallback?.rateLimitResponse ?? "You're sending messages too quickly. Please wait a moment.",
    },
    notifications: {
      enableNotifications: data.notifications?.enableNotifications ?? false,
      notifyOnError: data.notifications?.notifyOnError ?? true,
      notifyOnSlowResponse: data.notifications?.notifyOnSlowResponse ?? true,
      slowResponseThresholdMs: data.notifications?.slowResponseThresholdMs ?? 10000,
      notifyOnHighErrorRate: data.notifications?.notifyOnHighErrorRate ?? true,
      highErrorRateThreshold: data.notifications?.highErrorRateThreshold ?? 0.10,
    },
  };
}

// ═══════════════════════════════════════════════════════════
// RATE LIMITING
// ═══════════════════════════════════════════════════════════

async function checkRateLimit(iin: string, config: OrchestratorConfig): Promise<{allowed: boolean; remaining: number}> {
  if (!config.master.enableRateLimiting) {
    return { allowed: true, remaining: 999 };
  }

  const now = Date.now();
  const windowStart = now - 60000; // 1 minute window
  const rateLimitRef = db.collection('rateLimit').doc(iin);

  try {
    const doc = await rateLimitRef.get();
    const data = doc.data();

    if (!data) {
      await rateLimitRef.set({ requests: [now], updatedAt: admin.firestore.FieldValue.serverTimestamp() });
      return { allowed: true, remaining: config.master.maxRequestsPerMinute - 1 };
    }

    // Filter requests within window
    const recentRequests = (data.requests || []).filter((ts: number) => ts > windowStart);

    if (recentRequests.length >= config.master.maxRequestsPerMinute) {
      return { allowed: false, remaining: 0 };
    }

    // Add current request
    recentRequests.push(now);
    await rateLimitRef.set({ requests: recentRequests, updatedAt: admin.firestore.FieldValue.serverTimestamp() });

    return { allowed: true, remaining: config.master.maxRequestsPerMinute - recentRequests.length };
  } catch (error) {
    console.warn('Rate limit check failed:', error);
    return { allowed: true, remaining: 999 }; // Allow on error
  }
}

// ═══════════════════════════════════════════════════════════
// INLINE STAGE IMPLEMENTATIONS (Stages 1 & 2)
// ═══════════════════════════════════════════════════════════

function estimateTokenCount(text: string): number {
  return Math.ceil(text.length / 4);
}

function detectLanguage(text: string): { code: string; confidence: number } {
  const lowerText = text.toLowerCase();
  const spanishWords = ['hola', 'como', 'está', 'gracias', 'buenos', 'días', 'qué', 'sí', 'no sé'];
  const spanishCount = spanishWords.filter(w => lowerText.includes(w)).length;
  if (spanishCount >= 2) return { code: 'es', confidence: 0.8 };
  return { code: 'en', confidence: 0.9 };
}

interface InputAnalysisResult {
  tokens: { estimated: number; limit: number; exceeded: boolean };
  preprocessing: { processed: string; originalLength: number };
  language: { detected: string; confidence: number };
  validation: { passed: boolean; errors: string[] };
}

function processInputAnalysis(message: string): InputAnalysisResult {
  const estimatedTokens = estimateTokenCount(message);
  const maxTokens = 2048;
  const tokenLimitExceeded = estimatedTokens > maxTokens;
  const processedText = message.trim().replace(/\s+/g, ' ');
  const language = detectLanguage(processedText);
  const validationErrors: string[] = [];
  if (tokenLimitExceeded) validationErrors.push(`Token limit exceeded: ${estimatedTokens} > ${maxTokens}`);
  if (!processedText) validationErrors.push('Empty input after preprocessing');
  return {
    tokens: { estimated: estimatedTokens, limit: maxTokens, exceeded: tokenLimitExceeded },
    preprocessing: { processed: processedText, originalLength: message.length },
    language: { detected: language.code, confidence: language.confidence },
    validation: { passed: validationErrors.length === 0, errors: validationErrors },
  };
}

interface ClassifierResult {
  detectedIntent: string;
  confidence: number;
  allScores: Record<string, number>;
  matchedKeywords: string[];
  fallbackUsed: boolean;
}

async function processClassifier(message: string): Promise<ClassifierResult> {
  const lowerText = message.toLowerCase();
  const keywords: Record<string, string[]> = {
    code: ['python', 'javascript', 'flutter', 'dart', 'code', 'script', 'debug', 'fix', 'error', 'bug', 'api', 'function'],
    creative: ['poem', 'story', 'song', 'lyrics', 'compose', 'invent', 'imagine', 'design', 'create'],
    factual: ['what is', 'who is', 'when did', 'where is', 'how many', 'how much', 'define', 'meaning'],
    reasoning: ['why', 'explain', 'analyze', 'think', 'compare', 'evaluate', 'reason', 'because'],
    casual: ['hello', 'hi', 'hey', 'thanks', 'ok', 'sure', 'bye'],
  };
  const scores: Record<string, number> = { code: 0, creative: 0, factual: 0, reasoning: 0, casual: 0 };
  const matchedKeywords: string[] = [];
  for (const [intent, kws] of Object.entries(keywords)) {
    const matches = kws.filter(kw => {
      const regex = new RegExp(`\\b${kw.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i');
      return regex.test(lowerText);
    });
    if (matches.length > 0) {
      matchedKeywords.push(...matches.map(m => `${intent}:${m}`));
      scores[intent] = Math.min(0.95, 0.25 * matches.length * 1.5);
    }
  }
  let detectedIntent = 'casual';
  let maxConfidence = 0;
  for (const [intent, score] of Object.entries(scores)) {
    if (score > maxConfidence) { maxConfidence = score; detectedIntent = intent; }
  }
  const fallbackUsed = maxConfidence < 0.6;
  if (fallbackUsed) { detectedIntent = 'casual'; scores.casual = 0.5; }
  return { detectedIntent, confidence: maxConfidence || 0.5, allScores: scores, matchedKeywords, fallbackUsed };
}

// ═══════════════════════════════════════════════════════════
// INTERFACES
// ═══════════════════════════════════════════════════════════

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

interface StageResult {
  stage: string;
  stageNumber: number;
  success: boolean;
  skipped: boolean;
  data: any;
  error?: string;
  timeMs: number;
}

// Memory card interface for Generative UI
interface MemoryCard {
  tempId: string;
  type: string;
  status: 'pending' | 'complete';
  icon: string;
  title: string;
  subtitle: string;
  color: string;
  complete: boolean;
  missingRequired: string[];
  typeConfig: {
    requiredSlots: any[];
    optionalSlots: any[];
  };
  slots: Record<string, { value: any; filled: boolean }>;
}

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

  // Actions Protocol - extensible UI commands
  actions?: AnyAction[];

  // Saved memories with IDs for frontend edit capability
  savedMemories?: {
    memoryId: string;
    type: string;
    content: string;
    slots: Record<string, any>;
  }[];
}

// ═══════════════════════════════════════════════════════════
// STAGE EXECUTOR WITH RETRY
// ═══════════════════════════════════════════════════════════

async function executeStageWithRetry(
  stageName: string,
  stageNumber: number,
  executor: () => Promise<any>,
  config: OrchestratorConfig
): Promise<StageResult> {
  const startTime = Date.now();
  let lastError: any = null;

  for (let attempt = 0; attempt <= config.errorHandling.maxRetries; attempt++) {
    try {
      const timeoutMs = stageName === 'LLM Response'
        ? config.performance.llmTimeoutMs
        : config.performance.stageTimeoutMs;

      const timeoutPromise = new Promise((_, reject) => {
        setTimeout(() => reject(new Error(`Stage timeout after ${timeoutMs}ms`)), timeoutMs);
      });

      const data = await Promise.race([executor(), timeoutPromise]);

      return {
        stage: stageName,
        stageNumber,
        success: true,
        skipped: false,
        data,
        timeMs: Date.now() - startTime,
      };
    } catch (error: any) {
      lastError = error;
      console.error(`Stage ${stageNumber} (${stageName}) attempt ${attempt + 1} error:`, error.message);

      if (attempt < config.errorHandling.maxRetries) {
        await new Promise(resolve => setTimeout(resolve, config.errorHandling.retryDelayMs));
      }
    }
  }

  // All retries failed - log error
  if (config.errorHandling.logAllErrors) {
    try {
      await db.collection('logs').doc('errors').collection('pipeline').add({
        stage: stageName,
        stageNumber,
        error: lastError?.message || 'Unknown error',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.warn('Failed to log error:', e);
    }
  }

  return {
    stage: stageName,
    stageNumber,
    success: false,
    skipped: false,
    data: null,
    error: lastError?.message || 'Unknown error',
    timeMs: Date.now() - startTime,
  };
}

// ═══════════════════════════════════════════════════════════
// ACTIONS BUILDER
// ═══════════════════════════════════════════════════════════

interface MemoryQueryOutput {
  timelineAction?: RenderTimelineAction;
  queryType?: string;
  memories?: any[];
}

interface MemoryExtractionOutput {
  selectionGridAction?: RenderSelectionGridAction;
  relationshipGraphAction?: RenderRelationshipGraphAction;
  extracted?: any[];
  extractionCount?: number;
}

interface CuriosityOutput {
  memoryCards?: MemoryCard[];
  holdForClarification?: boolean;
  memories?: any[];
  action?: string;
}

interface SaveDecisionOutput {
  decision?: string;
  savedCount?: number;
  savedMemories?: Array<{ type: string }>;
  conflicts?: Array<{
    field: string;
    fieldLabel: string;
    icon?: string;
    oldValue: any;
    newValue: any;
    existingMemoryId: string;
  }>;
  conflictResolverAction?: RenderConflictResolverAction;
}

interface ContextInjectionOutput {
  quickRepliesAction?: RenderQuickRepliesAction;
  holdForClarification?: boolean;
  memoryCards?: MemoryCard[];
}

function buildActions(
  memoryQueryResult: MemoryQueryOutput | null,
  memoryExtractionResult: MemoryExtractionOutput | null,
  curiosityResult: CuriosityOutput | null,
  saveResult: SaveDecisionOutput | null,
  contextResult: ContextInjectionOutput | null
): AnyAction[] | undefined {
  const actions: AnyAction[] = [];

  // 1. Timeline action (from Memory Query - Stage 5)
  if (memoryQueryResult?.timelineAction) {
    actions.push(memoryQueryResult.timelineAction);
    console.log('[ORCH] Added timeline action');
  }

  // 2. Selection Grid action (from Memory Extraction - Stage 6)
  if (memoryExtractionResult?.selectionGridAction) {
    actions.push(memoryExtractionResult.selectionGridAction);
    console.log('[ORCH] Added selection grid action');
  }

  // 3. Relationship Graph action (from Memory Extraction - Stage 6)
  if (memoryExtractionResult?.relationshipGraphAction) {
    actions.push(memoryExtractionResult.relationshipGraphAction);
    console.log('[ORCH] Added relationship graph action');
  }

  // 4. Memory card actions (from Curiosity Module - Stage 7)
  if (curiosityResult?.memoryCards && curiosityResult.memoryCards.length > 0) {
    curiosityResult.memoryCards.forEach((card, index) => {
      actions.push(createMemoryCardAction(
        {
          tempId: card.tempId,
          type: card.type,
          status: card.status as 'pending' | 'complete' | 'saving' | 'saved' | 'error',
          icon: card.icon,
          title: card.title,
          subtitle: card.subtitle,
          color: card.color,
          complete: card.complete,
          missingRequired: card.missingRequired,
          typeConfig: card.typeConfig,
          slots: card.slots,
        },
        { priority: index, dismissable: true }
      ));
    });
    console.log(`[ORCH] Added ${curiosityResult.memoryCards.length} memory card actions`);
  }

  // 5. Conflict resolver action (from Save Decision - Stage 9)
  if (saveResult?.conflictResolverAction) {
    actions.push(saveResult.conflictResolverAction);
    console.log('[ORCH] Added conflict resolver action');
  } else if (saveResult?.conflicts && saveResult.conflicts.length > 0) {
    // Fallback: build from conflicts array if action not provided
    saveResult.conflicts.forEach((conflict, index) => {
      actions.push(createConflictResolverAction(
        {
          title: 'Conflict Detected',
          field: conflict.field,
          fieldLabel: conflict.fieldLabel,
          icon: conflict.icon || '⚠️',
          oldValue: conflict.oldValue,
          newValue: conflict.newValue,
          oldMemoryId: conflict.existingMemoryId,
        },
        { priority: 50 + index, requiresResponse: true }
      ));
    });
    console.log(`[ORCH] Added ${saveResult.conflicts.length} conflict resolver actions from array`);
  }

  // 6. Quick replies action (from Context Injection - Stage 10)
  if (contextResult?.quickRepliesAction && !curiosityResult?.holdForClarification) {
    actions.push(contextResult.quickRepliesAction);
    console.log('[ORCH] Added quick replies action');
  }

  // 7. Toast for auto-saved memories
  if (saveResult?.savedCount && saveResult.savedCount > 0 && !curiosityResult?.holdForClarification) {
    const savedTypes = saveResult.savedMemories?.map(m => m.type).join(', ') || 'memory';
    actions.push(createToastAction(
      {
        message: `Saved ${saveResult.savedCount} ${savedTypes}!`,
        type: 'success',
        duration: 3000,
      },
      { priority: 100 }
    ));
    console.log('[ORCH] Added save toast action');
  }

  console.log(`[ORCH] Total actions collected: ${actions.length}`);
  return actions.length > 0 ? actions : undefined;
}

// ═══════════════════════════════════════════════════════════
// MAIN ORCHESTRATOR
// ═══════════════════════════════════════════════════════════

export async function runPipeline(input: PipelineInput, forceDebug: boolean = false): Promise<PipelineResult> {
  const pipelineStartTime = Date.now();
  const stages: StageResult[] = [];

  // Load config
  const config = await getOrchestratorConfig();

  // Check if debug mode for this IIN
  const isDebugIIN = config.debug.debugIINs.includes(input.iin);
  const showDebug = config.debug.enableDebugMode || isDebugIIN || forceDebug;

  // Log request if enabled
  if (config.debug.logRequestPayloads) {
    console.log('REQUEST_PAYLOAD', JSON.stringify({ iin: input.iin, message: input.message }));
  }

  // Initialize result
  const result: PipelineResult = {
    success: false,
    response: '',
    iin: input.iin,
    conversationId: input.conversationId,
    totalTimeMs: 0,
    memoriesUsed: 0,
    memoriesSaved: 0,
    timestamp: new Date().toISOString(),
  };

  // ═══════════════════════════════════════════════════════
  // PRE-FLIGHT CHECKS
  // ═══════════════════════════════════════════════════════

  // Check if pipeline is enabled
  if (!config.master.pipelineEnabled) {
    result.response = config.fallback.genericErrorResponse;
    result.error = 'PIPELINE_DISABLED';
    result.totalTimeMs = Date.now() - pipelineStartTime;
    return result;
  }

  // Check maintenance mode
  if (config.master.maintenanceMode) {
    if (!config.master.allowedIINsDuringMaintenance.includes(input.iin)) {
      result.response = config.fallback.maintenanceResponse;
      result.error = 'MAINTENANCE_MODE';
      result.totalTimeMs = Date.now() - pipelineStartTime;
      return result;
    }
  }

  // Check rate limit
  const rateLimit = await checkRateLimit(input.iin, config);
  if (!rateLimit.allowed) {
    result.response = config.fallback.rateLimitResponse;
    result.error = 'RATE_LIMITED';
    result.totalTimeMs = Date.now() - pipelineStartTime;
    return result;
  }

  try {
    // ═══════════════════════════════════════════════════════
    // STAGE 1: INPUT ANALYSIS
    // ═══════════════════════════════════════════════════════
    if (config.stages.inputAnalysis) {
      const stage1 = await executeStageWithRetry(
        'Input Analysis', 1,
        async () => processInputAnalysis(input.message),
        config
      );
      stages.push(stage1);

      if (!stage1.success && config.execution.stopOnFirstError) {
        throw new Error(`Stage 1 failed: ${stage1.error}`);
      }
    } else {
      stages.push({ stage: 'Input Analysis', stageNumber: 1, success: true, skipped: true, data: null, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 2: CLASSIFIER
    // ═══════════════════════════════════════════════════════
    let classifierResult: ClassifierResult | null = null;
    if (config.stages.classifier) {
      const stage2 = await executeStageWithRetry(
        'Classifier', 2,
        () => processClassifier(input.message),
        config
      );
      stages.push(stage2);
      classifierResult = stage2.data;

      if (!stage2.success && config.execution.stopOnFirstError) {
        throw new Error(`Stage 2 failed: ${stage2.error}`);
      }
    } else {
      stages.push({ stage: 'Classifier', stageNumber: 2, success: true, skipped: true, data: null, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 3: CONFIDENCE GATE
    // ═══════════════════════════════════════════════════════
    let confidenceGateResult: any = null;
    if (config.stages.confidenceGate) {
      const stage3 = await executeStageWithRetry(
        'Confidence Gate', 3,
        () => processConfidenceGate(input.message, input.iin),
        config
      );
      stages.push(stage3);
      confidenceGateResult = stage3.data;

      // Check if message was blocked
      if (stage3.success && confidenceGateResult && !confidenceGateResult.passed && confidenceGateResult.action === 'block') {
        result.response = confidenceGateResult.message || "I couldn't process that message. Could you try rephrasing?";
        result.success = true;
        result.intent = 'blocked';
        if (showDebug) result.stages = stages;
        if (config.debug.includeTimings) {
          result.stageSummary = stages.map(s => ({ name: s.stage, timeMs: s.timeMs, success: s.success }));
        }
        result.totalTimeMs = Date.now() - pipelineStartTime;

        // Still log
        if (config.stages.postResponseLog) {
          await processPostResponseLog({
            iin: input.iin,
            userInput: input.message,
            aiResponse: result.response,
            intent: 'blocked',
            success: true,
            totalTimeMs: result.totalTimeMs,
          });
        }
        return result;
      }

      if (!stage3.success && config.execution.stopOnFirstError) {
        throw new Error(`Stage 3 failed: ${stage3.error}`);
      }
    } else {
      stages.push({ stage: 'Confidence Gate', stageNumber: 3, success: true, skipped: true, data: null, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 4: INTENT RESOLUTION
    // ═══════════════════════════════════════════════════════
    let intentResult: any = null;
    if (config.stages.intentResolution) {
      const stage4 = await executeStageWithRetry(
        'Intent Resolution', 4,
        () => processIntentResolution(input.message),
        config
      );
      stages.push(stage4);
      intentResult = stage4.data;
      result.intent = intentResult?.intent?.primary || classifierResult?.detectedIntent;

      if (!stage4.success && config.execution.stopOnFirstError) {
        throw new Error(`Stage 4 failed: ${stage4.error}`);
      }
    } else {
      stages.push({ stage: 'Intent Resolution', stageNumber: 4, success: true, skipped: true, data: null, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 5: MEMORY QUERY
    // ═══════════════════════════════════════════════════════
    let memoryQueryResult: any = null;
    if (config.stages.memoryQuery) {
      const shouldQueryMemory = intentResult?.actions?.queryMemory ?? true;

      if (shouldQueryMemory) {
        const stage5 = await executeStageWithRetry(
          'Memory Query', 5,
          () => queryMemories({
            iin: input.iin,
            query: input.message,
            message: input.message,  // Pass raw message for temporal detection
            intent: intentResult?.intent?.primary,  // Pass intent for temporal detection
            context: intentResult?.intent?.primary || classifierResult?.detectedIntent,
            includeDeep: false,
          }),
          config
        );
        stages.push(stage5);
        memoryQueryResult = stage5.data;
        result.memoriesUsed = memoryQueryResult?.memories?.length ?? 0;

        if (!stage5.success && config.execution.stopOnFirstError) {
          throw new Error(`Stage 5 failed: ${stage5.error}`);
        }
      } else {
        stages.push({ stage: 'Memory Query', stageNumber: 5, success: true, skipped: true, data: { reason: 'Intent does not require memory query' }, timeMs: 0 });
      }
    } else {
      stages.push({ stage: 'Memory Query', stageNumber: 5, success: true, skipped: true, data: null, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 6: MEMORY EXTRACTION
    // ═══════════════════════════════════════════════════════
    let memoryExtractionResult: any = null;
    if (config.stages.memoryExtraction) {
      const shouldExtractMemory = intentResult?.actions?.extractMemory ?? true;

      if (shouldExtractMemory) {
        const stage6 = await executeStageWithRetry(
          'Memory Extraction', 6,
          () => extractMemories({
            iin: input.iin,
            input: input.message,
            context: intentResult?.intent?.primary || classifierResult?.detectedIntent,
            intent: intentResult?.intent?.primary,  // Pass intent for active mode detection
          }),
          config
        );
        stages.push(stage6);
        memoryExtractionResult = stage6.data;

        if (!stage6.success && config.execution.stopOnFirstError) {
          throw new Error(`Stage 6 failed: ${stage6.error}`);
        }
      } else {
        stages.push({ stage: 'Memory Extraction', stageNumber: 6, success: true, skipped: true, data: { reason: 'Intent does not require memory extraction' }, timeMs: 0 });
      }
    } else {
      stages.push({ stage: 'Memory Extraction', stageNumber: 6, success: true, skipped: true, data: null, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 6.5: CONFLICT CHECK
    // ═══════════════════════════════════════════════════════
    let conflictCheckResult: any = null;
    let extractedMemories = memoryExtractionResult?.extracted ?? memoryExtractionResult?.memories ?? [];

    if (config.stages.conflictCheck && extractedMemories.length > 0) {
      const stage6_5 = await executeStageWithRetry(
        'Conflict Check', 6.5,
        () => checkConflicts({
          iin: input.iin,
          extractedMemories: extractedMemories,
        }),
        config
      );
      stages.push(stage6_5);
      conflictCheckResult = stage6_5.data;

      if (stage6_5.success && conflictCheckResult) {
        // Update extractedMemories to only include clean (non-conflicting) memories
        // Conflicting memories will be handled by Curiosity Module for clarification
        extractedMemories = conflictCheckResult.clean ?? extractedMemories;

        // Log conflict detection results
        if (conflictCheckResult.pendingClarifications?.length > 0) {
          console.log(`[ORCHESTRATOR] ${conflictCheckResult.pendingClarifications.length} conflicts need clarification`);
        }
        if (conflictCheckResult.autoResolved?.length > 0) {
          console.log(`[ORCHESTRATOR] ${conflictCheckResult.autoResolved.length} conflicts auto-resolved`);
        }
      }

      if (!stage6_5.success && config.execution.stopOnFirstError) {
        throw new Error(`Stage 6.5 failed: ${stage6_5.error}`);
      }
    } else {
      stages.push({ stage: 'Conflict Check', stageNumber: 6.5, success: true, skipped: true, data: { reason: extractedMemories.length === 0 ? 'No memories to check' : 'Stage disabled' }, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 7: CURIOSITY MODULE
    // ═══════════════════════════════════════════════════════
    let curiosityResult: any = null;
    // Include pending conflict clarifications in what Curiosity Module processes
    const hasConflicts = (conflictCheckResult?.pendingClarifications?.length ?? 0) > 0;
    const shouldRunCuriosity = extractedMemories.length > 0 || hasConflicts;

    if (config.stages.curiosityModule && shouldRunCuriosity) {
      const stage7 = await executeStageWithRetry(
        'Curiosity Module', 7,
        () => processCuriosityModule({
          iin: input.iin,
          extractedMemories: extractedMemories,
          originalMessage: input.message,
          questionsAskedCount: 0,  // First pass
          userDismissed: false,
          intent: intentResult?.intent?.primary,
          // Pass conflict information for clarification questions
          pendingConflicts: conflictCheckResult?.pendingClarifications ?? [],
        }),
        config
      );
      stages.push(stage7);
      curiosityResult = stage7.data;

      // If curiosity module wants to ask questions, we could handle that here
      // For now, we just proceed with the memories (complete or partial)
      if (curiosityResult?.action === 'reject') {
        // Skip trust/save stages for rejected memories
        stages.push({ stage: 'Trust Evaluation', stageNumber: 8, success: true, skipped: true, data: { reason: 'Memories rejected by curiosity module' }, timeMs: 0 });
        stages.push({ stage: 'Save Decision', stageNumber: 9, success: true, skipped: true, data: { reason: 'Memories rejected by curiosity module' }, timeMs: 0 });
      }

      if (!stage7.success && config.execution.stopOnFirstError) {
        throw new Error(`Stage 7 failed: ${stage7.error}`);
      }
    } else {
      stages.push({ stage: 'Curiosity Module', stageNumber: 7, success: true, skipped: true, data: { reason: 'No memories to check' }, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 8: TRUST EVALUATION
    // ═══════════════════════════════════════════════════════
    let trustResults: any[] = [];
    const memoriesToEvaluate = curiosityResult?.memories ?? extractedMemories;
    if (config.stages.trustEvaluation && memoriesToEvaluate.length > 0 && curiosityResult?.action !== 'reject') {
      const stage8 = await executeStageWithRetry(
        'Trust Evaluation', 8,
        async () => {
          const results = [];
          for (const memory of memoriesToEvaluate) {
            // Pass memory metadata for explicit command boost
            const memoryMetadata = {
              _explicitCommand: memory._explicitCommand,
              _extractionMethod: memory._extractionMethod,
              _originalMessage: memory._originalMessage,
            };

            const trustResult = await processTrustEvaluation(
              memory.content || memory.text || JSON.stringify(memory),
              input.iin,
              'user_stated',
              undefined,  // timestamp
              memoryMetadata
            );
            results.push({ memory, trust: trustResult });
          }
          return results;
        },
        config
      );
      stages.push(stage8);
      trustResults = stage8.data ?? [];

      if (!stage8.success && config.execution.stopOnFirstError) {
        throw new Error(`Stage 8 failed: ${stage8.error}`);
      }
    } else if (curiosityResult?.action !== 'reject') {
      stages.push({ stage: 'Trust Evaluation', stageNumber: 8, success: true, skipped: true, data: { reason: 'No memories to evaluate' }, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 9: SAVE DECISION
    // ═══════════════════════════════════════════════════════
    let savedMemories: any[] = [];
    let saveDecisionResult: any = null;

    // ═══════════════════════════════════════════════════════
    // FALLBACK CHECK: Block save if memories are incomplete
    // This catches edge cases where Stage 7 failed/disabled
    // but memories still have complete: false
    // ═══════════════════════════════════════════════════════
    const memoriesToCheck = curiosityResult?.memories ?? extractedMemories;
    const incompleteMemories = memoriesToCheck.filter((m: any) =>
      m && m.complete === false && Array.isArray(m.missingRequired) && m.missingRequired.length > 0
    );
    const hasIncompleteMemories = incompleteMemories.length > 0;

    if (hasIncompleteMemories && !curiosityResult?.holdForClarification) {
      console.log(`[ORCHESTRATOR] FALLBACK: Found ${incompleteMemories.length} incomplete memories - blocking save`);
      incompleteMemories.forEach((m: any) => {
        console.log(`[ORCHESTRATOR]   - ${m.type}: missing ${m.missingRequired?.join(', ')}`);
      });
    }

    // Check 1: Curiosity module explicitly holding
    // Check 2: FALLBACK - Incomplete memories detected (Stage 7 may have failed/disabled)
    if (curiosityResult?.holdForClarification || hasIncompleteMemories) {
      const reason = curiosityResult?.holdForClarification
        ? 'Waiting for user to complete missing information via memory cards'
        : `FALLBACK: ${incompleteMemories.length} memories have incomplete required slots`;

      console.log(`[ORCHESTRATOR] Stage 9: Holding for clarification - skipping save (${curiosityResult?.holdForClarification ? 'curiosity' : 'fallback'})`);
      const holdResult = {
        decision: 'hold',
        reason,
        saved: false,
        savedCount: 0,
        pendingCards: curiosityResult?.memoryCards ?? incompleteMemories.map((m: any) => ({
          tempId: m.tempId || `fallback_${Date.now()}`,
          type: m.type,
          status: 'pending',
          icon: m.typeConfig?.icon || '📝',
          title: m.content?.substring(0, 30) || m.type,
          subtitle: `Missing: ${m.missingRequired?.join(', ')}`,
          color: m.typeConfig?.color || '#607D8B',
          complete: false,
          missingRequired: m.missingRequired || [],
          typeConfig: m.typeConfig || { requiredSlots: [], optionalSlots: [] },
          slots: m.slots || {},
        })),
        memories: curiosityResult?.memories ?? incompleteMemories,
        _fallbackTriggered: !curiosityResult?.holdForClarification,
      };
      stages.push({
        stage: 'Save Decision',
        stageNumber: 9,
        success: true,
        skipped: false,
        data: holdResult,
        timeMs: 0,
      });
      saveDecisionResult = holdResult;
      result.memoriesSaved = 0;
    } else if (config.stages.saveDecision && trustResults.length > 0 && curiosityResult?.action !== 'reject') {
      const stage9 = await executeStageWithRetry(
        'Save Decision', 9,
        async () => {
          const results = [];
          for (const item of trustResults) {
            const content = item.memory.content || item.memory.text || JSON.stringify(item.memory);
            const trustScore = item.trust?.trustScore ?? 0.5;

            // Boost confidence when trust has accepted (0.6 → 0.9 to meet autoSaveThreshold)
            const boostedConfidence = item.trust?.action === 'accept'
              ? Math.max(trustScore, 0.9)
              : trustScore;

            // Only process if trust is acceptable
            if (item.trust?.action === 'accept' || item.trust?.action === 'flag' || trustScore >= 0.3) {
              // Check if this is from active mode (explicit command)
              const isExplicitCommand = item.memory._explicitCommand === true;
              const isMandatory = memoryExtractionResult?.mandatory === true || isExplicitCommand;

              const saveResult = await makeSaveDecision({
                iin: input.iin,
                content: content,
                type: item.memory.type || item.memory.category || 'fact',
                confidence: boostedConfidence,
                mandatory: isMandatory,
                _explicitCommand: isExplicitCommand,
                curiosityResult: curiosityResult,  // Pass curiosity result
              });

              console.log(`Save Decision for "${content.substring(0, 30)}...": decision=${saveResult.decision}, boostedConf=${boostedConfidence}`);

              // Accept save, update, reactivate, keep_both, and ask_user (when trust accepted)
              if (saveResult.decision === 'save' || saveResult.decision === 'update' ||
                  saveResult.decision === 'reactivate' || saveResult.decision === 'keep_both' ||
                  (saveResult.decision === 'ask_user' && item.trust?.action === 'accept')) {
                results.push({ ...saveResult, memory: item.memory, _trustApproved: true });
              } else {
                // Include for debugging but mark as not saved
                results.push({ ...saveResult, _notSaved: true, _reason: `decision=${saveResult.decision}` });
              }
            } else {
              results.push({ _notSaved: true, _reason: `trust rejected: score=${trustScore}, action=${item.trust?.action}` });
            }
          }
          return results;
        },
        config
      );
      stages.push(stage9);
      savedMemories = (stage9.data ?? []).filter((r: any) => !r._notSaved);

      // ═══════════════════════════════════════════════════════
      // ACTUALLY SAVE TO FIRESTORE (the missing piece!)
      // ═══════════════════════════════════════════════════════
      const actualSavedMemories: { memoryId: string; type: string; content: string; slots: Record<string, any> }[] = [];

      if (savedMemories.length > 0) {
        console.log(`[ORCHESTRATOR] Writing ${savedMemories.length} memories to Firestore...`);

        const batch = db.batch();
        const itemsRef = db.collection('memories').doc(input.iin).collection('items');

        for (const item of savedMemories) {
          if (item.decision === 'save' && item.memory) {
            const docRef = itemsRef.doc();
            const memoryDoc = {
              id: docRef.id,
              iin: input.iin,
              content: item.memory.content || '',
              type: item.memory.type || 'fact',
              slots: item.memory.slots || {},
              status: 'active',
              tier: item.memory.tier || 'working',
              context: item.memory.context || 'personal',
              confidence: item.memory.confidence || 0.9,
              source: 'pipeline_auto',
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };
            batch.set(docRef, memoryDoc);

            actualSavedMemories.push({
              memoryId: docRef.id,
              type: item.memory.type || 'fact',
              content: item.memory.content || '',
              slots: item.memory.slots || {},
            });

            console.log(`[ORCHESTRATOR] Queued save: ${docRef.id} (${item.memory.type})`);
          }
        }

        if (actualSavedMemories.length > 0) {
          await batch.commit();
          console.log(`[ORCHESTRATOR] ✅ Committed ${actualSavedMemories.length} memories to Firestore`);
        }
      }

      result.memoriesSaved = actualSavedMemories.length;
      result.savedMemories = actualSavedMemories;

      // Build saveDecisionResult for context injection
      if (actualSavedMemories.length > 0) {
        saveDecisionResult = {
          decision: 'save',
          saved: true,
          savedCount: actualSavedMemories.length,
          savedMemories: actualSavedMemories.map(m => ({ type: m.type })),
        };
      }

      if (!stage9.success && config.execution.stopOnFirstError) {
        throw new Error(`Stage 9 failed: ${stage9.error}`);
      }
    } else if (curiosityResult?.action !== 'reject') {
      stages.push({ stage: 'Save Decision', stageNumber: 9, success: true, skipped: true, data: { reason: 'No memories to save' }, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 10: CONTEXT INJECTION
    // ═══════════════════════════════════════════════════════
    let contextResult: any = null;
    if (config.stages.contextInjection) {
      // Build save results from Stage 9 for memory_instruction feedback (legacy format)
      const stage9Results = stages.find(s => s.stageNumber === 9)?.data ?? [];
      const saveResultsForContext = Array.isArray(stage9Results)
        ? stage9Results.map((r: any) => ({
            saved: r.saved === true || (r.decision === 'save' && !r._notSaved),
            content: r.memory?.content || r.content || '',
            reason: r.reason || r._reason || '',
            decision: r.decision,
          }))
        : [];

      // TEMPORARY DIAGNOSTIC LOG — STAGE 4 → STAGE 10 HANDOFF
      console.log('[ORCH DIAG] intentResult:', JSON.stringify(intentResult?.intent));
      console.log('[ORCH DIAG] intentResult?.intent?.primary:', intentResult?.intent?.primary);
      console.log('[ORCH DIAG] typeof intentResult?.intent?.primary:', typeof intentResult?.intent?.primary);
      console.log('[ORCH DIAG] saveDecisionResult:', JSON.stringify(saveDecisionResult));

      // Convert conversationHistory to ChatMessage format for 4-layer context
      const sessionMessages = input.conversationHistory?.map(msg => ({
        role: msg.role as 'user' | 'assistant',
        content: msg.content,
      })) || [];

      const stage10 = await executeStageWithRetry(
        'Context Injection', 10,
        () => buildContextPrompt({
          iin: input.iin,
          message: input.message,
          memories: memoryQueryResult?.memories ?? [],
          intent: intentResult?.intent?.primary,
          saveResults: saveResultsForContext,
          saveDecision: saveDecisionResult,  // NEW: Pass save decision with hold/pendingCards
          // NEW: 4-Layer context inputs
          sessionId: input.sessionId,
          sessionMessages: sessionMessages,
          userName: input.userProfile?.name,
        }),
        config
      );
      stages.push(stage10);
      contextResult = stage10.data;

      if (!stage10.success) {
        if (config.execution.stopOnFirstError || config.errorHandling.criticalStages.includes('contextInjection')) {
          throw new Error(`Stage 10 (critical) failed: ${stage10.error}`);
        }
      }
    } else {
      stages.push({ stage: 'Context Injection', stageNumber: 10, success: true, skipped: true, data: null, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 11: LLM RESPONSE
    // ═══════════════════════════════════════════════════════
    let llmResult: any = null;
    if (config.stages.llmResponse) {
      const stage11 = await executeStageWithRetry(
        'LLM Response', 11,
        () => generateLLMResponse({
          iin: input.iin,
          message: input.message,
          prompt: contextResult?.prompt?.full,
        }),
        config
      );
      stages.push(stage11);
      llmResult = stage11.data;
      result.response = llmResult?.response ?? '';
      result.provider = llmResult?.provider || input.provider || config.fallback.defaultProvider;

      // If LLM failed, try fallback
      if (!stage11.success && config.fallback.useFallbackOnError) {
        console.log('Primary LLM failed, trying fallback...');
        const fallbackStage = await executeStageWithRetry(
          'LLM Response (Fallback)', 11,
          () => generateLLMResponse({
            iin: input.iin,
            message: input.message,
            prompt: contextResult?.prompt?.full,
          }),
          config
        );

        if (fallbackStage.success) {
          llmResult = fallbackStage.data;
          result.response = llmResult?.response ?? '';
          result.provider = config.fallback.fallbackProvider;
          stages.push({ ...fallbackStage, stage: 'LLM Response (Fallback)' });
        }
      }

      // If still no response, use generic error
      if (!result.response && config.errorHandling.fallbackToBasicResponse) {
        result.response = config.errorHandling.errorResponseMessage;
      }
    } else {
      result.response = config.errorHandling.errorResponseMessage;
      stages.push({ stage: 'LLM Response', stageNumber: 11, success: false, skipped: true, data: null, error: 'LLM stage disabled', timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // STAGE 12: POST-RESPONSE LOG
    // ═══════════════════════════════════════════════════════
    if (config.stages.postResponseLog) {
      const stageTimings = stages.reduce((acc, s) => ({ ...acc, [s.stage]: s.timeMs }), {});

      const stage12 = await executeStageWithRetry(
        'Post-Response Log', 12,
        () => processPostResponseLog({
          iin: input.iin,
          conversationId: input.conversationId,
          sessionId: input.sessionId,
          userInput: input.message,
          aiResponse: result.response,
          intent: result.intent,
          entities: intentResult?.entities,
          memoriesUsed: result.memoriesUsed,
          memoriesSaved: result.memoriesSaved,
          memoriesQueried: showDebug ? memoryQueryResult?.memories : undefined,
          memoriesExtracted: showDebug ? memoryExtractionResult?.memories : undefined,
          trustScores: trustResults.map(t => t.trust?.trustScore),
          provider: result.provider,
          model: llmResult?.model,
          inputTokens: llmResult?.inputTokens,
          outputTokens: llmResult?.outputTokens,
          totalTimeMs: Date.now() - pipelineStartTime,
          stageTimings,
          success: true,
        }),
        config
      );
      stages.push(stage12);
    } else {
      stages.push({ stage: 'Post-Response Log', stageNumber: 12, success: true, skipped: true, data: null, timeMs: 0 });
    }

    // ═══════════════════════════════════════════════════════
    // BUILD RESULT
    // ═══════════════════════════════════════════════════════

    result.success = true;
    result.totalTimeMs = Date.now() - pipelineStartTime;

    // Build actions from all pipeline stages
    const actions = buildActions(
      memoryQueryResult,      // Stage 5: timeline
      memoryExtractionResult, // Stage 6: selection grid, relationship graph
      curiosityResult,        // Stage 7: memory cards
      saveDecisionResult,     // Stage 9: conflict resolver
      contextResult           // Stage 10: quick replies
    );
    if (actions && actions.length > 0) {
      result.actions = actions;
      console.log(`[ORCHESTRATOR] Returning ${actions.length} actions for UI`);
    }

    // Include debug info based on settings
    if (showDebug && config.debug.includeStageDetails) {
      result.stages = stages;
    }

    if (config.debug.includeTimings || showDebug) {
      result.stageSummary = stages.map(s => ({
        name: s.stage,
        timeMs: s.timeMs,
        success: s.success,
      }));
    }

    if (showDebug) {
      result.debug = {
        configSource: 'config/pipeline/settings/orchestrator',
        stagesEnabled: Object.entries(config.stages).filter(([_, v]) => v).map(([k]) => k).length,
        executionMode: config.execution.executionMode,
        provider: result.provider,
        memoriesFound: memoryQueryResult?.memories?.length ?? 0,
        memoriesExtracted: extractedMemories.length,
        trustEvaluated: trustResults.length,
        stageDetails: stages,
      };
    }

    // Check for slow response notification
    if (config.notifications.enableNotifications &&
        config.notifications.notifyOnSlowResponse &&
        result.totalTimeMs > config.notifications.slowResponseThresholdMs) {
      console.warn('SLOW_RESPONSE_ALERT', JSON.stringify({
        iin: input.iin,
        totalTimeMs: result.totalTimeMs,
        threshold: config.notifications.slowResponseThresholdMs,
      }));
    }

    // Log response if enabled
    if (config.debug.logResponsePayloads) {
      console.log('RESPONSE_PAYLOAD', JSON.stringify(result));
    }

  } catch (error: any) {
    console.error('Pipeline error:', error);
    result.error = error.message;
    result.totalTimeMs = Date.now() - pipelineStartTime;

    if (showDebug) {
      result.stages = stages;
    }

    if (config.errorHandling.fallbackToBasicResponse) {
      result.response = config.errorHandling.errorResponseMessage;
      result.success = true; // Still return success with fallback response
    }

    // Notify on error
    if (config.notifications.enableNotifications && config.notifications.notifyOnError) {
      console.error('PIPELINE_ERROR_ALERT', JSON.stringify({
        iin: input.iin,
        error: error.message,
        totalTimeMs: result.totalTimeMs,
      }));
    }
  }

  return result;
}

// ═══════════════════════════════════════════════════════════
// HTTP ENDPOINTS
// ═══════════════════════════════════════════════════════════

// Main chat endpoint (production)
export const pipelineChat = onRequest(
  { memory: '1GiB', timeoutSeconds: 60 },
  async (req: Request, res: Response) => {
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    try {
      const {
        iin,
        message,
        conversationId,
        sessionId,
        conversationHistory,
        userProfile,
        provider,
        model,
      } = req.body;

      if (!iin) {
        res.status(400).json({ error: 'IIN is required' });
        return;
      }

      if (!message) {
        res.status(400).json({ error: 'Message is required' });
        return;
      }

      console.log(`Pipeline Chat: iin=${iin}, message="${message.substring(0, 50)}..."`);

      const result = await runPipeline({
        iin,
        message,
        conversationId,
        sessionId,
        conversationHistory,
        userProfile,
        provider,
        model,
      }, false);

      res.status(200).json(result);

    } catch (error: any) {
      console.error('Pipeline chat error:', error);
      res.status(500).json({
        success: false,
        error: error.message ?? 'Internal server error',
        response: "I'm sorry, something went wrong. Please try again.",
      });
    }
  }
);

// Debug endpoint - always returns full details
export const pipelineChatDebug = onRequest(
  { memory: '1GiB', timeoutSeconds: 60 },
  async (req: Request, res: Response) => {
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    try {
      const { iin, message, conversationId, provider, model } = req.body;

      if (!iin || !message) {
        res.status(400).json({ error: 'IIN and message are required' });
        return;
      }

      console.log(`Pipeline Chat Debug: iin=${iin}, message="${message.substring(0, 50)}..."`);

      // Force debug mode for this endpoint
      const result = await runPipeline({
        iin,
        message,
        conversationId,
        provider,
        model,
      }, true);

      res.status(200).json({
        ...result,
        debug: {
          ...result.debug,
          endpoint: 'pipelineChatDebug',
          forceDebug: true,
        },
      });

    } catch (error: any) {
      console.error('Pipeline chat debug error:', error);
      res.status(500).json({ error: error.message });
    }
  }
);
