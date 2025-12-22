// IAMONEAI - Conflict Check Stage (Stage ⑥.5)
// Config stored at: config/pipeline/stages/conflict_check
//
// PURPOSE: Detect conflicts between newly extracted memories and existing memories
// FLOW: Memory Extraction (⑥) → Conflict Check (⑥.5) → Curiosity Module (⑦)
//
// If conflict detected:
//   - Flag memory for clarification
//   - Curiosity Module will ask user to resolve
// If no conflict:
//   - Memory proceeds to Save Decision (⑨)

import * as admin from 'firebase-admin';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import { GoogleGenerativeAI } from '@google/generative-ai';

const db = admin.firestore();
const secretManager = new SecretManagerServiceClient();

// Secret cache
const secretCache: Record<string, string> = {};

// ═══════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════

type ConflictType = 'CONFLICT' | 'UPDATE' | 'ADDITION' | 'DUPLICATE' | 'NONE';

interface ConflictCheckConfig {
  enabled: boolean;
  stageNumber: number;
  stageName: string;
  similarity: {
    threshold: number;
    algorithm: 'keyword' | 'semantic' | 'hybrid';
    maxCandidates: number;
  };
  llm: {
    provider: string;
    model: string;
    temperature: number;
    maxTokens: number;
  };
  categories: string[];
  behavior: {
    autoResolveUpdates: boolean;
    skipDuplicates: boolean;
    askForAllConflicts: boolean;
    logAllChecks: boolean;
  };
  promptTemplate: string;
}

interface ExtractedMemory {
  tempId: string;
  content: string;
  type: string;
  confidence: number;
  slots?: Record<string, any>;
  typeConfig?: any;
  complete?: boolean;
  missingRequired?: string[];
}

interface ExistingMemory {
  id: string;
  content: string;
  type: string;
  slots?: Record<string, any>;
  created_at?: any;
  updated_at?: any;
}

interface ConflictResult {
  hasConflict: boolean;
  conflictType: ConflictType;
  confidence: number;
  reason: string;
  existingMemory: ExistingMemory | null;
  extractedMemory: ExtractedMemory;
  needsClarification: boolean;
  autoResolved: boolean;
}

interface ConflictCheckInput {
  iin: string;
  extractedMemories: ExtractedMemory[];
}

interface ConflictCheckOutput {
  checked: number;
  conflicts: ConflictResult[];
  pendingClarifications: ConflictResult[];
  autoResolved: ConflictResult[];
  clean: ExtractedMemory[];  // Memories with no conflicts
  config: {
    enabled: boolean;
    threshold: number;
    algorithm: string;
  };
  processingTime: string;
}

// ═══════════════════════════════════════════════════════════
// CONFIG LOADER
// ═══════════════════════════════════════════════════════════

async function getConflictCheckConfig(): Promise<ConflictCheckConfig> {
  const doc = await db.collection('config').doc('pipeline')
    .collection('stages').doc('conflict_check').get();

  const data = doc.data() ?? {};

  return {
    enabled: data.enabled ?? true,
    stageNumber: data.stageNumber ?? 6.5,
    stageName: data.stageName ?? 'Conflict Check',
    similarity: {
      threshold: data.similarity?.threshold ?? 0.75,
      algorithm: data.similarity?.algorithm ?? 'keyword',
      maxCandidates: data.similarity?.maxCandidates ?? 10,
    },
    llm: {
      provider: data.llm?.provider ?? 'gemini',
      model: data.llm?.model ?? 'gemini-2.0-flash-exp',
      temperature: data.llm?.temperature ?? 0.2,
      maxTokens: data.llm?.maxTokens ?? 200,
    },
    categories: data.categories ?? ['location', 'job', 'relationship', 'name', 'preference'],
    behavior: {
      autoResolveUpdates: data.behavior?.autoResolveUpdates ?? false,
      skipDuplicates: data.behavior?.skipDuplicates ?? true,
      askForAllConflicts: data.behavior?.askForAllConflicts ?? true,
      logAllChecks: data.behavior?.logAllChecks ?? true,
    },
    promptTemplate: data.promptTemplate ?? getDefaultPrompt(),
  };
}

function getDefaultPrompt(): string {
  return `You are analyzing whether two pieces of information about a user conflict.

EXISTING MEMORY: {{existing}}
NEW INFORMATION: {{new}}

Determine the relationship between these. Respond with exactly one of:
- CONFLICT: They directly contradict each other
- UPDATE: The new info is a temporal update to old info
- ADDITION: They can both be true simultaneously
- DUPLICATE: They express the same information

Respond in JSON format:
{
  "type": "CONFLICT|UPDATE|ADDITION|DUPLICATE",
  "confidence": 0.0-1.0,
  "reason": "Brief explanation"
}`;
}

// ═══════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════

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
 * Calculate keyword-based similarity between two strings
 */
