// IAMONEAI - Direct LLM Mode (Clean Restart)
import { onRequest, Request } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { Response } from 'express';
import { GoogleGenerativeAI } from '@google/generative-ai';
import Anthropic from '@anthropic-ai/sdk';
import OpenAI from 'openai';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import { processDecisionPipeline } from './pipeline';

admin.initializeApp();
const db = admin.firestore();
const secretManager = new SecretManagerServiceClient();

// Secret cache
const secretCache: Record<string, string> = {};

// System prompt - Cloud Commander Mode
const SYSTEM_PROMPT = `You are IAMONEAI, a personal AI assistant with memory capabilities.

IMPORTANT: You have access to the following TOOLS. When appropriate, output a JSON command instead of plain text.

## AVAILABLE TOOLS:

### SAVE_MEMORY
Use this when the user shares personal information, preferences, facts about themselves, or anything worth remembering.
Output format:
\`\`\`json
{"tool": "SAVE_MEMORY", "params": {"content": "the fact to remember", "tags": ["tag1", "tag2"], "category": "personal|work|health|hobby|relationship", "sentiment": "positive|neutral|negative"}}
\`\`\`

### GET_MEMORIES
Use this when the user asks "what do you know about me" or similar.
Output format:
\`\`\`json
{"tool": "GET_MEMORIES", "params": {"limit": 10}}
\`\`\`

## RULES:
1. For casual conversation (greetings, questions, jokes), respond normally with text.
2. When user shares a personal fact like "I love tacos" or "My dog's name is Max", you MUST output ONLY the JSON tool command, nothing else.
3. After the app executes the tool, it will show the user a confirmation message.
4. Keep memories concise and factual.
5. Extract relevant tags and sentiment from the context.

## EXAMPLES:

User: "Hello!"
Response: "Hello! How can I help you today?"

User: "I love hiking on weekends"
Response:
\`\`\`json
{"tool": "SAVE_MEMORY", "params": {"content": "User loves hiking on weekends", "tags": ["hiking", "weekend", "hobby"], "category": "hobby", "sentiment": "positive"}}
\`\`\`

User: "What do you remember about me?"
Response:
\`\`\`json
{"tool": "GET_MEMORIES", "params": {"limit": 10}}
\`\`\`
`;

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
 * Brain Config interface - SIMPLIFIED
 * Core settings stored in config/brain
 * Classifier config is now at config/pipeline/stages/classifier
 */
interface BrainConfig {
  defaultLLM: string;
  temperature: number;
  maxTokens: number;
  memory: {
    saveEnabled: boolean;
    injectEnabled: boolean;
  };
  system: {
    chatEnabled: boolean;
    loggingLevel: string;
  };
  debugMode: boolean;
}

/**
 * Get brain config from Firestore - SIMPLIFIED
 * Core settings only. Classifier is at config/pipeline/stages/classifier
 */
async function getBrainConfig(): Promise<BrainConfig> {
  // Safe defaults
  const defaults: BrainConfig = {
    defaultLLM: 'gemini',
    temperature: 0.7,
    maxTokens: 1024,
    memory: {
      saveEnabled: true,
      injectEnabled: true,
    },
    system: {
      chatEnabled: true,
      loggingLevel: 'info',
    },
    debugMode: false,
  };

  try {
    const doc = await db.doc('config/brain').get();

    if (!doc.exists) {
      console.log('[CONFIG] No config found at config/brain, using defaults');
      return defaults;
    }

    const data = doc.data() || {};
    const memory = data.memory || {};
    const system = data.system || {};

    // Support both new flat structure and legacy nested structure
    let defaultLLM = defaults.defaultLLM;
    let temperature = defaults.temperature;
    let maxTokens = defaults.maxTokens;

    // New flat structure
    if (data.defaultLLM) {
      defaultLLM = data.defaultLLM;
    }
    // Legacy: routing.defaultLLM
    else if (data.routing?.defaultLLM) {
      defaultLLM = data.routing.defaultLLM;
    }

    // New flat structure
    if (data.temperature !== undefined) {
      temperature = data.temperature;
    }
    // Legacy: llm.temperature
    else if (data.llm?.temperature !== undefined) {
      temperature = data.llm.temperature;
    }

    // New flat structure
    if (data.maxTokens !== undefined) {
      maxTokens = data.maxTokens;
    }
    // Legacy: llm.maxTokens
    else if (data.llm?.maxTokens !== undefined) {
      maxTokens = data.llm.maxTokens;
    }

    const config: BrainConfig = {
      defaultLLM,
      temperature,
      maxTokens,
      memory: {
        saveEnabled: memory.saveEnabled ?? defaults.memory.saveEnabled,
        injectEnabled: memory.injectEnabled ?? defaults.memory.injectEnabled,
      },
      system: {
        chatEnabled: system.chatEnabled ?? defaults.system.chatEnabled,
        loggingLevel: system.loggingLevel ?? defaults.system.loggingLevel,
      },
      debugMode: data.debugMode ?? defaults.debugMode,
    };

    console.log(`[CONFIG] Loaded from config/brain: defaultLLM=${config.defaultLLM}, temp=${config.temperature}, chatEnabled=${config.system.chatEnabled}`);
    return config;
  } catch (error) {
    console.error('[CONFIG] Error loading config:', error);
    return defaults;
  }
}

/**
 * Call Gemini
 */
async function callGemini(
  message: string,
  temperature: number,
  maxTokens: number
): Promise<{ text: string; inputTokens: number; outputTokens: number }> {
  const apiKey = await getSecret('gemini-api-key');
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: 'gemini-2.0-flash-exp',
    systemInstruction: SYSTEM_PROMPT,
    generationConfig: {
      temperature,
      maxOutputTokens: maxTokens,
    },
  });

  const result = await model.generateContent(message);
  const response = result.response;

  return {
    text: response.text(),
    inputTokens: response.usageMetadata?.promptTokenCount || 0,
    outputTokens: response.usageMetadata?.candidatesTokenCount || 0,
  };
}

/**
 * Call Claude
 */
