import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { queryMemories } from './memoryQuery';
import {
  RenderQuickRepliesAction,
  QuickReply,
  createQuickRepliesAction,
} from '../types/actions';
import { getRecentSummaries, formatSummariesForContext } from './compression';

const db = admin.firestore();
const secretManager = new SecretManagerServiceClient();

// Secret cache
const secretCache: Record<string, string> = {};

async function getSecret(name: string): Promise<string> {
  if (secretCache[name]) return secretCache[name];
  const projectId = process.env.GCLOUD_PROJECT || 'app-iamoneai-c36ec';
  const [version] = await secretManager.accessSecretVersion({
    name: `projects/${projectId}/secrets/${name}/versions/latest`,
  });
  const payload = version.payload?.data?.toString() || '';
  secretCache[name] = payload;
  return payload;
}

// ═══════════════════════════════════════════════════════════
// CONFIG LOADER
// ═══════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════
// 4-LAYER CONTEXT TYPES
// ═══════════════════════════════════════════════════════════

interface LayerConfig {
  immediate: {
    enabled: boolean;
    maxMessages: number;
    tokenBudget: number;
    format: 'conversation' | 'summary' | 'json';
  };
  sessionSummary: {
    enabled: boolean;
    threshold: number;
    summarizeCount: number;
    tokenBudget: number;
    cacheEnabled: boolean;
    cacheTTLMinutes: number;
  };
  profile: {
    enabled: boolean;
    maxMemories: number;
    tokenBudget: number;
    queryMethod: 'semantic' | 'keyword' | 'hybrid';
    includeTypes: string[];
    excludeTypes: string[];
  };
  calendar: {
    enabled: boolean;
    lookaheadHours: number;
    tokenBudget: number;
    maxEvents: number;
    format: 'list' | 'prose' | 'json';
  };
  // NEW: Past conversations from nightly compression
  pastConversations: {
    enabled: boolean;
    maxDays: number;
    tokenBudget: number;
  };
}

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
  timestamp?: any;
}

interface CalendarEvent {
  id: string;
  title: string;
  date: Date;
  time?: string;
  description?: string;
}

interface LayerResult {
  name: string;
  content: string;
  tokenCount: number;
  itemCount: number;
  trimmed: boolean;
}

interface ContextInjectionConfig {
  injection: {
    enabled: boolean;
    maxMemories: number;
    minRelevance: number;
    sortBy: string;
  };
  filter: {
    includeFacts: boolean;
    includePreferences: boolean;
    includeRelationships: boolean;
    includeEvents: boolean;
    includeGoals: boolean;
    includeTodos: boolean;
    includeNotes: boolean;
    includeWorkingTier: boolean;
    includeLongtermTier: boolean;
    includeDeepTier: boolean;
  };
  format: {
    memoryFormat: string;
    groupByType: boolean;
    includeMetadata: boolean;
    separator: string;
  };
  prompts: {
    systemPrompt: string;
    memoryHeader: string;
    memoryItemFormat: string;
    noMemoriesText: string;
    userMessageFormat: string;
  };
  tokens: {
    maxMemoryTokens: number;
    reserveResponseTokens: number;
    truncationStrategy: string;
    maxTotalContextTokens?: number;
  };
  // NEW: 4-Layer config
  layers?: LayerConfig;
  promptStructure?: {
    systemPromptTemplate: string;
    sectionHeaders: Record<string, string>;
    sectionOrder: string[];
  };
  summaryLLM?: {
    provider: string;
    model: string;
    temperature: number;
    maxTokens: number;
    prompt: string;
  };
  debug?: {
    logLayerTokens: boolean;
    logAssembly: boolean;
    logTrimming: boolean;
  };
}

async function getContextInjectionConfig(): Promise<ContextInjectionConfig> {
  const doc = await db.collection('config').doc('pipeline')
    .collection('stages').doc('context_injection').get();

  if (!doc.exists) {
    console.log('Context Injection config not found, using defaults');
  }

  const data = doc.data() ?? {};

  const defaultSystemPrompt = `You are IAMONEAI, a personal AI guardian. You remember the user and use their memories to provide personalized, helpful responses. Be friendly, context-aware, and reference what you know about the user when relevant.`;

  return {
    injection: {
      enabled: data.injection?.enabled ?? true,
      maxMemories: data.injection?.maxMemories ?? 10,
      minRelevance: data.injection?.minRelevance ?? 0.30,
      sortBy: data.injection?.sortBy ?? 'relevance',
    },
    filter: {
      includeFacts: data.filter?.includeFacts ?? true,
      includePreferences: data.filter?.includePreferences ?? true,
      includeRelationships: data.filter?.includeRelationships ?? true,
      includeEvents: data.filter?.includeEvents ?? true,
      includeGoals: data.filter?.includeGoals ?? true,
      includeTodos: data.filter?.includeTodos ?? true,
      includeNotes: data.filter?.includeNotes ?? false,
      includeWorkingTier: data.filter?.includeWorkingTier ?? true,
      includeLongtermTier: data.filter?.includeLongtermTier ?? true,
      includeDeepTier: data.filter?.includeDeepTier ?? false,
    },
    format: {
      memoryFormat: data.format?.memoryFormat ?? 'bullet',
      groupByType: data.format?.groupByType ?? false,
      includeMetadata: data.format?.includeMetadata ?? false,
      separator: data.format?.separator ?? 'newline',
    },
    prompts: {
      systemPrompt: data.prompts?.systemPrompt ?? defaultSystemPrompt,
      memoryHeader: data.prompts?.memoryHeader ?? 'Here is what you know about the user:',
      memoryItemFormat: data.prompts?.memoryItemFormat ?? '- {{content}}',
      noMemoriesText: data.prompts?.noMemoriesText ?? "You don't have any memories about this user yet.",
      userMessageFormat: data.prompts?.userMessageFormat ?? 'User: {{message}}',
    },
    tokens: {
      maxMemoryTokens: data.tokens?.maxMemoryTokens ?? 2000,
      reserveResponseTokens: data.tokens?.reserveResponseTokens ?? 1000,
      truncationStrategy: data.tokens?.truncationStrategy ?? 'most_relevant',
      maxTotalContextTokens: data.tokens?.maxTotalContextTokens ?? 1500,
    },
    // NEW: 4-Layer config with defaults
    layers: {
      immediate: {
        enabled: data.layers?.immediate?.enabled ?? true,
        maxMessages: data.layers?.immediate?.maxMessages ?? 10,
        tokenBudget: data.layers?.immediate?.tokenBudget ?? 400,
        format: data.layers?.immediate?.format ?? 'conversation',
      },
      sessionSummary: {
        enabled: data.layers?.sessionSummary?.enabled ?? true,
        threshold: data.layers?.sessionSummary?.threshold ?? 20,
        summarizeCount: data.layers?.sessionSummary?.summarizeCount ?? 15,
        tokenBudget: data.layers?.sessionSummary?.tokenBudget ?? 200,
        cacheEnabled: data.layers?.sessionSummary?.cacheEnabled ?? true,
        cacheTTLMinutes: data.layers?.sessionSummary?.cacheTTLMinutes ?? 30,
      },
      profile: {
        enabled: data.layers?.profile?.enabled ?? true,
        maxMemories: data.layers?.profile?.maxMemories ?? 10,
        tokenBudget: data.layers?.profile?.tokenBudget ?? 300,
        queryMethod: data.layers?.profile?.queryMethod ?? 'semantic',
        includeTypes: data.layers?.profile?.includeTypes ?? ['fact', 'preference', 'relationship', 'goal'],
        excludeTypes: data.layers?.profile?.excludeTypes ?? ['note', 'event'],
      },
      calendar: {
        enabled: data.layers?.calendar?.enabled ?? true,
        lookaheadHours: data.layers?.calendar?.lookaheadHours ?? 48,
        tokenBudget: data.layers?.calendar?.tokenBudget ?? 100,
        maxEvents: data.layers?.calendar?.maxEvents ?? 10,
        format: data.layers?.calendar?.format ?? 'list',
      },
      // NEW: Past conversations from nightly compression
      pastConversations: {
        enabled: data.layers?.pastConversations?.enabled ?? true,
        maxDays: data.layers?.pastConversations?.maxDays ?? 7,
        tokenBudget: data.layers?.pastConversations?.tokenBudget ?? 200,
      },
    },
    promptStructure: {
      systemPromptTemplate: data.promptStructure?.systemPromptTemplate ?? defaultSystemPrompt,
      sectionHeaders: data.promptStructure?.sectionHeaders ?? {
        profile: 'USER PROFILE:',
        calendar: 'UPCOMING EVENTS:',
        pastConversations: 'PAST CONVERSATIONS:',
        sessionSummary: 'SESSION CONTEXT:',
        immediate: 'RECENT CONVERSATION:',
      },
      sectionOrder: data.promptStructure?.sectionOrder ?? ['profile', 'calendar', 'pastConversations', 'sessionSummary', 'immediate'],
    },
    summaryLLM: {
      provider: data.summaryLLM?.provider ?? 'gemini',
      model: data.summaryLLM?.model ?? 'gemini-2.0-flash-exp',
      temperature: data.summaryLLM?.temperature ?? 0.3,
      maxTokens: data.summaryLLM?.maxTokens ?? 200,
      prompt: data.summaryLLM?.prompt ?? `Summarize the following conversation in 2-3 sentences, focusing on key topics discussed, decisions made, and important facts mentioned.

Conversation:
{{messages}}

Summary:`,
    },
    debug: {
      logLayerTokens: data.debug?.logLayerTokens ?? true,
      logAssembly: data.debug?.logAssembly ?? true,
      logTrimming: data.debug?.logTrimming ?? true,
    },
  };
}