function calculateKeywordSimilarity(text1: string, text2: string): number {
  const normalize = (s: string) => s.toLowerCase().replace(/[^\w\s]/g, '');

  const words1 = new Set(normalize(text1).split(/\s+/).filter(w => w.length > 2));
  const words2 = new Set(normalize(text2).split(/\s+/).filter(w => w.length > 2));

  if (words1.size === 0 || words2.size === 0) return 0;

  let overlap = 0;
  words1.forEach(word => {
    if (words2.has(word)) overlap++;
  });

  // Jaccard similarity
  const union = new Set([...words1, ...words2]);
  return overlap / union.size;
}

/**
 * Check if memory type matches any conflict category
 */
function matchesConflictCategory(memoryType: string, content: string, categories: string[]): boolean {
  const lowerContent = content.toLowerCase();
  const lowerType = memoryType.toLowerCase();

  // Direct type match
  if (categories.includes(lowerType)) return true;

  // Content-based category detection
  const categoryKeywords: Record<string, string[]> = {
    location: ['live', 'lives', 'living', 'moved', 'from', 'city', 'country', 'address', 'home'],
    job: ['work', 'works', 'job', 'career', 'company', 'employed', 'position', 'role', 'occupation'],
    relationship: ['married', 'wife', 'husband', 'partner', 'girlfriend', 'boyfriend', 'dating', 'single', 'divorced'],
    name: ['name', 'called', 'known as', 'nickname'],
    preference: ['like', 'love', 'hate', 'prefer', 'favorite', 'dislike', 'enjoy'],
    personal_info: ['age', 'birthday', 'born', 'years old', 'height', 'weight'],
  };

  for (const category of categories) {
    const keywords = categoryKeywords[category] || [];
    if (keywords.some(kw => lowerContent.includes(kw))) {
      return true;
    }
  }

  return false;
}

/**
 * Fetch existing memories for a user
 */
async function getExistingMemories(iin: string, maxCount: number): Promise<ExistingMemory[]> {
  try {
    const snapshot = await db.collection('memories').doc(iin)
      .collection('items')
      .where('status', '==', 'active')
      .orderBy('created_at', 'desc')
      .limit(maxCount)
      .get();

    return snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
    } as ExistingMemory));
  } catch (error) {
    console.error('[CONFLICT-CHECK] Error fetching existing memories:', error);
    return [];
  }
}

/**
 * Find candidate memories that might conflict with extracted memory
 */
function findCandidates(
  extracted: ExtractedMemory,
  existingMemories: ExistingMemory[],
  config: ConflictCheckConfig
): ExistingMemory[] {
  const candidates: { memory: ExistingMemory; score: number }[] = [];

  for (const existing of existingMemories) {
    // Skip if different types and not in conflict categories
    if (extracted.type !== existing.type) {
      if (!matchesConflictCategory(extracted.type, extracted.content, config.categories)) {
        continue;
      }
    }

    // Calculate similarity
    const similarity = calculateKeywordSimilarity(extracted.content, existing.content);

    if (similarity >= config.similarity.threshold * 0.5) { // Use half threshold for candidates
      candidates.push({ memory: existing, score: similarity });
    }
  }

  // Sort by similarity score and return top candidates
  candidates.sort((a, b) => b.score - a.score);
  return candidates.slice(0, config.similarity.maxCandidates).map(c => c.memory);
}

/**
 * Use LLM to determine conflict type
 */
async function determineConflictType(
  extracted: ExtractedMemory,
  existing: ExistingMemory,
  config: ConflictCheckConfig
): Promise<{ type: ConflictType; confidence: number; reason: string }> {
  try {
    const apiKey = await getSecret('gemini-api-key');
    if (!apiKey) {
      console.error('[CONFLICT-CHECK] No API key found');
      return { type: 'NONE', confidence: 0, reason: 'API key not available' };
    }

    // Build prompt
    const prompt = config.promptTemplate
      .replace('{{existing}}', existing.content)
      .replace('{{new}}', extracted.content);

    // Call Gemini
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
      model: config.llm.model,
      generationConfig: {
        temperature: config.llm.temperature,
        maxOutputTokens: config.llm.maxTokens,
      },
    });

    const result = await model.generateContent(prompt);
    const responseText = result.response.text();

    // Parse JSON response
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      console.warn('[CONFLICT-CHECK] Could not parse LLM response');
      return { type: 'NONE', confidence: 0.5, reason: 'Could not parse response' };
    }

    const parsed = JSON.parse(jsonMatch[0]);
    const conflictType = (['CONFLICT', 'UPDATE', 'ADDITION', 'DUPLICATE'].includes(parsed.type))
      ? parsed.type as ConflictType
      : 'NONE';

    return {
      type: conflictType,
      confidence: parsed.confidence ?? 0.8,
      reason: parsed.reason ?? 'LLM determined',
    };

  } catch (error: any) {
    console.error('[CONFLICT-CHECK] LLM error:', error.message);
    return { type: 'NONE', confidence: 0, reason: `LLM error: ${error.message}` };
  }
}