async function callClaude(
  message: string,
  maxTokens: number
): Promise<{ text: string; inputTokens: number; outputTokens: number }> {
  const apiKey = await getSecret('anthropic-api-key');
  const anthropic = new Anthropic({ apiKey });

  const response = await anthropic.messages.create({
    model: 'claude-3-haiku-20240307',
    max_tokens: maxTokens,
    system: SYSTEM_PROMPT,
    messages: [{ role: 'user', content: message }],
  });

  const textBlock = response.content.find(block => block.type === 'text');
  const text = textBlock?.type === 'text' ? textBlock.text : '';

  return {
    text,
    inputTokens: response.usage.input_tokens,
    outputTokens: response.usage.output_tokens,
  };
}

/**
 * Call GPT
 */
async function callGPT(
  message: string,
  temperature: number,
  maxTokens: number
): Promise<{ text: string; inputTokens: number; outputTokens: number }> {
  const apiKey = await getSecret('openai-api-key');
  const openai = new OpenAI({ apiKey });

  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    temperature,
    max_tokens: maxTokens,
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: message },
    ],
  });

  return {
    text: response.choices[0]?.message?.content || '',
    inputTokens: response.usage?.prompt_tokens || 0,
    outputTokens: response.usage?.completion_tokens || 0,
  };
}

/**
 * Health check endpoint
 */
export const health = onRequest(async (req: Request, res: Response) => {
  const config = await getBrainConfig();

  res.json({
    status: 'ok',
    project: 'iamoneai',
    version: 'simplified-config',
    configSource: 'config/brain',
    config: {
      defaultLLM: config.defaultLLM,
      temperature: config.temperature,
      maxTokens: config.maxTokens,
      memory: config.memory,
      system: config.system,
      debugMode: config.debugMode,
    },
    classifierSource: 'config/pipeline/stages/classifier',
    timestamp: new Date().toISOString(),
  });
});

/**
 * Chat endpoint - Direct LLM (no memory)
 */
export const chat = onRequest(
  { memory: '512MiB', timeoutSeconds: 120 },
  async (req: Request, res: Response) => {
    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ text: 'Method not allowed' });
      return;
    }

    const { message } = req.body;
    const startTime = Date.now();

    // Validate
    if (!message) {
      res.status(400).json({ text: 'Message is required' });
      return;
    }

    try {
      // Get brain config - SINGLE SOURCE OF TRUTH for all settings
      const config = await getBrainConfig();

      // Get classifier config (from Inference Pipeline)
      const classifierConfig = await getClassifierConfig();

      // Check if chat is enabled (kill switch)
      if (!config.system.chatEnabled) {
        res.json({ text: 'Chat is currently disabled.' });
        return;
      }

      // Preprocess message for classification
      const preprocessed = message.trim().replace(/\s+/g, ' ');

      // Run intent classification (SAME as admin testClassifier endpoint)
      const { scores, matchedKeywords, method } = calculateIntentScores(preprocessed, classifierConfig);

      // Find highest scoring intent
      let detectedIntent = classifierConfig.fallbackIntent;
      let maxConfidence = 0;
      Object.entries(scores).forEach(([intent, score]) => {
        if (score > maxConfidence) {
          maxConfidence = score;
          detectedIntent = intent;
        }
      });

      // Check if confidence meets threshold
      const fallbackUsed = maxConfidence < classifierConfig.minConfidenceThreshold;
      if (fallbackUsed) {
        detectedIntent = classifierConfig.fallbackIntent;
      }

      // Use defaultLLM from config (simplified - no intent-based routing)
      const provider = config.defaultLLM as 'gemini' | 'claude' | 'gpt';
      const routingReason = `defaultLLM → ${provider}`;

      const temperature = config.temperature;
      const maxTokens = config.maxTokens;

      console.log(`[CLASSIFIER] intent=${detectedIntent} confidence=${maxConfidence.toFixed(2)} fallback=${fallbackUsed} keywords=[${matchedKeywords.join(',')}]`);
      console.log(`[ROUTING] ${routingReason}`);
      console.log(`[CHAT] provider=${provider} message="${message.substring(0, 50)}..."`);

      // Call LLM directly using defaultLLM
      let result: { text: string; inputTokens: number; outputTokens: number };

      switch (provider) {
        case 'claude':
          result = await callClaude(message, maxTokens);
          break;
        case 'gpt':
          result = await callGPT(message, temperature, maxTokens);
          break;
        case 'gemini':
        default:
          result = await callGemini(message, temperature, maxTokens);
          break;
      }

      const latencyMs = Date.now() - startTime;
      console.log(`[CHAT] latency=${latencyMs}ms tokens=${result.inputTokens}/${result.outputTokens}`);

      // Run the Decision Pipeline for memory analysis
      const pipelineResult = processDecisionPipeline(message, {
        defaultLLM: config.defaultLLM,
        classifierConfidenceThreshold: classifierConfig.minConfidenceThreshold,
        debugMode: config.debugMode,
        memory: config.memory,
        trust: { provisionalThreshold: 0.5 }, // Configured in Inference Pipeline
      });

      // Use the SAME classifier values for the response (matches admin testClassifier)
      const classifierScore = maxConfidence;
      const classifierDecision = fallbackUsed ? 'fallback' : 'direct';
      const finalIntent = detectedIntent;

      console.log(`[CLASSIFIER] score=${classifierScore} decision=${classifierDecision} intent=${finalIntent}`);
      console.log(`[PIPELINE] outcome=${pipelineResult.pipeline.finalOutcome} stopReason=${pipelineResult.pipeline.stopReason || 'none'} latency=${pipelineResult.pipeline.totalLatencyMs}ms`);

      // ALWAYS return comprehensive debug info
      const response: Record<string, unknown> = {
        text: result.text,
        provider,
        latencyMs,
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
        // Always include execution details
        execution: {
          provider: provider,
          defaultLLM: config.defaultLLM,
          temperature: temperature,
          maxTokens: maxTokens,
          timestamp: new Date().toISOString(),
        },
        // Classifier decision info (matches admin testClassifier format)
        classifier: {
          score: classifierScore,
          decision: classifierDecision,
          finalIntent: finalIntent,
          allScores: scores,
          matchedKeywords: matchedKeywords,
          method: method,
          fallbackUsed: fallbackUsed,
          threshold: classifierConfig.minConfidenceThreshold,
        },
        // Routing decision
        routing: {
          selectedLLM: provider,
          reason: routingReason,
        },
        // Config from config/brain (simplified)
        config: {
          defaultLLM: config.defaultLLM,
          temperature: config.temperature,
          maxTokens: config.maxTokens,
          memory: config.memory,
          system: config.system,
          debugMode: config.debugMode,
        },
        // Include full decision pipeline when debugMode is true
        decisionPipeline: config.debugMode ? pipelineResult.pipeline : undefined,
      };

      res.json(response);

    } catch (error) {
      console.error('[CHAT] Error:', error);
      res.json({ text: "Sorry, I couldn't answer that right now." });
    }
  }
);