// ═══════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════

interface Memory {
  id: string;
  content: string;
  type: string;
  context: string;
  relevance: number;
  tier: string;
  created_at?: any;
  [key: string]: any;
}

// ═══════════════════════════════════════════════════════════
// MEMORY CARD INTERFACE (for Generative UI)
// ═══════════════════════════════════════════════════════════

interface SlotConfig {
  id: string;
  label: string;
  icon: string;
  inputType: string;
  placeholder?: string;
  questionTemplate?: string;
  options?: string[];
}

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
    requiredSlots: SlotConfig[];
    optionalSlots: SlotConfig[];
  };
  slots: Record<string, { value: any; filled: boolean }>;
}

// Save result from Stage 8 (Save Decision) - legacy format
interface SaveResult {
  saved: boolean;
  content: string;
  reason: string;
  decision?: string;
  pendingCards?: MemoryCard[];  // Memory cards when decision='hold'
}

// Save decision from upstream stage (new format)
interface SaveDecision {
  saved: boolean;
  savedCount?: number;
  mandatory?: boolean;
  reason?: string;
  decision?: 'save' | 'skip' | 'update' | 'ask_user' | 'keep_both' | 'reactivate' | 'hold';
  pendingCards?: MemoryCard[];  // Memory cards when decision='hold'
}

// Intent object format (when upstream passes structured intent)
interface IntentObject {
  primary: string;
  confidence?: number;
  [key: string]: any;
}

interface ContextInjectionInput {
  iin: string;
  message: string;
  memories?: Memory[];
  intent?: string | IntentObject; // From Stage 4: string OR object with primary field
  saveResults?: SaveResult[];     // From Stage 8: results of save decisions (legacy)
  saveDecision?: SaveDecision;    // From upstream: single save decision (preferred)
  // NEW: 4-Layer context inputs
  sessionId?: string;             // Current chat session ID
  sessionMessages?: ChatMessage[]; // Current session messages (if available)
  userName?: string;              // User's name for personalization
}

// ═══════════════════════════════════════════════════════════
// FIX 4: CONTEXT MODE TYPE
// Determines what the LLM is allowed to reference/confirm.
// ═══════════════════════════════════════════════════════════

type ContextMode =
  | 'identity_only'
  | 'neutral_ack'
  | 'memory_confirm_allowed'
  | 'memory_use_allowed';

// ═══════════════════════════════════════════════════════════
// FIX 4: CONTEXT MODE GUARD BUILDER
// Generates system-level instructions based on context mode.
// ═══════════════════════════════════════════════════════════

function buildContextModeGuard(mode: ContextMode): string {
  switch (mode) {
    case 'identity_only':
      return `
[CONTEXT MODE: IDENTITY ONLY]
You may acknowledge the user by name.
You MUST NOT reference personal facts, preferences, reminders, work, family, or past events.
You MUST NOT imply memory updates or long-term recall.
`.trim();

    case 'neutral_ack':
      return `
[CONTEXT MODE: NEUTRAL ACKNOWLEDGEMENT]
You may acknowledge the statement conversationally.
You MUST NOT say you will remember, store, save, or recall this information later.
You MUST NOT reference unrelated personal memories.
Do not imply persistence.
`.trim();

    case 'memory_confirm_allowed':
      return `
[CONTEXT MODE: MEMORY CONFIRMATION ALLOWED]
You may confirm that the information was saved, but ONLY if explicitly instructed below.
Do not restate unrelated memories.
`.trim();

    case 'memory_use_allowed':
      return `
[CONTEXT MODE: MEMORY USE ALLOWED]
You have access to memories about the user listed below.
You MUST actively use these memories to provide personalized, relevant responses.
When answering questions or making suggestions, reference what you know about the user.
If a memory is directly relevant to the user's question, incorporate it naturally into your response.
Do not just acknowledge - use the information to be helpful.
`.trim();
  }
}

// ═══════════════════════════════════════════════════════════
// FIX 1 - RULE 4: ANTI-HALLUCINATION GUARD (DYNAMIC)
// Appended to every system prompt to prevent the LLM from
// inventing past conversations or memories.
// This is the ONLY source of truth enforcement in Stage 9.
// ═══════════════════════════════════════════════════════════

const ANTI_HALLUCINATION_GUARD = `

You may ONLY reference memories explicitly provided in this prompt.
You MUST NOT invent past conversations, saved memories, or confirmations.
If no memory save instruction is present, assume nothing was saved.`;

// ═══════════════════════════════════════════════════════════
// FIX 2: MEMORY TYPE CLASSIFICATIONS
// Used for intent-based memory filtering to prevent over-sharing.
// These classifications are READ-ONLY from upstream - no decisions here.
// ═══════════════════════════════════════════════════════════

// Personal memories: filtered out for greetings/smalltalk
const PERSONAL_MEMORY_TYPES = ['event', 'appointment', 'preference', 'work', 'todo', 'goal', 'relationship'];