// ═══════════════════════════════════════════════════════════
// MAIN CONFLICT CHECK FUNCTION
// ═══════════════════════════════════════════════════════════

async function checkConflicts(input: ConflictCheckInput): Promise<ConflictCheckOutput> {
  const startTime = Date.now();
  const config = await getConflictCheckConfig();

  console.log(`[CONFLICT-CHECK] Starting check for ${input.extractedMemories.length} memories`);

  // If disabled, pass through all memories
  if (!config.enabled) {
    console.log('[CONFLICT-CHECK] Stage disabled, passing through');
    return {
      checked: 0,
      conflicts: [],
      pendingClarifications: [],
      autoResolved: [],
      clean: input.extractedMemories,
      config: {
        enabled: false,
        threshold: config.similarity.threshold,
        algorithm: config.similarity.algorithm,
      },
      processingTime: `${Date.now() - startTime}ms`,
    };
  }

  // Fetch existing memories
  const existingMemories = await getExistingMemories(input.iin, 100);
  console.log(`[CONFLICT-CHECK] Found ${existingMemories.length} existing memories`);

  if (existingMemories.length === 0) {
    // No existing memories, no possible conflicts
    return {
      checked: input.extractedMemories.length,
      conflicts: [],
      pendingClarifications: [],
      autoResolved: [],
      clean: input.extractedMemories,
      config: {
        enabled: true,
        threshold: config.similarity.threshold,
        algorithm: config.similarity.algorithm,
      },
      processingTime: `${Date.now() - startTime}ms`,
    };
  }

  const conflicts: ConflictResult[] = [];
  const pendingClarifications: ConflictResult[] = [];
  const autoResolved: ConflictResult[] = [];
  const clean: ExtractedMemory[] = [];

  // Check each extracted memory
  for (const extracted of input.extractedMemories) {
    // Find candidate memories that might conflict
    const candidates = findCandidates(extracted, existingMemories, config);

    if (candidates.length === 0) {
      // No similar memories found
      clean.push(extracted);
      if (config.behavior.logAllChecks) {
        console.log(`[CONFLICT-CHECK] No candidates for "${extracted.content.substring(0, 50)}..."`);
      }
      continue;
    }

    // Check each candidate for conflicts
    let foundConflict = false;
    for (const candidate of candidates) {
      const similarity = calculateKeywordSimilarity(extracted.content, candidate.content);

      if (similarity < config.similarity.threshold) {
        continue;
      }

      // Use LLM to determine conflict type
      const { type, confidence, reason } = await determineConflictType(extracted, candidate, config);

      console.log(`[CONFLICT-CHECK] "${extracted.content.substring(0, 30)}..." vs "${candidate.content.substring(0, 30)}..." = ${type} (${confidence})`);

      if (type === 'NONE' || type === 'ADDITION') {
        // Not a conflict, memory can coexist
        continue;
      }

      const conflictResult: ConflictResult = {
        hasConflict: true,
        conflictType: type,
        confidence,
        reason,
        existingMemory: candidate,
        extractedMemory: extracted,
        needsClarification: false,
        autoResolved: false,
      };

      if (type === 'DUPLICATE') {
        if (config.behavior.skipDuplicates) {
          conflictResult.autoResolved = true;
          conflictResult.reason = 'Duplicate detected, skipping';
          autoResolved.push(conflictResult);
          foundConflict = true;
          break;
        }
      }

      if (type === 'UPDATE') {
        if (config.behavior.autoResolveUpdates) {
          conflictResult.autoResolved = true;
          conflictResult.reason = 'Auto-resolved as update';
          autoResolved.push(conflictResult);
          foundConflict = true;
          break;
        }
      }

      if (type === 'CONFLICT' || !conflictResult.autoResolved) {
        conflictResult.needsClarification = true;
        pendingClarifications.push(conflictResult);
        foundConflict = true;
        break;
      }

      conflicts.push(conflictResult);
      foundConflict = true;
      break;
    }

    if (!foundConflict) {
      clean.push(extracted);
    }
  }

  const result: ConflictCheckOutput = {
    checked: input.extractedMemories.length,
    conflicts,
    pendingClarifications,
    autoResolved,
    clean,
    config: {
      enabled: true,
      threshold: config.similarity.threshold,
      algorithm: config.similarity.algorithm,
    },
    processingTime: `${Date.now() - startTime}ms`,
  };

  console.log(`[CONFLICT-CHECK] Complete: ${pendingClarifications.length} need clarification, ${autoResolved.length} auto-resolved, ${clean.length} clean`);

  return result;
}

// ═══════════════════════════════════════════════════════════
// EXPORTS
// ═══════════════════════════════════════════════════════════

export {
  checkConflicts,
  getConflictCheckConfig,
  ConflictCheckInput,
  ConflictCheckOutput,
  ConflictResult,
  ConflictType,
};