/**
 * Input Analysis Config interface
 */
interface InputAnalysisConfig {
  tokenLimitEnabled: boolean;
  maxTokens: number;
  preprocessingEnabled: boolean;
  stripWhitespace: boolean;
  lowercaseNormalize: boolean;
  languageDetectionEnabled: boolean;
  detectedLanguages: string[];
}

/**
 * Get Input Analysis config from Firestore
 */
async function getInputAnalysisConfig(): Promise<InputAnalysisConfig> {
  const defaults: InputAnalysisConfig = {
    tokenLimitEnabled: true,
    maxTokens: 2048,
    preprocessingEnabled: true,
    stripWhitespace: true,
    lowercaseNormalize: false,
    languageDetectionEnabled: true,
    detectedLanguages: ['en', 'es'],
  };

  try {
    const doc = await db.collection('config').doc('pipeline').collection('stages').doc('inputAnalysis').get();

    if (!doc.exists) {
      console.log('[INPUT-ANALYSIS] No config found, using defaults');
      return defaults;
    }

    const data = doc.data() || {};
    return {
      tokenLimitEnabled: data.tokenLimitEnabled ?? defaults.tokenLimitEnabled,
      maxTokens: data.maxTokens ?? defaults.maxTokens,
      preprocessingEnabled: data.preprocessingEnabled ?? defaults.preprocessingEnabled,
      stripWhitespace: data.stripWhitespace ?? defaults.stripWhitespace,
      lowercaseNormalize: data.lowercaseNormalize ?? defaults.lowercaseNormalize,
      languageDetectionEnabled: data.languageDetectionEnabled ?? defaults.languageDetectionEnabled,
      detectedLanguages: data.detectedLanguages ?? defaults.detectedLanguages,
    };
  } catch (error) {
    console.error('[INPUT-ANALYSIS] Error loading config:', error);
    return defaults;
  }
}

/**
 * Simple token count estimation (approximation: 1 token ≈ 4 chars)
 */
function estimateTokenCount(text: string): number {
  return Math.ceil(text.length / 4);
}

/**
 * Detect language using simple heuristics
 */
function detectLanguage(text: string): { code: string; confidence: number } {
  const lowerText = text.toLowerCase();

  // Spanish indicators
  const spanishWords = ['hola', 'como', 'está', 'gracias', 'buenos', 'días', 'qué', 'sí', 'no sé'];
  const spanishCount = spanishWords.filter(w => lowerText.includes(w)).length;

  // French indicators
  const frenchWords = ['bonjour', 'merci', 'comment', 'oui', 'non', 'très', 'bien', "c'est"];
  const frenchCount = frenchWords.filter(w => lowerText.includes(w)).length;

  // German indicators
  const germanWords = ['guten', 'danke', 'bitte', 'ja', 'nein', 'wie', 'ist', 'nicht'];
  const germanCount = germanWords.filter(w => lowerText.includes(w)).length;

  if (spanishCount >= 2) return { code: 'es', confidence: 0.8 };
  if (frenchCount >= 2) return { code: 'fr', confidence: 0.8 };
  if (germanCount >= 2) return { code: 'de', confidence: 0.8 };

  // Default to English
  return { code: 'en', confidence: 0.9 };
}

/**
 * Test Input Analysis endpoint
 * Tests Stage 1 of the Inference Pipeline
 */