// ═══════════════════════════════════════════════════════════
// FIX 2: INTENT-BASED MEMORY FILTER
// Prevents irrelevant or excessive memory injection.
// This function READS intent from upstream - it does NOT decide intent.
// Fail safe = inject fewer memories.
// ═══════════════════════════════════════════════════════════

/**
 * FIX 2: Filters memories based on the detected intent from upstream.
 *
 * Rules:
 * - greeting / smalltalk → Inject identity-only memories (name)
 * - memory_instruction   → Inject full relevant memory context
 * - general / statement  → Inject high-relevance identity + related domain only
 *
 * Hard Rules:
 * - Do NOT decide intent here (read only)
 * - Do NOT infer relevance
 * - Do NOT alter memory content
 * - Fail safe = inject fewer memories
 *
 * @param intent - The classified intent from upstream Stage 4 (READ ONLY)
 * @param memories - Array of retrieved memories
 * @returns Filtered array of memories appropriate for the intent
 */
function filterMemoriesByIntent(memories: Memory[], intent: string | undefined): Memory[] {
  // SAFE FALLBACK: If no memories provided, return empty array
  if (!memories || memories.length === 0) {
    return [];
  }

  // SAFE FALLBACK: If no intent provided, be conservative - only identity
  // Fail safe = inject fewer memories
  if (!intent) {
    console.log('[Context Injection] FIX 2: No intent provided, defaulting to identity-only filter');
    return memories.filter(m =>
      m.type?.toLowerCase() === 'name' ||
      m.context?.toLowerCase() === 'identity'
    );
  }

  const intentLower = intent.toLowerCase();

  // FIX 2 Rule: greeting / smalltalk → Inject identity-only memories (name)
  // Prevents: "hello" → full life history
  if (intentLower === 'greeting' || intentLower === 'smalltalk') {
    console.log(`[Context Injection] FIX 2: ${intentLower} intent - filtering to identity-only memories`);
    return memories.filter(m => {
      const memType = m.type?.toLowerCase();
      const memContext = m.context?.toLowerCase();
      // Include only name/identity memories
      const isIdentity = memType === 'name' || memContext === 'identity';
      // Explicitly exclude personal memories
      const isPersonal = PERSONAL_MEMORY_TYPES.includes(memType);
      return isIdentity && !isPersonal;
    });
  }

  // FIX 2 Rule: memory_instruction → Inject full relevant memory context
  if (intentLower === 'memory_instruction') {
    console.log('[Context Injection] FIX 2: memory_instruction intent - injecting all relevant memories');
    return memories; // Full context allowed
  }

  // FIX 5: question / memory_recall / recommendation / advice → Inject all relevant memories
  // User is asking for personalized response, so we should use their memories
  if (
    intentLower === 'question' ||
    intentLower === 'memory_recall' ||
    intentLower === 'memory_recall_temporal' ||
    intentLower === 'recommendation' ||
    intentLower === 'advice'
  ) {
    console.log(`[Context Injection] FIX 5: ${intentLower} intent - injecting all relevant memories for personalization`);
    return memories; // Full context allowed for personalized responses
  }

  // FIX 2 Rule: general / statement / other → Inject high-relevance identity + related domain only
  // Prevents: "I have a red car" → unrelated reminders about sushi, work, sister
  console.log(`[Context Injection] FIX 2: ${intent} intent - filtering to high-relevance identity memories`);
  return memories.filter(m => {
    const memType = m.type?.toLowerCase();
    const memContext = m.context?.toLowerCase();
    // Include only identity/name memories
    const isIdentity = memType === 'name' || memContext === 'identity';
    // Also include very high relevance facts (0.8+) that are likely related
    const isHighRelevanceFact = memType === 'fact' && m.relevance >= 0.8;
    return isIdentity || isHighRelevanceFact;
  });
}

// ═══════════════════════════════════════════════════════════
// 4-LAYER CONTEXT ASSEMBLY FUNCTIONS
// ═══════════════════════════════════════════════════════════

/**
 * LAYER 1 - IMMEDIATE: Get last N messages from current chat session
 */