export const testInputAnalysis = onRequest(async (req: Request, res: Response) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const { message } = req.body;
  const startTime = Date.now();

  if (!message || typeof message !== 'string') {
    res.status(400).json({ error: 'Message is required' });
    return;
  }

  try {
    // Load configuration
    const config = await getInputAnalysisConfig();
    console.log('[INPUT-ANALYSIS] Config loaded:', JSON.stringify(config));

    // Start analysis
    const analysis: Record<string, unknown> = {
      stage: 'Input Analysis',
      stageNumber: 1,
      input: {
        raw: message,
        length: message.length,
      },
      config: config,
    };

    // Token analysis
    const estimatedTokens = estimateTokenCount(message);
    const tokenLimitExceeded = config.tokenLimitEnabled && estimatedTokens > config.maxTokens;

    analysis.tokens = {
      estimated: estimatedTokens,
      limit: config.maxTokens,
      limitEnabled: config.tokenLimitEnabled,
      exceeded: tokenLimitExceeded,
    };

    // Preprocessing
    let processedText = message;
    const preprocessingSteps: string[] = [];

    if (config.preprocessingEnabled) {
      // Strip outer quotes first
      if ((processedText.startsWith('"') && processedText.endsWith('"')) ||
          (processedText.startsWith("'") && processedText.endsWith("'"))) {
        processedText = processedText.slice(1, -1);
        preprocessingSteps.push('stripQuotes');
      }

      if (config.stripWhitespace) {
        const beforeLength = processedText.length;
        processedText = processedText.replace(/\s+/g, ' ').trim();
        if (processedText.length !== beforeLength) {
          preprocessingSteps.push('stripWhitespace');
        }
      }

      if (config.lowercaseNormalize) {
        processedText = processedText.toLowerCase();
        preprocessingSteps.push('lowercaseNormalize');
      }
    }

    analysis.preprocessing = {
      enabled: config.preprocessingEnabled,
      stepsApplied: preprocessingSteps,
      processed: processedText,
      originalLength: message.length,
      processedLength: processedText.length,
    };

    // Language detection
    if (config.languageDetectionEnabled) {
      const detected = detectLanguage(processedText);
      const isSupported = config.detectedLanguages.includes(detected.code);

      analysis.language = {
        detected: detected.code,
        confidence: detected.confidence,
        supported: isSupported,
        supportedLanguages: config.detectedLanguages,
      };
    } else {
      analysis.language = {
        detectionEnabled: false,
      };
    }

    // Overall validation
    const validationErrors: string[] = [];

    if (tokenLimitExceeded) {
      validationErrors.push(`Token limit exceeded: ${estimatedTokens} > ${config.maxTokens}`);
    }

    // Check processed text for empty content (after quote stripping and whitespace handling)
    if (processedText === '' || processedText === '""' || processedText === "''") {
      validationErrors.push('Empty input after preprocessing');
    }

    analysis.validation = {
      passed: validationErrors.length === 0,
      errors: validationErrors,
    };

    // Timing
    const latencyMs = Date.now() - startTime;
    analysis.latencyMs = latencyMs;
    analysis.timestamp = new Date().toISOString();

    console.log(`[INPUT-ANALYSIS] Completed in ${latencyMs}ms`);
    res.json(analysis);

  } catch (error) {
    console.error('[INPUT-ANALYSIS] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * Classifier Config interface - reads from config/pipeline/stages/classifier
 */
interface ClassifierConfig {
  keywords: {
    code: string[];
    creative: string[];
    factual: string[];
    reasoning: string[];
    casual: string[];
  };
  scoring: {
    baseScorePerKeyword: number;
    multipleKeywordMultiplier: number;
    scoreCap: number;
    confidenceThreshold: number;
    wordBoundaryMatching: boolean;
    defaultCasualScore: number;
  };
  priority: string[];
  fallbackIntent: string;
  // For backwards compatibility with existing code
  minConfidenceThreshold: number;
}

/**
 * Get Classifier config from config/pipeline/stages/classifier
 * Falls back to config/brain.classifier for backwards compatibility
 */
async function getClassifierConfig(): Promise<ClassifierConfig> {
  // Default values
  const defaults: ClassifierConfig = {
    keywords: {
      code: ['python', 'javascript', 'flutter', 'dart', 'code', 'script', 'debug', 'fix', 'error', 'bug', 'api', 'function', 'class', 'method', 'variable', 'sort', 'loop', 'array', 'list', 'database'],
      creative: ['poem', 'story', 'song', 'lyrics', 'compose', 'invent', 'imagine', 'design', 'create', 'artistic'],
      factual: ['what is', 'who is', 'when did', 'where is', 'how many', 'how much', 'define', 'meaning', 'capital of', 'tell me about'],
      reasoning: ['why', 'explain', 'analyze', 'think', 'compare', 'evaluate', 'reason', 'because'],
      casual: ['hello', 'hi', 'hey', 'thanks', 'ok', 'sure', 'bye'],
    },
    scoring: {
      baseScorePerKeyword: 0.25,
      multipleKeywordMultiplier: 1.5,
      scoreCap: 0.95,
      confidenceThreshold: 0.60,
      wordBoundaryMatching: true,
      defaultCasualScore: 0.50,
    },
    priority: ['code', 'reasoning', 'creative', 'factual', 'casual'],
    fallbackIntent: 'casual',
    minConfidenceThreshold: 0.60,
  };

  try {
    // Try new path first: config/pipeline/stages/classifier
    const pipelineDoc = await db.doc('config/pipeline/stages/classifier').get();

    if (pipelineDoc.exists) {
      const data = pipelineDoc.data() || {};
      const keywords = data.keywords || {};
      const scoring = data.scoring || {};

      console.log('[CLASSIFIER] Config loaded from config/pipeline/stages/classifier');
      return {
        keywords: {
          code: keywords.code ?? defaults.keywords.code,
          creative: keywords.creative ?? defaults.keywords.creative,
          factual: keywords.factual ?? defaults.keywords.factual,
          reasoning: keywords.reasoning ?? defaults.keywords.reasoning,
          casual: keywords.casual ?? defaults.keywords.casual,
        },
        scoring: {
          baseScorePerKeyword: scoring.baseScorePerKeyword ?? defaults.scoring.baseScorePerKeyword,
          multipleKeywordMultiplier: scoring.multipleKeywordMultiplier ?? defaults.scoring.multipleKeywordMultiplier,
          scoreCap: scoring.scoreCap ?? defaults.scoring.scoreCap,
          confidenceThreshold: scoring.confidenceThreshold ?? defaults.scoring.confidenceThreshold,
          wordBoundaryMatching: scoring.wordBoundaryMatching ?? defaults.scoring.wordBoundaryMatching,
          defaultCasualScore: scoring.defaultCasualScore ?? defaults.scoring.defaultCasualScore,
        },
        priority: data.priority ?? defaults.priority,
        fallbackIntent: data.fallbackIntent ?? defaults.fallbackIntent,
        minConfidenceThreshold: scoring.confidenceThreshold ?? defaults.scoring.confidenceThreshold,
      };
    }

    // No classifier config found - use defaults
    console.log('[CLASSIFIER] No config found, using defaults');
    return defaults;
  } catch (error) {
    console.error('[CLASSIFIER] Error loading config:', error);
    return defaults;
  }
}

/**
 * Calculate intent scores based on keyword matching
 * Uses config-driven keywords and scoring formula:
 * - 1 keyword:  baseScore × 1 = baseScore
 * - 2+ keywords: baseScore × count × multiplier (capped at scoreCap)
 *
 * Word boundary matching (when enabled) prevents partial matches:
 * - "hi" won't match "physics" or "thinking"
 * - Uses regex \b word boundaries
 */
function calculateIntentScores(
  text: string,
  config: ClassifierConfig
): { scores: Record<string, number>; matchedKeywords: string[]; method: string } {
  const lowerText = text.toLowerCase();
  const matchedKeywords: string[] = [];
  const scores: Record<string, number> = {
    code: 0,
    creative: 0,
    factual: 0,
    reasoning: 0,
    casual: 0,
  };

  const { baseScorePerKeyword, multipleKeywordMultiplier, scoreCap, wordBoundaryMatching, defaultCasualScore } = config.scoring;

  // Helper function to check if keyword matches
  const keywordMatches = (keyword: string, text: string): boolean => {
    const lowerKeyword = keyword.toLowerCase();
    if (wordBoundaryMatching) {
      // Use word boundary matching to prevent partial matches
      // e.g., "hi" won't match "physics" or "thinking"
      const regex = new RegExp(`\\b${lowerKeyword.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i');
      return regex.test(text);
    } else {
      // Simple substring matching (original behavior)
      return text.includes(lowerKeyword);
    }
  };

  // Helper function to calculate score from matches
  const calculateScore = (matches: string[]): number => {
    if (matches.length === 0) return 0;
    if (matches.length === 1) return baseScorePerKeyword;
    // Multiple keywords: baseScore × count × multiplier, capped
    return Math.min(scoreCap, baseScorePerKeyword * matches.length * multipleKeywordMultiplier);
  };

  // Check each intent's keywords from config
  const intentKeywords: Record<string, string[]> = {
    code: config.keywords.code,
    creative: config.keywords.creative,
    factual: config.keywords.factual,
    reasoning: config.keywords.reasoning,
    casual: config.keywords.casual,
  };

  Object.entries(intentKeywords).forEach(([intent, keywords]) => {
    const matches = keywords.filter(kw => keywordMatches(kw, lowerText));
    if (matches.length > 0) {
      matchedKeywords.push(...matches.map(m => `${intent}:${m}`));
      scores[intent] = calculateScore(matches);
    }
  });

  // If no keywords matched, use defaultCasualScore
  const maxScore = Math.max(...Object.values(scores));
  if (maxScore === 0) {
    scores.casual = defaultCasualScore;
  }

  return {
    scores,
    matchedKeywords,
    method: wordBoundaryMatching ? 'keyword-boundary' : 'keyword-substring',
  };
}

/**
 * Test Classifier endpoint
 * Tests Stage 2 of the Inference Pipeline
 */
export const testClassifier = onRequest(async (req: Request, res: Response) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const { message } = req.body;
  const startTime = Date.now();

  if (!message || typeof message !== 'string') {
    res.status(400).json({ error: 'Message is required' });
    return;
  }

  try {
    // Load configurations
    const classifierConfig = await getClassifierConfig();
    const brainConfig = await getBrainConfig();
    console.log('[CLASSIFIER] Config loaded from config/brain.routing');

    // Preprocess text (simple for now)
    const preprocessed = message.trim().replace(/\s+/g, ' ');

    // Calculate intent scores
    const { scores, matchedKeywords, method } = calculateIntentScores(preprocessed, classifierConfig);

    // Find highest scoring intent
    let detectedIntent = classifierConfig.fallbackIntent;
    let maxConfidence = 0;

    Object.entries(scores).forEach(([intent, score]) => {
      if (score > maxConfidence) {
        maxConfidence = score;
        detectedIntent = intent;
      }
    });

    // Check if confidence meets threshold
    const fallbackUsed = maxConfidence < classifierConfig.minConfidenceThreshold;
    if (fallbackUsed) {
      detectedIntent = classifierConfig.fallbackIntent;
    }

    // Build response
    const processingTime = Date.now() - startTime;

    const result = {
      stage: 'Classifier',
      stageNumber: 2,
      input: {
        text: message,
        preprocessed: preprocessed,
        language: 'en',
      },
      classification: {
        detectedIntent,
        confidence: maxConfidence,
        allScores: scores,
        method,
        matchedKeywords,
        fallbackUsed,
        threshold: classifierConfig.minConfidenceThreshold,
      },
      routing: {
        selectedLLM: brainConfig.defaultLLM,
        reason: 'Uses defaultLLM from config/brain',
      },
      config: {
        classifierSource: 'config/pipeline/stages/classifier',
        brainSource: 'config/brain',
        defaultLLM: brainConfig.defaultLLM,
        scoring: classifierConfig.scoring,
        priority: classifierConfig.priority,
        fallbackIntent: classifierConfig.fallbackIntent,
        keywordCounts: {
          code: classifierConfig.keywords.code.length,
          creative: classifierConfig.keywords.creative.length,
          factual: classifierConfig.keywords.factual.length,
          reasoning: classifierConfig.keywords.reasoning.length,
          casual: classifierConfig.keywords.casual.length,
        },
      },
      processingTime: `${processingTime}ms`,
      timestamp: new Date().toISOString(),
    };

    console.log(`[CLASSIFIER] intent=${detectedIntent} confidence=${maxConfidence.toFixed(2)} time=${processingTime}ms`);
    res.json(result);

  } catch (error) {
    console.error('[CLASSIFIER] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ═══════════════════════════════════════════════════════════
// STAGE 3: CONFIDENCE GATE
// ═══════════════════════════════════════════════════════════

export { testConfidenceGate } from './stages/confidenceGate';

// ═══════════════════════════════════════════════════════════
// STAGE 4: INTENT RESOLUTION
// ═══════════════════════════════════════════════════════════

export { testIntentResolution } from './stages/intentResolution';

// ═══════════════════════════════════════════════════════════
// STAGE 5: MEMORY QUERY
// ═══════════════════════════════════════════════════════════

export { testMemoryQuery } from './stages/memoryQuery';

// ═══════════════════════════════════════════════════════════
// STAGE 6: MEMORY EXTRACTION
// ═══════════════════════════════════════════════════════════

export { testMemoryExtraction } from './stages/memoryExtraction';

// ═══════════════════════════════════════════════════════════
// STAGE 7: CURIOSITY MODULE
// ═══════════════════════════════════════════════════════════

export { testCuriosityModule } from './stages/curiosityModule';

// ═══════════════════════════════════════════════════════════
// STAGE 8: TRUST EVALUATION
// ═══════════════════════════════════════════════════════════

export { testTrustEvaluation } from './stages/trustEvaluation';

// ═══════════════════════════════════════════════════════════
// STAGE 9: SAVE DECISION
// ═══════════════════════════════════════════════════════════

export { testSaveDecision } from './stages/saveDecision';

// ═══════════════════════════════════════════════════════════
// STAGE 10: CONTEXT INJECTION
// ═══════════════════════════════════════════════════════════

export { testContextInjection } from './stages/contextInjection';

// ═══════════════════════════════════════════════════════════
// STAGE 11: LLM RESPONSE
// ═══════════════════════════════════════════════════════════

export { testLLMResponse } from './stages/llmResponse';

// ═══════════════════════════════════════════════════════════
// STAGE 12: POST-RESPONSE LOG
// ═══════════════════════════════════════════════════════════

export { testPostResponseLog } from './stages/postResponseLog';

// ═══════════════════════════════════════════════════════════
// PIPELINE ORCHESTRATOR
// ═══════════════════════════════════════════════════════════

export { pipelineChat, pipelineChatDebug } from './pipeline/orchestrator';

// ═══════════════════════════════════════════════════════════
// NIGHTLY COMPRESSION & CLEANUP
// ═══════════════════════════════════════════════════════════

export {
  nightlyCompression,
  triggerCompression,
  weeklyCleanup,
  triggerCleanup,
} from './stages/compression';

// ═══════════════════════════════════════════════════════════
// SAVE MEMORY CARD ENDPOINT
// ═══════════════════════════════════════════════════════════

/**
 * Save a completed memory card from Generative UI
 * POST body: { iin: string, card: MemoryCard }
 */
export const saveMemoryCard = onRequest(
  { memory: '256MiB', timeoutSeconds: 30 },
  async (req: Request, res: Response) => {
    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ success: false, error: 'Method not allowed' });
      return;
    }

    const { iin, card } = req.body;

    // Validate input
    if (!iin || typeof iin !== 'string') {
      res.status(400).json({ success: false, error: 'IIN is required' });
      return;
    }

    if (!card || typeof card !== 'object') {
      res.status(400).json({ success: false, error: 'Card is required' });
      return;
    }

    const { type, slots, title } = card;

    if (!type || !slots) {
      res.status(400).json({ success: false, error: 'Card type and slots are required' });
      return;
    }

    try {
      console.log(`[SAVE-CARD] Saving ${type} card for IIN: ${iin}`);
      console.log(`[SAVE-CARD] Title: ${title || 'untitled'}`);

      // Build memory document from card slots
      const slotData: Record<string, unknown> = {};
      for (const [slotId, slotValue] of Object.entries(slots)) {
        const sv = slotValue as { value?: unknown; filled?: boolean };
        if (sv.filled && sv.value !== undefined && sv.value !== null) {
          slotData[slotId] = sv.value;
        }
      }

      // Create memory document
      const memoryDoc = {
        iin,
        type,
        source: 'generative_ui',
        title: title || `${type} memory`,
        data: slotData,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        status: 'active',
        confidence: 1.0, // User-confirmed data has high confidence
        tempId: card.tempId || null,
      };

      // Save to Firestore (correct nested path: memories/{iin}/items/{memoryId})
      const docRef = await db.collection('memories').doc(iin).collection('items').add(memoryDoc);

      console.log(`[SAVE-CARD] ✅ Saved memory: ${docRef.id}`);

      res.json({
        success: true,
        memoryId: docRef.id,
        type,
        timestamp: new Date().toISOString(),
      });

    } catch (error) {
      console.error('[SAVE-CARD] Error:', error);
      res.status(500).json({
        success: false,
        error: 'Failed to save memory card',
      });
    }
  }
);

// ═══════════════════════════════════════════════════════════
// UPDATE MEMORY ENDPOINT (Inline Edit)
// ═══════════════════════════════════════════════════════════

/**
 * Update an existing memory's slots (for inline edit)
 * POST body: { iin: string, memoryId: string, updates: { slots?: Record<string, any>, ... } }
 */
export const updateMemory = onRequest(
  { memory: '256MiB', timeoutSeconds: 30 },
  async (req: Request, res: Response) => {
    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ success: false, error: 'Method not allowed' });
      return;
    }

    const { iin, memoryId, updates } = req.body;

    // Validate input
    if (!iin || typeof iin !== 'string') {
      res.status(400).json({ success: false, error: 'IIN is required' });
      return;
    }

    if (!memoryId || typeof memoryId !== 'string') {
      res.status(400).json({ success: false, error: 'memoryId is required' });
      return;
    }

    if (!updates || typeof updates !== 'object') {
      res.status(400).json({ success: false, error: 'updates object is required' });
      return;
    }

    try {
      console.log(`[UPDATE-MEMORY] Updating ${memoryId} for IIN: ${iin}`);

      const memoryRef = db.collection('memories').doc(iin).collection('items').doc(memoryId);

      // Check if memory exists
      const memoryDoc = await memoryRef.get();
      if (!memoryDoc.exists) {
        res.status(404).json({ success: false, error: 'Memory not found' });
        return;
      }

      // Build update object - only allow certain fields to be updated
      const allowedFields = ['slots', 'content', 'title', 'data'];
      const sanitizedUpdates: Record<string, unknown> = {};

      for (const field of allowedFields) {
        if (updates[field] !== undefined) {
          sanitizedUpdates[field] = updates[field];
        }
      }

      // Always update the timestamp
      sanitizedUpdates.updatedAt = admin.firestore.FieldValue.serverTimestamp();

      await memoryRef.update(sanitizedUpdates);

      console.log(`[UPDATE-MEMORY] ✅ Updated memory: ${memoryId}`);

      res.json({
        success: true,
        memoryId,
        timestamp: new Date().toISOString(),
      });

    } catch (error) {
      console.error('[UPDATE-MEMORY] Error:', error);
      res.status(500).json({
        success: false,
        error: 'Failed to update memory',
      });
    }
  }
);

// ═══════════════════════════════════════════════════════════
// SAVE SELECTED MEMORIES ENDPOINT (Selection Grid)
// ═══════════════════════════════════════════════════════════

/**
 * Save selected memories from a Selection Grid action
 * POST body: { iin: string, actionId: string, selectedIds: string[], memories: SelectionItem[] }
 */
export const saveSelectedMemories = onRequest(
  { memory: '256MiB', timeoutSeconds: 30 },
  async (req: Request, res: Response) => {
    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ success: false, error: 'Method not allowed' });
      return;
    }

    const { iin, actionId, selectedIds, memories } = req.body;

    // Validate input
    if (!iin || typeof iin !== 'string') {
      res.status(400).json({ success: false, error: 'IIN is required' });
      return;
    }

    if (!selectedIds || !Array.isArray(selectedIds)) {
      res.status(400).json({ success: false, error: 'selectedIds array is required' });
      return;
    }

    if (!memories || !Array.isArray(memories)) {
      res.status(400).json({ success: false, error: 'memories array is required' });
      return;
    }

    try {
      console.log(`[SAVE-SELECTED] Processing ${selectedIds.length} selected memories for IIN: ${iin}`);

      const savedMemories: Array<{ id: string; type: string }> = [];
      const batch = db.batch();

      // Filter to only selected items
      const selectedMemories = memories.filter((m: any) => selectedIds.includes(m.id));

      for (const item of selectedMemories) {
        const memoryData = item.memory || {};
        const docRef = db.collection('memories').doc(iin).collection('items').doc();

        batch.set(docRef, {
          id: docRef.id,
          iin,
          type: memoryData.type || item.type || 'fact',
          content: memoryData.content || item.label || '',
          slots: memoryData.slots || {},
          source: 'selection_grid',
          status: 'active',
          tier: 'working',
          relevance: 0.9,
          context: 'personal',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          selectionGridActionId: actionId,
        });

        savedMemories.push({ id: docRef.id, type: memoryData.type || item.type });
      }

      await batch.commit();

      console.log(`[SAVE-SELECTED] ✅ Saved ${savedMemories.length} memories`);

      res.json({
        success: true,
        savedCount: savedMemories.length,
        savedMemories,
        skippedCount: memories.length - selectedMemories.length,
        timestamp: new Date().toISOString(),
      });

    } catch (error) {
      console.error('[SAVE-SELECTED] Error:', error);
      res.status(500).json({
        success: false,
        error: 'Failed to save selected memories',
      });
    }
  }
);

// ═══════════════════════════════════════════════════════════
// RESOLVE CONFLICT ENDPOINT (Conflict Resolver)
// ═══════════════════════════════════════════════════════════

/**
 * Resolve a memory conflict from a Conflict Resolver action
 * POST body: { iin: string, actionId: string, choice: 'keep_old' | 'update', oldMemoryId: string, newValue?: any }
 */
export const resolveConflict = onRequest(
  { memory: '256MiB', timeoutSeconds: 30 },
  async (req: Request, res: Response) => {
    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ success: false, error: 'Method not allowed' });
      return;
    }

    const { iin, actionId, choice, oldMemoryId, newValue, field } = req.body;

    // Validate input
    if (!iin || typeof iin !== 'string') {
      res.status(400).json({ success: false, error: 'IIN is required' });
      return;
    }

    if (!choice || !['keep_old', 'update'].includes(choice)) {
      res.status(400).json({ success: false, error: 'choice must be "keep_old" or "update"' });
      return;
    }

    if (!oldMemoryId) {
      res.status(400).json({ success: false, error: 'oldMemoryId is required' });
      return;
    }

    try {
      console.log(`[RESOLVE-CONFLICT] Processing conflict resolution for IIN: ${iin}, choice: ${choice}`);

      const memoryRef = db.collection('memories').doc(iin).collection('items').doc(oldMemoryId);
      const memoryDoc = await memoryRef.get();

      if (!memoryDoc.exists) {
        res.status(404).json({ success: false, error: 'Original memory not found' });
        return;
      }

      let result: any = { choice };

      if (choice === 'keep_old') {
        // User chose to keep the old value - no changes needed
        result.action = 'kept_existing';
        result.message = 'Kept existing memory value';
        console.log(`[RESOLVE-CONFLICT] ✅ Keeping old value`);
      } else if (choice === 'update') {
        // User chose to update - update the memory with new value
        const updateData: Record<string, any> = {
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          conflictResolvedAt: admin.firestore.FieldValue.serverTimestamp(),
          conflictActionId: actionId,
        };

        // Update the specific field if provided
        if (field && newValue !== undefined) {
          updateData[`data.${field}`] = newValue;
          updateData.content = String(newValue);
        } else if (newValue !== undefined) {
          updateData.content = String(newValue);
        }

        await memoryRef.update(updateData);

        result.action = 'updated';
        result.message = 'Updated memory with new value';
        result.memoryId = oldMemoryId;
        console.log(`[RESOLVE-CONFLICT] ✅ Updated memory: ${oldMemoryId}`);
      }

      res.json({
        success: true,
        ...result,
        timestamp: new Date().toISOString(),
      });

    } catch (error) {
      console.error('[RESOLVE-CONFLICT] Error:', error);
      res.status(500).json({
        success: false,
        error: 'Failed to resolve conflict',
      });
    }
  }
);

// ═══════════════════════════════════════════════════════════
// SAVE RELATIONSHIPS ENDPOINT (Relationship Graph)
// ═══════════════════════════════════════════════════════════

/**
 * Save relationships from a Relationship Graph action
 * POST body: { iin: string, actionId: string, connections: RelationshipConnection[] }
 */
export const saveRelationships = onRequest(
  { memory: '256MiB', timeoutSeconds: 30 },
  async (req: Request, res: Response) => {
    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ success: false, error: 'Method not allowed' });
      return;
    }

    const { iin, actionId, connections } = req.body;

    // Validate input
    if (!iin || typeof iin !== 'string') {
      res.status(400).json({ success: false, error: 'IIN is required' });
      return;
    }

    if (!connections || !Array.isArray(connections)) {
      res.status(400).json({ success: false, error: 'connections array is required' });
      return;
    }

    try {
      console.log(`[SAVE-RELATIONSHIPS] Processing ${connections.length} connections for IIN: ${iin}`);

      const savedRelationships: Array<{ id: string; to: string; relationship: string }> = [];
      const batch = db.batch();

      for (const conn of connections) {
        const docRef = db.collection('memories').doc(iin).collection('items').doc();

        // Build content string
        const content = `User's ${conn.relationship}: ${conn.to}${conn.metadata?.location ? ` (lives in ${conn.metadata.location})` : ''}`;

        batch.set(docRef, {
          id: docRef.id,
          iin,
          type: 'relationship',
          content,
          slots: {
            person_name: { value: conn.to, filled: true },
            relationship_type: { value: conn.relationship, filled: true },
            location: conn.metadata?.location ? { value: conn.metadata.location, filled: true } : { value: null, filled: false },
          },
          source: 'relationship_graph',
          status: 'active',
          tier: 'working',
          relevance: 0.9,
          context: 'personal',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          relationshipGraphActionId: actionId,
        });

        savedRelationships.push({
          id: docRef.id,
          to: conn.to,
          relationship: conn.relationship,
        });
      }

      await batch.commit();

      console.log(`[SAVE-RELATIONSHIPS] ✅ Saved ${savedRelationships.length} relationships`);

      res.json({
        success: true,
        savedCount: savedRelationships.length,
        savedRelationships,
        timestamp: new Date().toISOString(),
      });

    } catch (error) {
      console.error('[SAVE-RELATIONSHIPS] Error:', error);
      res.status(500).json({
        success: false,
        error: 'Failed to save relationships',
      });
    }
  }
);

// ═══════════════════════════════════════════════════════════
// GET MEMORY DETAILS ENDPOINT (Timeline)
// ═══════════════════════════════════════════════════════════

/**
 * Get memory details for timeline event
 * POST body: { iin: string, memoryId: string }
 */
export const getMemoryDetails = onRequest(
  { memory: '256MiB', timeoutSeconds: 30 },
  async (req: Request, res: Response) => {
    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ success: false, error: 'Method not allowed' });
      return;
    }

    const { iin, memoryId } = req.body;

    // Validate input
    if (!iin || typeof iin !== 'string') {
      res.status(400).json({ success: false, error: 'IIN is required' });
      return;
    }

    if (!memoryId || typeof memoryId !== 'string') {
      res.status(400).json({ success: false, error: 'memoryId is required' });
      return;
    }

    try {
      console.log(`[GET-MEMORY-DETAILS] Fetching memory ${memoryId} for IIN: ${iin}`);

      const memoryRef = db.collection('memories').doc(iin).collection('items').doc(memoryId);
      const memoryDoc = await memoryRef.get();

      if (!memoryDoc.exists) {
        res.status(404).json({ success: false, error: 'Memory not found' });
        return;
      }

      const data = memoryDoc.data();
      const createdAt = data?.createdAt?.toDate?.()?.toISOString() || null;
      const updatedAt = data?.updatedAt?.toDate?.()?.toISOString() || null;

      console.log(`[GET-MEMORY-DETAILS] ✅ Found memory: ${memoryId}`);

      res.json({
        success: true,
        memory: {
          id: memoryDoc.id,
          type: data?.type || 'unknown',
          content: data?.content || '',
          slots: data?.slots || {},
          tier: data?.tier || 'working',
          status: data?.status || 'active',
          context: data?.context || 'personal',
          createdAt,
          updatedAt,
        },
      });

    } catch (error) {
      console.error('[GET-MEMORY-DETAILS] Error:', error);
      res.status(500).json({
        success: false,
        error: 'Failed to get memory details',
      });
    }
  }
);

// ═══════════════════════════════════════════════════════════
// LOG ACTION INTERACTION ENDPOINT (Analytics)
// ═══════════════════════════════════════════════════════════

/**
 * Log action interaction for analytics
 * POST body: { iin: string, actionId: string, actionType: string, interaction: string, metadata?: object, timestamp?: string }
 */
export const logActionInteraction = onRequest(
  { memory: '256MiB', timeoutSeconds: 30 },
  async (req: Request, res: Response) => {
    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ success: false, error: 'Method not allowed' });
      return;
    }

    const { iin, actionId, actionType, interaction, metadata, timestamp } = req.body;

    // Validate input
    if (!iin || typeof iin !== 'string') {
      res.status(400).json({ success: false, error: 'IIN is required' });
      return;
    }

    if (!actionId || typeof actionId !== 'string') {
      res.status(400).json({ success: false, error: 'actionId is required' });
      return;
    }

    if (!actionType || typeof actionType !== 'string') {
      res.status(400).json({ success: false, error: 'actionType is required' });
      return;
    }

    if (!interaction || typeof interaction !== 'string') {
      res.status(400).json({ success: false, error: 'interaction is required' });
      return;
    }

    try {
      console.log(`[LOG-INTERACTION] ${actionType} - ${interaction} for IIN: ${iin}`);

      await db.collection('analytics').doc('generativeUI').collection('interactions').add({
        iin,
        actionId,
        actionType,
        interaction,
        metadata: metadata || {},
        timestamp: timestamp || new Date().toISOString(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[LOG-INTERACTION] ✅ Logged interaction`);

      res.json({
        success: true,
        timestamp: new Date().toISOString(),
      });

    } catch (error) {
      // Silent fail for analytics - still return success to not block UI
      console.error('[LOG-INTERACTION] Error (silent):', error);
      res.json({
        success: true,
        note: 'Analytics logging failed silently',
      });
    }
  }
);

// ═══════════════════════════════════════════════════════════
// GET GENERATIVE UI ANALYTICS ENDPOINT (Admin)
// ═══════════════════════════════════════════════════════════

/**
 * Get Generative UI analytics for admin dashboard
 * POST body: { startDate?: string, endDate?: string }
 */
export const getGenerativeUIAnalytics = onRequest(
  { memory: '256MiB', timeoutSeconds: 60 },
  async (req: Request, res: Response) => {
    // CORS
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ success: false, error: 'Method not allowed' });
      return;
    }

    const { startDate, endDate } = req.body;

    try {
      console.log(`[ANALYTICS] Fetching Generative UI analytics`);

      // Query interactions
      let query = db.collection('analytics').doc('generativeUI').collection('interactions')
        .orderBy('createdAt', 'desc')
        .limit(10000);

      const snapshot = await query.get();

      // Aggregate by action type
      const byActionType: Record<string, { total: number; completed: number; dismissed: number; errors: number }> = {};

      for (const doc of snapshot.docs) {
        const data = doc.data();

        // Filter by date range if provided
        if (startDate || endDate) {
          const docTimestamp = data.timestamp;
          if (startDate && docTimestamp < startDate) continue;
          if (endDate && docTimestamp > endDate) continue;
        }

        const actionType = data.actionType || 'unknown';

        if (!byActionType[actionType]) {
          byActionType[actionType] = { total: 0, completed: 0, dismissed: 0, errors: 0 };
        }

        byActionType[actionType].total++;

        switch (data.interaction) {
          case 'completed':
          case 'save':
          case 'submit':
          case 'confirm':
          case 'update':
          case 'keep_old':
            byActionType[actionType].completed++;
            break;
          case 'dismissed':
          case 'cancel':
          case 'delete':
            byActionType[actionType].dismissed++;
            break;
          case 'error':
            byActionType[actionType].errors++;
            break;
        }
      }

      // Calculate completion rates
      const analytics = Object.entries(byActionType).map(([type, stats]) => ({
        actionType: type,
        ...stats,
        completionRate: stats.total > 0 ? Math.round((stats.completed / stats.total) * 100) : 0,
      }));

      console.log(`[ANALYTICS] ✅ Found ${snapshot.size} interactions`);

      res.json({
        success: true,
        totalInteractions: snapshot.size,
        byActionType: analytics,
        dateRange: { startDate, endDate },
      });

    } catch (error) {
      console.error('[ANALYTICS] Error:', error);
      res.status(500).json({
        success: false,
        error: 'Failed to get analytics',
      });
    }
  }
);