async function buildLayer1Immediate(
  iin: string,
  sessionId: string | undefined,
  sessionMessages: ChatMessage[] | undefined,
  config: LayerConfig['immediate']
): Promise<LayerResult> {
  if (!config.enabled) {
    return { name: 'immediate', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
  }

  let messages: ChatMessage[] = sessionMessages || [];

  // If no messages provided, try to fetch from Firestore
  if (messages.length === 0 && sessionId) {
    try {
      const messagesRef = db.collection('chats').doc(iin)
        .collection('sessions').doc(sessionId)
        .collection('messages')
        .orderBy('timestamp', 'desc')
        .limit(config.maxMessages);

      const snapshot = await messagesRef.get();
      messages = snapshot.docs.map(doc => {
        const data = doc.data();
        return {
          role: data.role as 'user' | 'assistant',
          content: data.content,
          timestamp: data.timestamp,
        };
      }).reverse(); // Reverse to get chronological order
    } catch (error) {
      console.log('[Layer 1] Could not fetch session messages:', error);
    }
  }

  // Take last N messages
  const recentMessages = messages.slice(-config.maxMessages);

  if (recentMessages.length === 0) {
    return { name: 'immediate', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
  }

  // Format messages
  let content: string;
  if (config.format === 'conversation') {
    content = recentMessages.map(m =>
      `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`
    ).join('\n');
  } else if (config.format === 'json') {
    content = JSON.stringify(recentMessages, null, 2);
  } else {
    content = recentMessages.map(m => m.content).join(' | ');
  }

  // Trim if exceeds token budget
  let trimmed = false;
  const tokenCount = estimateTokens(content);
  if (tokenCount > config.tokenBudget) {
    // Remove oldest messages until within budget
    while (recentMessages.length > 1 && estimateTokens(content) > config.tokenBudget) {
      recentMessages.shift();
      content = recentMessages.map(m =>
        `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`
      ).join('\n');
      trimmed = true;
    }
  }

  console.log(`[Layer 1 - Immediate] ${recentMessages.length} messages, ${estimateTokens(content)} tokens${trimmed ? ' (trimmed)' : ''}`);

  return {
    name: 'immediate',
    content,
    tokenCount: estimateTokens(content),
    itemCount: recentMessages.length,
    trimmed,
  };
}

/**
 * LAYER 2 - SESSION SUMMARY: Summarize early conversation if session is long
 */
async function buildLayer2SessionSummary(
  iin: string,
  sessionId: string | undefined,
  sessionMessages: ChatMessage[] | undefined,
  config: LayerConfig['sessionSummary'],
  summaryLLMConfig: ContextInjectionConfig['summaryLLM']
): Promise<LayerResult> {
  if (!config.enabled) {
    return { name: 'sessionSummary', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
  }

  const messages = sessionMessages || [];

  // Only generate summary if session exceeds threshold
  if (messages.length <= config.threshold) {
    console.log(`[Layer 2 - Session Summary] Session has ${messages.length} messages, threshold is ${config.threshold}, skipping`);
    return { name: 'sessionSummary', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
  }

  // Check cache first
  if (config.cacheEnabled && sessionId) {
    try {
      const cacheRef = db.collection('chats').doc(iin)
        .collection('sessions').doc(sessionId)
        .collection('cache').doc('summary');

      const cacheDoc = await cacheRef.get();
      if (cacheDoc.exists) {
        const cacheData = cacheDoc.data();
        const cacheAge = Date.now() - (cacheData?.generatedAt?._seconds * 1000 || 0);
        const maxAge = config.cacheTTLMinutes * 60 * 1000;

        if (cacheAge < maxAge) {
          console.log('[Layer 2 - Session Summary] Using cached summary');
          return {
            name: 'sessionSummary',
            content: cacheData?.summary || '',
            tokenCount: estimateTokens(cacheData?.summary || ''),
            itemCount: cacheData?.messageCount || 0,
            trimmed: false,
          };
        }
      }
    } catch (error) {
      console.log('[Layer 2] Cache lookup failed:', error);
    }
  }

  // Generate summary for first N messages
  const messagesToSummarize = messages.slice(0, config.summarizeCount);
  const conversationText = messagesToSummarize.map(m =>
    `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`
  ).join('\n');

  try {
    const apiKey = await getSecret('gemini-api-key');
    if (!apiKey) {
      console.log('[Layer 2] No API key for summary generation');
      return { name: 'sessionSummary', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
      model: summaryLLMConfig?.model || 'gemini-2.0-flash-exp',
      generationConfig: {
        temperature: summaryLLMConfig?.temperature || 0.3,
        maxOutputTokens: summaryLLMConfig?.maxTokens || 200,
      },
    });

    const prompt = (summaryLLMConfig?.prompt || 'Summarize: {{messages}}')
      .replace('{{messages}}', conversationText);

    const result = await model.generateContent(prompt);
    const summary = result.response.text().trim();

    // Cache the summary
    if (config.cacheEnabled && sessionId) {
      try {
        await db.collection('chats').doc(iin)
          .collection('sessions').doc(sessionId)
          .collection('cache').doc('summary')
          .set({
            summary,
            messageCount: messagesToSummarize.length,
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
      } catch (error) {
        console.log('[Layer 2] Cache write failed:', error);
      }
    }

    console.log(`[Layer 2 - Session Summary] Generated summary for ${messagesToSummarize.length} messages, ${estimateTokens(summary)} tokens`);

    return {
      name: 'sessionSummary',
      content: summary,
      tokenCount: estimateTokens(summary),
      itemCount: messagesToSummarize.length,
      trimmed: false,
    };
  } catch (error) {
    console.error('[Layer 2] Summary generation failed:', error);
    return { name: 'sessionSummary', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
  }
}

/**
 * LAYER 3 - USER PROFILE: Query relevant memories
 */
async function buildLayer3Profile(
  iin: string,
  currentMessage: string,
  providedMemories: Memory[] | undefined,
  config: LayerConfig['profile'],
  filterConfig: ContextInjectionConfig['filter'],
  injectionConfig: ContextInjectionConfig['injection']
): Promise<LayerResult> {
  if (!config.enabled) {
    return { name: 'profile', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
  }

  let memories: Memory[] = providedMemories || [];

  // Query memories if not provided
  if (memories.length === 0) {
    try {
      const queryResult = await queryMemories({
        iin,
        query: currentMessage,
        context: 'general',
      });
      memories = queryResult.memories || [];
    } catch (error) {
      console.log('[Layer 3] Memory query failed:', error);
    }
  }

  // Filter by included types from layer config
  memories = memories.filter(m => {
    const memType = m.type?.toLowerCase();
    return config.includeTypes.includes(memType) && !config.excludeTypes.includes(memType);
  });

  // Apply relevance filter
  memories = memories.filter(m => m.relevance >= injectionConfig.minRelevance);

  // Limit to max memories
  memories = memories.slice(0, config.maxMemories);

  if (memories.length === 0) {
    return { name: 'profile', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
  }

  // Format memories
  const content = memories.map(m => `- ${m.content}`).join('\n');

  // Check token budget
  let trimmed = false;
  let finalMemories = memories;
  let finalContent = content;
  if (estimateTokens(content) > config.tokenBudget) {
    // Trim least relevant memories
    while (finalMemories.length > 1 && estimateTokens(finalContent) > config.tokenBudget) {
      finalMemories = finalMemories.slice(0, -1);
      finalContent = finalMemories.map(m => `- ${m.content}`).join('\n');
      trimmed = true;
    }
  }

  console.log(`[Layer 3 - Profile] ${finalMemories.length} memories, ${estimateTokens(finalContent)} tokens${trimmed ? ' (trimmed)' : ''}`);

  return {
    name: 'profile',
    content: finalContent,
    tokenCount: estimateTokens(finalContent),
    itemCount: finalMemories.length,
    trimmed,
  };
}

/**
 * LAYER 4 - CALENDAR: Get upcoming events within lookahead window
 */
async function buildLayer4Calendar(
  iin: string,
  config: LayerConfig['calendar']
): Promise<LayerResult> {
  if (!config.enabled) {
    return { name: 'calendar', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
  }

  const now = new Date();
  const lookahead = new Date(now.getTime() + config.lookaheadHours * 60 * 60 * 1000);

  try {
    // Query events collection
    const eventsRef = db.collection('memories').doc(iin)
      .collection('events')
      .where('date', '>=', now)
      .where('date', '<=', lookahead)
      .orderBy('date', 'asc')
      .limit(config.maxEvents);

    const snapshot = await eventsRef.get();

    if (snapshot.empty) {
      console.log('[Layer 4 - Calendar] No upcoming events');
      return { name: 'calendar', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
    }

    const events: CalendarEvent[] = snapshot.docs.map(doc => {
      const data = doc.data();
      return {
        id: doc.id,
        title: data.title || data.content || 'Untitled event',
        date: data.date?.toDate?.() || new Date(data.date),
        time: data.time,
        description: data.description,
      };
    });

    // Format events
    let content: string;
    if (config.format === 'list') {
      content = events.map(e => {
        const dateStr = e.date.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
        const timeStr = e.time || e.date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
        return `- ${dateStr} ${timeStr}: ${e.title}`;
      }).join('\n');
    } else if (config.format === 'prose') {
      content = events.map(e => {
        const dateStr = e.date.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
        return `${e.title} on ${dateStr}`;
      }).join('. ');
    } else {
      content = JSON.stringify(events, null, 2);
    }

    console.log(`[Layer 4 - Calendar] ${events.length} events, ${estimateTokens(content)} tokens`);

    return {
      name: 'calendar',
      content,
      tokenCount: estimateTokens(content),
      itemCount: events.length,
      trimmed: false,
    };
  } catch (error) {
    // Calendar collection may not exist yet - that's okay
    console.log('[Layer 4 - Calendar] No events collection or query failed:', error);
    return { name: 'calendar', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
  }
}

/**
 * LAYER 5 - PAST CONVERSATIONS: Get compressed summaries from nightly compression
 */
async function buildLayer5PastConversations(
  iin: string,
  config: LayerConfig['pastConversations']
): Promise<LayerResult> {
  if (!config.enabled) {
    return { name: 'pastConversations', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
  }

  try {
    // Get summaries from the compression module
    const summaries = await getRecentSummaries(iin, config.maxDays);

    if (summaries.length === 0) {
      console.log('[Layer 5 - Past Conversations] No compressed summaries available');
      return { name: 'pastConversations', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
    }

    // Format summaries for context
    let content = formatSummariesForContext(summaries);

    // Check token budget and trim if needed
    let trimmed = false;
    let finalSummaries = summaries;
    if (estimateTokens(content) > config.tokenBudget) {
      // Remove oldest summaries until within budget
      while (finalSummaries.length > 1 && estimateTokens(content) > config.tokenBudget) {
        finalSummaries = finalSummaries.slice(0, -1);
        content = formatSummariesForContext(finalSummaries);
        trimmed = true;
      }
    }

    console.log(`[Layer 5 - Past Conversations] ${finalSummaries.length} day summaries, ${estimateTokens(content)} tokens${trimmed ? ' (trimmed)' : ''}`);

    return {
      name: 'pastConversations',
      content,
      tokenCount: estimateTokens(content),
      itemCount: finalSummaries.length,
      trimmed,
    };
  } catch (error) {
    console.log('[Layer 5 - Past Conversations] Error fetching summaries:', error);
    return { name: 'pastConversations', content: '', tokenCount: 0, itemCount: 0, trimmed: false };
  }
}

/**
 * Assemble all 5 layers into final context
 */
async function assemble4LayerContext(
  input: {
    iin: string;
    message: string;
    sessionId?: string;
    sessionMessages?: ChatMessage[];
    memories?: Memory[];
    userName?: string;
  },
  config: ContextInjectionConfig
): Promise<{
  layers: LayerResult[];
  assembledContext: string;
  totalTokens: number;
  debug: {
    layersIncluded: string[];
    tokensPerLayer: Record<string, number>;
    trimmed: string[];
  };
}> {
  const layers: LayerResult[] = [];
  const layerConfig = config.layers!;

  // Build all 5 layers in parallel
  const [layer1, layer2, layer3, layer4, layer5] = await Promise.all([
    buildLayer1Immediate(input.iin, input.sessionId, input.sessionMessages, layerConfig.immediate),
    buildLayer2SessionSummary(input.iin, input.sessionId, input.sessionMessages, layerConfig.sessionSummary, config.summaryLLM),
    buildLayer3Profile(input.iin, input.message, input.memories, layerConfig.profile, config.filter, config.injection),
    buildLayer4Calendar(input.iin, layerConfig.calendar),
    buildLayer5PastConversations(input.iin, layerConfig.pastConversations),
  ]);

  layers.push(layer1, layer2, layer3, layer4, layer5);

  // Build assembled context according to section order
  const sectionOrder = config.promptStructure?.sectionOrder || ['profile', 'calendar', 'pastConversations', 'sessionSummary', 'immediate'];
  const sectionHeaders = config.promptStructure?.sectionHeaders || {};

  const layerMap: Record<string, LayerResult> = {
    immediate: layer1,
    sessionSummary: layer2,
    profile: layer3,
    calendar: layer4,
    pastConversations: layer5,
  };

  const sections: string[] = [];
  const layersIncluded: string[] = [];
  const tokensPerLayer: Record<string, number> = {};
  const trimmed: string[] = [];

  for (const section of sectionOrder) {
    const layer = layerMap[section];
    if (layer && layer.content) {
      const header = sectionHeaders[section] || section.toUpperCase() + ':';
      sections.push(`${header}\n${layer.content}`);
      layersIncluded.push(section);
      tokensPerLayer[section] = layer.tokenCount;
      if (layer.trimmed) {
        trimmed.push(section);
      }
    }
  }

  const assembledContext = sections.join('\n\n');
  const totalTokens = Object.values(tokensPerLayer).reduce((a, b) => a + b, 0);

  // Log debug info
  if (config.debug?.logLayerTokens) {
    console.log('[4-Layer Context] Token breakdown:', tokensPerLayer);
    console.log(`[4-Layer Context] Total: ${totalTokens} tokens, Layers: ${layersIncluded.join(', ')}`);
  }

  return {
    layers,
    assembledContext,
    totalTokens,
    debug: {
      layersIncluded,
      tokensPerLayer,
      trimmed,
    },
  };
}

interface ContextInjectionResult {
  prompt: {
    system: string;
    memories: string;
    saveInstruction?: string;  // Injected for memory_instruction intent
    user: string;
    full: string;
  };
  memoriesUsed: number;
  memoriesFiltered: number;
  tokenEstimate: number;
  saveResultsInjected: boolean;  // Whether save results were added to prompt

  // NEW: Memory cards for Generative UI
  memoryCards?: MemoryCard[];
  holdForClarification?: boolean;

  // NEW: Quick replies for Generative UI
  quickRepliesAction?: RenderQuickRepliesAction;

  // NEW: 4-Layer context debug info
  layerContext?: {
    layers: LayerResult[];
    assembledContext: string;
    totalTokens: number;
    debug: {
      layersIncluded: string[];
      tokensPerLayer: Record<string, number>;
      trimmed: string[];
    };
  };

  config: {
    source: string;
    maxMemories: number;
    format: string;
    enabledTypes: string[];
    enabledTiers: string[];
  };
  processingTime: string;
  timestamp: string;
}

// ═══════════════════════════════════════════════════════════
// QUICK REPLIES BUILDER
// ═══════════════════════════════════════════════════════════

function buildQuickRepliesAction(
  intent: string | undefined,
  saveDecision: SaveDecision | undefined | null,
  isHolding: boolean
): RenderQuickRepliesAction | undefined {
  const replies: QuickReply[] = [];

  // If holding for clarification, don't add quick replies (cards are shown instead)
  if (isHolding) {
    return undefined;
  }

  // Generate context-aware quick replies based on intent and save decision
  if (intent === 'greeting' || intent === 'smalltalk') {
    // Greeting context - casual conversation starters
    replies.push(
      { id: 'qr_howareyou', label: "How are you?", message: "How are you doing today?", icon: '👋' },
      { id: 'qr_whatcanido', label: "What can you do?", message: "What can you help me with?", icon: '❓' },
      { id: 'qr_tellme', label: "Tell me something", message: "Tell me something interesting", icon: '💡' },
    );
  } else if (intent === 'memory_instruction' && saveDecision?.saved === true) {
    // Memory was saved - offer follow-up options
    replies.push(
      { id: 'qr_showmemories', label: "Show my memories", message: "Show me what you remember about me", icon: '🧠' },
      { id: 'qr_addmore', label: "Add more", message: "I want to tell you something else", icon: '➕' },
      { id: 'qr_thanks', label: "Thanks!", message: "Thanks, that's all for now", icon: '👍' },
    );
  } else if (intent === 'memory_recall' || intent === 'memory_recall_temporal') {
    // User was asking about memories - offer navigation
    replies.push(
      { id: 'qr_lastweek', label: "Last week", message: "What happened last week?", icon: '📅' },
      { id: 'qr_relationships', label: "My people", message: "Who do you know about in my life?", icon: '👥' },
      { id: 'qr_events', label: "Upcoming events", message: "What events do I have coming up?", icon: '📆' },
    );
  } else if (intent === 'question') {
    // User asked a question - offer follow-ups
    replies.push(
      { id: 'qr_tellmore', label: "Tell me more", message: "Tell me more about that", icon: '📖' },
      { id: 'qr_example', label: "Give an example", message: "Can you give me an example?", icon: '💡' },
    );
  }
  // No default quick replies - keep chat clean for general conversation

  // Only return if we have replies
  if (replies.length === 0) {
    return undefined;
  }

  return createQuickRepliesAction({ replies });
}

// ═══════════════════════════════════════════════════════════
// MAIN INJECTION FUNCTION
// ═══════════════════════════════════════════════════════════

async function buildContextPrompt(input: ContextInjectionInput): Promise<ContextInjectionResult> {
  const startTime = Date.now();

  // ═══════════════════════════════════════════════════════════
  // TEMPORARY DIAGNOSTIC LOGS — INTENT WIRING VERIFICATION
  // TODO: Remove after verification complete
  // ═══════════════════════════════════════════════════════════
  console.log('[CTX DIAG] Raw input.intent:', input.intent);
  console.log('[CTX DIAG] typeof input.intent:', typeof input.intent);
  console.log('[CTX DIAG] input.intent value:', JSON.stringify(input.intent));

  // 1. Load config
  const config = await getContextInjectionConfig();

  // Get enabled types and tiers
  const enabledTypes = getEnabledTypes(config);
  const enabledTiers = getEnabledTiers(config);

  if (!config.injection.enabled) {
    return {
      prompt: {
        system: config.prompts.systemPrompt,
        memories: config.prompts.noMemoriesText,
        user: config.prompts.userMessageFormat.replace('{{message}}', input.message),
        full: buildFullPrompt(config.prompts.systemPrompt, config.prompts.noMemoriesText, input.message, config),
      },
      memoriesUsed: 0,
      memoriesFiltered: 0,
      tokenEstimate: estimateTokens(config.prompts.systemPrompt + config.prompts.noMemoriesText + input.message),
      saveResultsInjected: false,
      config: {
        source: 'config/pipeline/stages/context_injection',
        maxMemories: config.injection.maxMemories,
        format: config.format.memoryFormat,
        enabledTypes,
        enabledTiers,
      },
      processingTime: `${Date.now() - startTime}ms`,
      timestamp: new Date().toISOString(),
    };
  }

  // 2. Get memories (from input or query)
  let memories: Memory[] = input.memories ?? [];

  if (memories.length === 0) {
    // Query memories if not provided
    const queryResult = await queryMemories({
      iin: input.iin,
      query: input.message,
      context: 'general',
    });
    memories = queryResult.memories;
  }

  const totalMemories = memories.length;

  // 3. Filter by type
  memories = memories.filter(m => enabledTypes.includes(m.type));

  // 4. Filter by tier
  memories = memories.filter(m => enabledTiers.includes(m.tier));

  // 5. Filter by relevance
  memories = memories.filter(m => m.relevance >= config.injection.minRelevance);

  // 6. Sort
  memories = sortMemories(memories, config.injection.sortBy);

  // 7. Limit
  memories = memories.slice(0, config.injection.maxMemories);

  // ═══════════════════════════════════════════════════════════
  // FIX 2: INTENT NORMALIZATION (BOUNDARY INPUT)
  //
  // Normalize intent to a lowercase string before any downstream use.
  // Upstream may pass:
  //   - string: "greeting"
  //   - object: { primary: "greeting", confidence: 0.92 }
  //
  // This is INPUT NORMALIZATION ONLY — no intent detection or inference.
  // If intent cannot be resolved → undefined (triggers fail-safe filter).
  // ═══════════════════════════════════════════════════════════
  const normalizedIntent: string | undefined =
    typeof input.intent === 'string'
      ? input.intent.toLowerCase()
      : typeof input.intent === 'object' && input.intent !== null && typeof input.intent?.primary === 'string'
        ? input.intent.primary.toLowerCase()
        : undefined;

  // TEMPORARY DIAGNOSTIC LOG — NORMALIZED INTENT
  console.log('[CTX DIAG] Normalized intent:', normalizedIntent);

  // ═══════════════════════════════════════════════════════════
  // FIX 4: CONTEXT MODE DERIVATION
  // Derive context mode strictly from intent — NO inference.
  // FIX 5: Added memory_use_allowed for question/recall intents
  // ═══════════════════════════════════════════════════════════
  let contextMode: ContextMode;
  if (normalizedIntent === 'memory_instruction') {
    contextMode = 'memory_confirm_allowed';
  } else if (normalizedIntent === 'greeting' || normalizedIntent === 'smalltalk') {
    contextMode = 'identity_only';
  } else if (
    normalizedIntent === 'question' ||
    normalizedIntent === 'memory_recall' ||
    normalizedIntent === 'memory_recall_temporal' ||
    normalizedIntent === 'recommendation' ||
    normalizedIntent === 'advice'
  ) {
    // FIX 5: For questions and recalls, encourage using memories
    contextMode = 'memory_use_allowed';
  } else if (!normalizedIntent) {
    // No intent provided - be conservative
    contextMode = 'identity_only';
  } else {
    // Default for statements, etc.
    contextMode = 'neutral_ack';
  }

  // ═══════════════════════════════════════════════════════════
  // FIX 2: INTENT-BASED MEMORY FILTER
  // Apply after all other filters to restrict what memories are injected.
  // Intent is READ from upstream Stage 4 - no decision making here.
  // Fail safe = inject fewer memories.
  // ═══════════════════════════════════════════════════════════
  const memoriesBeforeIntentFilter = memories.length;
  memories = filterMemoriesByIntent(memories, normalizedIntent);
  const memoriesFilteredByIntent = memoriesBeforeIntentFilter - memories.length;
  console.log(`[Context Injection] FIX 2 applied: ${memoriesFilteredByIntent} memories filtered by intent "${normalizedIntent || 'none'}"`);

  const memoriesFiltered = totalMemories - memories.length;

  // 8. Format memories
  const formattedMemories = formatMemories(memories, config);

  // ═══════════════════════════════════════════════════════════
  // FIX 4: CONTEXT MODE GUARD + FIX 1: ANTI-HALLUCINATION GUARD
  // Order: basePrompt → contextModeGuard → antiHallucinationGuard
  // ═══════════════════════════════════════════════════════════
  let systemPrompt =
    config.prompts.systemPrompt +
    '\n\n' +
    buildContextModeGuard(contextMode) +
    ANTI_HALLUCINATION_GUARD;

  // ═══════════════════════════════════════════════════════════
  // NEW: CHECK FOR HOLD FOR CLARIFICATION (from Save Decision)
  // If holding, adjust system prompt to guide LLM response
  // ═══════════════════════════════════════════════════════════
  const isHolding = input.saveDecision?.decision === 'hold';
  const pendingCards = input.saveDecision?.pendingCards || [];

  if (isHolding && pendingCards.length > 0) {
    const incompleteCount = pendingCards.filter(c => !c.complete).length;
    const cardSummary = pendingCards.map(c =>
      `- ${c.icon} ${c.title}: missing ${c.missingRequired.join(', ') || 'none'}`
    ).join('\n');

    const clarificationContext = `

[CONTEXT: MEMORY CARDS PENDING]
The user shared information that I'm capturing.
${incompleteCount} item(s) need more details before saving.

Items detected:
${cardSummary}

IMPORTANT INSTRUCTIONS:
- The UI will show interactive cards for the user to complete
- Keep your text response brief and friendly
- Acknowledge what you understood
- Do NOT list all missing fields in text - the cards show that
- Example: "Got it! I'll save that once you complete the details."
`.trim();

    systemPrompt = systemPrompt + '\n\n' + clarificationContext;
    console.log(`[Context Injection] Holding for clarification: ${incompleteCount} incomplete cards`);
  }

  // 9. Build prompt sections
  const memoriesSection = memories.length > 0
    ? `${config.prompts.memoryHeader}\n\n${formattedMemories}`
    : config.prompts.noMemoriesText;
  const userSection = config.prompts.userMessageFormat.replace('{{message}}', input.message);

  // ═══════════════════════════════════════════════════════════
  // FIX 1 - RULES 1-3: SAVE DECISION BINDING (DATA-DRIVEN ONLY)
  //
  // CRITICAL: Stage 8 is the ONLY authority on whether memory was saved.
  // Stage 9 must NEVER infer, guess, or recompute save status.
  // We do NOT check intent here - all behavior is driven by upstream data.
  //
  // Priority: saveDecision (new format) > saveResults (legacy) > default (no save)
  // ═══════════════════════════════════════════════════════════
  let saveInstruction: string | undefined;
  let saveResultsInjected = false;

  // FIX 1 Rule 5: Backward compatibility - prefer saveDecision over saveResults
  if (input.saveDecision !== undefined) {
    // New format: single saveDecision object from Stage 8
    saveInstruction = buildSaveDecisionInstruction(input.saveDecision);
    saveResultsInjected = true;
    console.log('[Context Injection] FIX 1: Injecting save decision instruction (new format)');
  } else if (input.saveResults && input.saveResults.length > 0) {
    // Legacy format: array of saveResults from Stage 8
    saveInstruction = buildLegacySaveInstruction(input.saveResults);
    saveResultsInjected = true;
    console.log('[Context Injection] FIX 1: Injecting save instruction (legacy format)');
  } else {
    // FIX 1 Rule 3: No save information = assume nothing was saved
    // Inject instruction to prevent false claims
    saveInstruction = buildNoSaveInstruction();
    saveResultsInjected = true;
    console.log('[Context Injection] FIX 1: No save decision provided, injecting no-save instruction');
  }

  // ═══════════════════════════════════════════════════════════
  // NEW: 4-LAYER CONTEXT ASSEMBLY
  // Build layered context for enhanced AI memory
  // ═══════════════════════════════════════════════════════════
  let layerContextResult: {
    layers: LayerResult[];
    assembledContext: string;
    totalTokens: number;
    debug: {
      layersIncluded: string[];
      tokensPerLayer: Record<string, number>;
      trimmed: string[];
    };
  } | undefined;

  if (config.layers) {
    try {
      layerContextResult = await assemble4LayerContext(
        {
          iin: input.iin,
          message: input.message,
          sessionId: input.sessionId,
          sessionMessages: input.sessionMessages,
          memories: memories,
          userName: input.userName,
        },
        config
      );

      // Log 4-layer assembly debug
      if (config.debug?.logAssembly) {
        console.log(`[Context Injection] 4-Layer Context assembled: ${layerContextResult.debug.layersIncluded.length} layers, ${layerContextResult.totalTokens} tokens`);
      }
    } catch (error) {
      console.error('[Context Injection] 4-Layer assembly failed, falling back to legacy:', error);
    }
  }

  // 11. Build full prompt (with or without 4-layer context)
  let fullPrompt: string;
  if (layerContextResult && layerContextResult.assembledContext) {
    // Use 4-layer context: System + Layers + User
    const layeredSystem = config.promptStructure?.systemPromptTemplate
      ? config.promptStructure.systemPromptTemplate.replace('{{userName}}', input.userName || 'this user')
      : systemPrompt;

    fullPrompt = `${layeredSystem}

${buildContextModeGuard(contextMode)}
${ANTI_HALLUCINATION_GUARD}

${layerContextResult.assembledContext}

${saveInstruction || ''}

User: ${input.message}`;
  } else {
    // Fallback to legacy prompt building
    fullPrompt = buildFullPrompt(systemPrompt, memoriesSection, input.message, config, saveInstruction);
  }

  // 12. Estimate tokens
  const tokenEstimate = estimateTokens(fullPrompt);

  // 13. Build quick replies action
  const quickRepliesAction = buildQuickRepliesAction(
    normalizedIntent,
    input.saveDecision,
    isHolding
  );
  if (quickRepliesAction) {
    console.log(`[Context Injection] Built quick replies with ${quickRepliesAction.params.replies.length} options`);
  }

  const processingTime = Date.now() - startTime;

  return {
    prompt: {
      system: systemPrompt,
      memories: memoriesSection,
      saveInstruction,
      user: userSection,
      full: fullPrompt,
    },
    memoriesUsed: memories.length,
    memoriesFiltered,
    tokenEstimate,
    saveResultsInjected,

    // NEW: Memory cards for Generative UI
    memoryCards: pendingCards.length > 0 ? pendingCards : undefined,
    holdForClarification: isHolding,

    // NEW: Quick replies for Generative UI
    quickRepliesAction,

    // NEW: 4-Layer context debug info
    layerContext: layerContextResult,

    config: {
      source: 'config/pipeline/stages/context_injection',
      maxMemories: config.injection.maxMemories,
      format: config.format.memoryFormat,
      enabledTypes,
      enabledTiers,
    },
    processingTime: `${processingTime}ms`,
    timestamp: new Date().toISOString(),
  };
}

// ═══════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════

function getEnabledTypes(config: ContextInjectionConfig): string[] {
  const types: string[] = [];
  if (config.filter.includeFacts) types.push('fact');
  if (config.filter.includePreferences) types.push('preference');
  if (config.filter.includeRelationships) types.push('relationship');
  if (config.filter.includeEvents) types.push('event');
  if (config.filter.includeGoals) types.push('goal');
  if (config.filter.includeTodos) types.push('todo');
  if (config.filter.includeNotes) types.push('note');
  return types;
}

function getEnabledTiers(config: ContextInjectionConfig): string[] {
  const tiers: string[] = [];
  if (config.filter.includeWorkingTier) tiers.push('working');
  if (config.filter.includeLongtermTier) tiers.push('longterm');
  if (config.filter.includeDeepTier) tiers.push('deep');
  return tiers;
}

function sortMemories(memories: Memory[], sortBy: string): Memory[] {
  switch (sortBy) {
    case 'relevance':
      return [...memories].sort((a, b) => b.relevance - a.relevance);
    case 'recency':
      return [...memories].sort((a, b) => {
        const aTime = a.created_at?._seconds ?? 0;
        const bTime = b.created_at?._seconds ?? 0;
        return bTime - aTime;
      });
    case 'type':
      return [...memories].sort((a, b) => a.type.localeCompare(b.type));
    default:
      return memories;
  }
}

function formatMemories(memories: Memory[], config: ContextInjectionConfig): string {
  if (memories.length === 0) return '';

  const format = config.format.memoryFormat;
  const itemFormat = config.prompts.memoryItemFormat;
  const separator = config.format.separator === 'newline' ? '\n' : ', ';

  if (config.format.groupByType) {
    return formatGroupedMemories(memories, config);
  }

  const formattedItems = memories.map((memory, index) => {
    let item = itemFormat
      .replace('{{content}}', memory.content)
      .replace('{{type}}', memory.type)
      .replace('{{context}}', memory.context);

    // Apply format
    switch (format) {
      case 'numbered':
        item = `${index + 1}. ${memory.content}`;
        break;
      case 'prose':
        item = memory.content;
        break;
      case 'json':
        item = JSON.stringify({ type: memory.type, content: memory.content });
        break;
      case 'bullet':
      default:
        // Use itemFormat as is
        break;
    }

    // Add metadata if enabled
    if (config.format.includeMetadata) {
      item += ` [${memory.type}]`;
    }

    return item;
  });

  // Handle prose format differently
  if (format === 'prose') {
    return formattedItems.join('. ') + '.';
  }

  // Handle JSON format
  if (format === 'json') {
    return JSON.stringify(memories.map(m => ({
      type: m.type,
      content: m.content,
      context: m.context,
    })), null, 2);
  }

  return formattedItems.join(separator);
}

function formatGroupedMemories(memories: Memory[], config: ContextInjectionConfig): string {
  const groups: Record<string, Memory[]> = {};

  // Group by type
  for (const memory of memories) {
    if (!groups[memory.type]) {
      groups[memory.type] = [];
    }
    groups[memory.type].push(memory);
  }

  // Format each group
  const sections: string[] = [];
  const typeLabels: Record<string, string> = {
    fact: 'Facts',
    preference: 'Preferences',
    relationship: 'Relationships',
    event: 'Events',
    goal: 'Goals',
    todo: 'Tasks',
    note: 'Notes',
  };

  for (const [type, typeMemories] of Object.entries(groups)) {
    const label = typeLabels[type] ?? type;
    const items = typeMemories.map(m => `- ${m.content}`).join('\n');
    sections.push(`**${label}:**\n${items}`);
  }

  return sections.join('\n\n');
}

// ═══════════════════════════════════════════════════════════
// FIX 1.1: STRICT MEMORY TRUTH ENFORCEMENT
//
// HARD RULE: Stage 9 is the SINGLE SOURCE OF TRUTH for memory save confirmation.
// If Stage 9 does NOT inject a save instruction, the LLM must behave as if
// no memory was saved — even if:
//   - The user said a factual statement
//   - The information appears in injected memories
//   - The conversation sounds like a memory command
//
// PRECEDENCE (STRICT):
//   1. saveDecision (new format) - if saved === true → allow confirmation
//   2. legacy saveResults[] - if any saved === true → allow confirmation
//   3. NO-SAVE RULE (default) - forbid all save claims
//
// This is a SAFETY-FIRST implementation.
// ═══════════════════════════════════════════════════════════

/**
 * FIX 1.1: NO-SAVE DEFAULT SYSTEM INSTRUCTION
 *
 * This is the DEFAULT instruction injected when:
 *   - saveDecision is missing OR saveDecision.saved === false
 *   - saveResults is empty OR no items have saved === true
 *
 * APPLIES TO ALL INTENTS. Overrides tone, friendliness, conversational style.
 * Injected even if memory context is present.
 */
const NO_SAVE_DEFAULT_INSTRUCTION = `
[CRITICAL MEMORY RULE — NO SAVE CONFIRMED]

- No new memory has been saved during this message.
- You MUST NOT say or imply that you:
  - remembered this
  - saved this
  - added this to memory
  - updated your memory
  - will remember this later
- Treat the user's statement as conversational only.
- You MAY acknowledge the information neutrally (e.g. "Got it", "Thanks for sharing").
- You MUST NOT suggest persistence, future recall, or learning.

[END RULE]`;

/**
 * FIX 1.1: Build save instruction from new SaveDecision format.
 *
 * STRICT PRECEDENCE:
 *   - saveDecision.saved === true → Allow confirmation
 *   - saveDecision.saved === false OR missing → NO-SAVE RULE
 *
 * @param saveDecision - The save decision from Stage 8 (consumed, not computed)
 * @returns Instruction string to inject into the prompt
 */
function buildSaveDecisionInstruction(saveDecision: SaveDecision | null | undefined): string {
  // ONLY allow save confirmation if explicitly saved === true
  if (saveDecision?.saved === true) {
    return `
[MEMORY SAVE CONFIRMED]
- Successfully saved to memory.
- You MAY confirm to the user that this information was saved.
- You MAY say "I'll remember that" or similar confirmation.
[END CONFIRMATION]`;
  }

  // DEFAULT: No save confirmed — apply strict NO-SAVE rule
  return NO_SAVE_DEFAULT_INSTRUCTION;
}

/**
 * FIX 1.1: Build instruction when NO save decision was provided.
 * Default safe behavior: assume nothing was saved.
 *
 * This is the SAFETY-FIRST default.
 *
 * @returns NO-SAVE instruction forbidding all save claims
 */
function buildNoSaveInstruction(): string {
  return NO_SAVE_DEFAULT_INSTRUCTION;
}

/**
 * FIX 1.1: Legacy format support for saveResults[] array.
 * Maintains backward compatibility with older flows.
 *
 * STRICT PRECEDENCE:
 *   - ANY saveResults[].saved === true → Allow confirmation
 *   - Otherwise → NO-SAVE RULE
 *
 * @param saveResults - Array of save results from Stage 8 (legacy format)
 * @returns Instruction string to inject into the prompt
 */
function buildLegacySaveInstruction(saveResults: SaveResult[]): string {
  // Safety check: if empty or missing, apply NO-SAVE rule
  if (!saveResults || saveResults.length === 0) {
    return NO_SAVE_DEFAULT_INSTRUCTION;
  }

  // Check if ANY items were successfully saved
  const savedItems = saveResults.filter(r => r.saved === true);

  if (savedItems.length > 0) {
    // At least one item saved - allow confirmation
    let instruction = `
[MEMORY SAVE CONFIRMED]
- Successfully saved to memory:`;
    for (const item of savedItems) {
      instruction += `\n  * "${item.content}"`;
    }
    instruction += `
- You MAY confirm to the user that this information was saved.
[END CONFIRMATION]`;
    return instruction;
  }

  // No items saved - apply strict NO-SAVE rule
  return NO_SAVE_DEFAULT_INSTRUCTION;
}

function buildFullPrompt(
  system: string,
  memories: string,
  message: string,
  config: ContextInjectionConfig,
  saveInstruction?: string
): string {
  const userFormat = config.prompts.userMessageFormat.replace('{{message}}', message);

  let prompt = `${system}

${memories}`;

  // Add save instruction if present (for memory_instruction intent)
  if (saveInstruction) {
    prompt += saveInstruction;
  }

  prompt += `

${userFormat}`;

  return prompt;
}

function estimateTokens(text: string): number {
  // Rough estimate: ~4 characters per token
  return Math.ceil(text.length / 4);
}

// ═══════════════════════════════════════════════════════════
// HTTP ENDPOINT
// ═══════════════════════════════════════════════════════════

export const testContextInjection = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    // Accept both saveDecision (new format) and saveResults (legacy format)
    const { iin, message, memories, intent, saveResults, saveDecision } = req.body;

    if (!iin) {
      res.status(400).json({ error: 'IIN is required' });
      return;
    }

    if (!message) {
      res.status(400).json({ error: 'Message is required' });
      return;
    }

    console.log(`Context Injection: iin=${iin}, message="${message.substring(0, 50)}...", intent=${intent || 'none'}, saveDecision=${JSON.stringify(saveDecision)}`);

    const result = await buildContextPrompt({ iin, message, memories, intent, saveResults, saveDecision });

    res.status(200).json({
      stage: 'Context Injection',
      stageNumber: 9,
      input: {
        iin,
        message: message.substring(0, 100) + (message.length > 100 ? '...' : ''),
        intent: intent || 'none',
        saveResultsProvided: saveResults?.length || 0,
        saveDecisionProvided: saveDecision !== undefined,
      },
      ...result,
    });
  } catch (error: any) {
    console.error('Context Injection error:', error);
    res.status(500).json({
      error: error.message ?? 'Internal server error',
    });
  }
});

export { buildContextPrompt, getContextInjectionConfig };
