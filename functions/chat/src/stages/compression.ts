import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onRequest } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import { GoogleGenerativeAI } from '@google/generative-ai';

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
// TYPES
// ═══════════════════════════════════════════════════════════

interface CompressionConfig {
  enabled: boolean;
  runTime: string;
  timezone: string;
  minMessagesToCompress: number;
  maxSummaryTokens: number;
  retentionDays: number;
  rawLogRetentionDays: number;
  llm: {
    provider: string;
    model: string;
    temperature: number;
    maxTokens: number;
  };
  prompts: {
    summarize: string;
    extractTopics: string;
  };
  logLevel: string;
}

interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: admin.firestore.Timestamp;
  compressed: boolean;
  sessionId: string;
}

interface DailySummary {
  id: string;
  date: admin.firestore.Timestamp;
  content: string;
  messageCount: number;
  topics: string[];
  sessionIds: string[];
  tokenCount: number;
  createdAt: admin.firestore.Timestamp;
}

interface CompressionResult {
  iin: string;
  date: string;
  messagesProcessed: number;
  summaryCreated: boolean;
  summary?: string;
  topics?: string[];
  skipped: boolean;
  skipReason?: string;
  error?: string;
}

interface CompressionJobResult {
  success: boolean;
  date: string;
  usersProcessed: number;
  summariesCreated: number;
  messagesCompressed: number;
  errors: number;
  details: CompressionResult[];
  duration: number;
}

// ═══════════════════════════════════════════════════════════
// CONFIG LOADER
// ═══════════════════════════════════════════════════════════

async function getCompressionConfig(): Promise<CompressionConfig> {
  const defaults: CompressionConfig = {
    enabled: true,
    runTime: '03:00',
    timezone: 'America/New_York',
    minMessagesToCompress: 10,
    maxSummaryTokens: 150,
    retentionDays: 90,
    rawLogRetentionDays: 30,
    llm: {
      provider: 'gemini',
      model: 'gemini-2.0-flash-exp',
      temperature: 0.3,
      maxTokens: 200,
    },
    prompts: {
      summarize: `Summarize this conversation into 2-3 sentences.
Focus on: decisions made, preferences expressed, tasks discussed, important facts shared.
Ignore: greetings, small talk, clarification back-and-forth.

Transcript:
{{transcript}}

Summary:`,
      extractTopics: `Extract 3-5 topic keywords from this conversation summary.
Return as a JSON array of lowercase strings.

Summary: {{summary}}

Topics (JSON array):`,
    },
    logLevel: 'info',
  };

  try {
    const doc = await db.collection('config').doc('scheduled')
      .collection('jobs').doc('nightly_compression').get();

    if (!doc.exists) {
      console.log('[Compression] No config found, using defaults');
      return defaults;
    }

    const data = doc.data() || {};
    return {
      enabled: data.enabled ?? defaults.enabled,
      runTime: data.runTime ?? defaults.runTime,
      timezone: data.timezone ?? defaults.timezone,
      minMessagesToCompress: data.minMessagesToCompress ?? defaults.minMessagesToCompress,
      maxSummaryTokens: data.maxSummaryTokens ?? defaults.maxSummaryTokens,
      retentionDays: data.retentionDays ?? defaults.retentionDays,
      rawLogRetentionDays: data.rawLogRetentionDays ?? defaults.rawLogRetentionDays,
      llm: {
        provider: data.llm?.provider ?? defaults.llm.provider,
        model: data.llm?.model ?? defaults.llm.model,
        temperature: data.llm?.temperature ?? defaults.llm.temperature,
        maxTokens: data.llm?.maxTokens ?? defaults.llm.maxTokens,
      },
      prompts: {
        summarize: data.prompts?.summarize ?? defaults.prompts.summarize,
        extractTopics: data.prompts?.extractTopics ?? defaults.prompts.extractTopics,
      },
      logLevel: data.logLevel ?? defaults.logLevel,
    };
  } catch (error) {
    console.error('[Compression] Error loading config:', error);
    return defaults;
  }
}

// ═══════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════

function getYesterdayDateRange(): { start: Date; end: Date; dateKey: string } {
  const now = new Date();
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);

  const start = new Date(yesterday);
  start.setHours(0, 0, 0, 0);

  const end = new Date(yesterday);
  end.setHours(23, 59, 59, 999);

  const dateKey = yesterday.toISOString().split('T')[0]; // YYYY-MM-DD

  return { start, end, dateKey };
}

function getDateRange(dateKey: string): { start: Date; end: Date } {
  const date = new Date(dateKey);
  const start = new Date(date);
  start.setHours(0, 0, 0, 0);

  const end = new Date(date);
  end.setHours(23, 59, 59, 999);

  return { start, end };
}

function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}

// ═══════════════════════════════════════════════════════════
// LLM FUNCTIONS
// ═══════════════════════════════════════════════════════════

async function generateSummary(
  transcript: string,
  config: CompressionConfig
): Promise<string> {
  const apiKey = await getSecret('gemini-api-key');
  if (!apiKey) {
    throw new Error('No Gemini API key available');
  }

  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({
    model: config.llm.model,
    generationConfig: {
      temperature: config.llm.temperature,
      maxOutputTokens: config.llm.maxTokens,
    },
  });

  const prompt = config.prompts.summarize.replace('{{transcript}}', transcript);
  const result = await model.generateContent(prompt);
  return result.response.text().trim();
}

async function extractTopics(
  summary: string,
  config: CompressionConfig
): Promise<string[]> {
  try {
    const apiKey = await getSecret('gemini-api-key');
    if (!apiKey) {
      return [];
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
      model: config.llm.model,
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 100,
      },
    });

    const prompt = config.prompts.extractTopics.replace('{{summary}}', summary);
    const result = await model.generateContent(prompt);
    const text = result.response.text().trim();

    // Parse JSON array
    const match = text.match(/\[[\s\S]*\]/);
    if (match) {
      const parsed = JSON.parse(match[0]);
      if (Array.isArray(parsed)) {
        return parsed.map(t => String(t).toLowerCase().trim()).slice(0, 5);
      }
    }
    return [];
  } catch (error) {
    console.error('[Compression] Topic extraction failed:', error);
    return [];
  }
}

// ═══════════════════════════════════════════════════════════
// CORE COMPRESSION LOGIC
// ═══════════════════════════════════════════════════════════

/**
 * Get all IINs that had chat activity on a specific date
 */
async function getActiveIINs(dateKey: string): Promise<string[]> {
  const { start, end } = getDateRange(dateKey);

  // Query chat_logs collection to find active IINs
  // Structure: chat_logs/{iin}/{sessionId}/messages/{messageId}
  const iins: Set<string> = new Set();

  try {
    // Get all IIN documents
    const iinDocs = await db.collection('chat_logs').listDocuments();

    for (const iinDoc of iinDocs) {
      // Check if this IIN has uncompressed messages from the target date
      const sessionsSnapshot = await iinDoc.listCollections();

      for (const sessionRef of sessionsSnapshot) {
        const messagesQuery = await sessionRef
          .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(start))
          .where('timestamp', '<=', admin.firestore.Timestamp.fromDate(end))
          .where('compressed', '==', false)
          .limit(1)
          .get();

        if (!messagesQuery.empty) {
          iins.add(iinDoc.id);
          break; // Found activity, move to next IIN
        }
      }
    }
  } catch (error) {
    console.error('[Compression] Error fetching active IINs:', error);
  }

  return Array.from(iins);
}

/**
 * Get uncompressed messages for a specific IIN and date
 */
async function getUncompressedMessages(
  iin: string,
  dateKey: string
): Promise<{ messages: ChatMessage[]; sessionIds: string[] }> {
  const { start, end } = getDateRange(dateKey);
  const messages: ChatMessage[] = [];
  const sessionIds: Set<string> = new Set();

  try {
    const iinRef = db.collection('chat_logs').doc(iin);
    const sessionsSnapshot = await iinRef.listCollections();

    for (const sessionRef of sessionsSnapshot) {
      const messagesQuery = await sessionRef
        .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(start))
        .where('timestamp', '<=', admin.firestore.Timestamp.fromDate(end))
        .where('compressed', '==', false)
        .orderBy('timestamp', 'asc')
        .get();

      for (const doc of messagesQuery.docs) {
        const data = doc.data();
        messages.push({
          id: doc.id,
          role: data.role as 'user' | 'assistant',
          content: data.content,
          timestamp: data.timestamp,
          compressed: data.compressed || false,
          sessionId: sessionRef.id,
        });
        sessionIds.add(sessionRef.id);
      }
    }
  } catch (error) {
    console.error(`[Compression] Error fetching messages for ${iin}:`, error);
  }

  // Sort all messages by timestamp
  messages.sort((a, b) => a.timestamp.toMillis() - b.timestamp.toMillis());

  return { messages, sessionIds: Array.from(sessionIds) };
}

/**
 * Build transcript from messages
 */
function buildTranscript(messages: ChatMessage[]): string {
  return messages.map(m =>
    `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`
  ).join('\n');
}

/**
 * Mark messages as compressed
 */
async function markMessagesCompressed(
  iin: string,
  messages: ChatMessage[]
): Promise<void> {
  const batch = db.batch();
  let batchCount = 0;
  const MAX_BATCH_SIZE = 500;

  for (const msg of messages) {
    const msgRef = db.collection('chat_logs').doc(iin)
      .collection(msg.sessionId).doc(msg.id);
    batch.update(msgRef, { compressed: true });
    batchCount++;

    // Firestore has a limit of 500 operations per batch
    if (batchCount >= MAX_BATCH_SIZE) {
      await batch.commit();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }
}

/**
 * Save summary to Firestore
 */
async function saveSummary(
  iin: string,
  dateKey: string,
  summary: string,
  messageCount: number,
  topics: string[],
  sessionIds: string[]
): Promise<void> {
  const summaryDoc: Omit<DailySummary, 'id'> = {
    date: admin.firestore.Timestamp.fromDate(new Date(dateKey)),
    content: summary,
    messageCount,
    topics,
    sessionIds,
    tokenCount: estimateTokens(summary),
    createdAt: admin.firestore.Timestamp.now(),
  };

  await db.collection('memories').doc(iin)
    .collection('summaries').doc(dateKey)
    .set(summaryDoc);
}

/**
 * Compress messages for a single IIN
 */
async function compressUserMessages(
  iin: string,
  dateKey: string,
  config: CompressionConfig
): Promise<CompressionResult> {
  const result: CompressionResult = {
    iin,
    date: dateKey,
    messagesProcessed: 0,
    summaryCreated: false,
    skipped: false,
  };

  try {
    // Get uncompressed messages
    const { messages, sessionIds } = await getUncompressedMessages(iin, dateKey);
    result.messagesProcessed = messages.length;

    // Check minimum message count
    if (messages.length < config.minMessagesToCompress) {
      result.skipped = true;
      result.skipReason = `Only ${messages.length} messages (minimum: ${config.minMessagesToCompress})`;

      // Still mark as compressed to avoid reprocessing
      if (messages.length > 0) {
        await markMessagesCompressed(iin, messages);
      }

      return result;
    }

    // Build transcript
    const transcript = buildTranscript(messages);

    // Generate summary
    const summary = await generateSummary(transcript, config);
    result.summary = summary;

    // Extract topics
    const topics = await extractTopics(summary, config);
    result.topics = topics;

    // Save summary
    await saveSummary(iin, dateKey, summary, messages.length, topics, sessionIds);
    result.summaryCreated = true;

    // Mark messages as compressed
    await markMessagesCompressed(iin, messages);

    console.log(`[Compression] ✅ ${iin}: ${messages.length} messages → "${summary.substring(0, 50)}..."`);

  } catch (error: any) {
    result.error = error.message || 'Unknown error';
    console.error(`[Compression] ❌ ${iin}:`, error);
  }

  return result;
}

/**
 * Main compression job logic
 */
async function runCompressionJob(
  targetDate?: string
): Promise<CompressionJobResult> {
  const startTime = Date.now();
  const config = await getCompressionConfig();

  if (!config.enabled) {
    console.log('[Compression] Job is disabled');
    return {
      success: false,
      date: targetDate || 'N/A',
      usersProcessed: 0,
      summariesCreated: 0,
      messagesCompressed: 0,
      errors: 0,
      details: [],
      duration: Date.now() - startTime,
    };
  }

  // Determine target date
  const dateKey = targetDate || getYesterdayDateRange().dateKey;
  console.log(`[Compression] Starting job for date: ${dateKey}`);

  // Get active IINs
  const activeIINs = await getActiveIINs(dateKey);
  console.log(`[Compression] Found ${activeIINs.length} active users`);

  // Process each IIN
  const details: CompressionResult[] = [];
  let summariesCreated = 0;
  let messagesCompressed = 0;
  let errors = 0;

  for (const iin of activeIINs) {
    const result = await compressUserMessages(iin, dateKey, config);
    details.push(result);

    if (result.summaryCreated) summariesCreated++;
    if (result.error) errors++;
    messagesCompressed += result.messagesProcessed;
  }

  const duration = Date.now() - startTime;

  // Log summary
  console.log(`[Compression] ═══════════════════════════════════════════════`);
  console.log(`[Compression] Job Complete - ${dateKey}`);
  console.log(`[Compression] Users processed: ${activeIINs.length}`);
  console.log(`[Compression] Summaries created: ${summariesCreated}`);
  console.log(`[Compression] Messages compressed: ${messagesCompressed}`);
  console.log(`[Compression] Errors: ${errors}`);
  console.log(`[Compression] Duration: ${duration}ms`);
  console.log(`[Compression] ═══════════════════════════════════════════════`);

  return {
    success: errors === 0,
    date: dateKey,
    usersProcessed: activeIINs.length,
    summariesCreated,
    messagesCompressed,
    errors,
    details,
    duration,
  };
}

// ═══════════════════════════════════════════════════════════
// SCHEDULED FUNCTION: NIGHTLY COMPRESSION
// Runs at 3am daily (configurable via Firestore)
// ═══════════════════════════════════════════════════════════

export const nightlyCompression = onSchedule(
  {
    schedule: '0 3 * * *', // 3am daily
    timeZone: 'America/New_York',
    memory: '1GiB',
    timeoutSeconds: 540, // 9 minutes
  },
  async (_event) => {
    console.log('[Compression] Starting scheduled nightly compression');
    await runCompressionJob();
  }
);

// ═══════════════════════════════════════════════════════════
// HTTP ENDPOINT: MANUAL TRIGGER
// For testing without waiting for scheduled time
// ═══════════════════════════════════════════════════════════

export const triggerCompression = onRequest(
  { memory: '1GiB', timeoutSeconds: 540 },
  async (req, res) => {
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

    try {
      const { iin, date } = req.body;

      console.log(`[Compression] Manual trigger: iin=${iin || 'all'}, date=${date || 'yesterday'}`);

      if (iin) {
        // Single user compression
        const config = await getCompressionConfig();
        const dateKey = date || getYesterdayDateRange().dateKey;
        const result = await compressUserMessages(iin, dateKey, config);

        res.json({
          success: !result.error,
          result,
        });
      } else {
        // Full compression job
        const result = await runCompressionJob(date);
        res.json(result);
      }
    } catch (error: any) {
      console.error('[Compression] Manual trigger error:', error);
      res.status(500).json({
        error: error.message || 'Internal server error',
      });
    }
  }
);

// ═══════════════════════════════════════════════════════════
// SCHEDULED FUNCTION: WEEKLY CLEANUP
// Runs at 4am on Sundays
// ═══════════════════════════════════════════════════════════

interface CleanupConfig {
  enabled: boolean;
  deleteSummariesOlderThan: number;
  deleteRawLogsOlderThan: number;
  deleteAnalyticsOlderThan: number;
  requireCompressedBeforeDelete: boolean;
  dryRun: boolean;
  logLevel: string;
}

async function getCleanupConfig(): Promise<CleanupConfig> {
  const defaults: CleanupConfig = {
    enabled: true,
    deleteSummariesOlderThan: 90,
    deleteRawLogsOlderThan: 30,
    deleteAnalyticsOlderThan: 365,
    requireCompressedBeforeDelete: true,
    dryRun: false,
    logLevel: 'info',
  };

  try {
    const doc = await db.collection('config').doc('scheduled')
      .collection('jobs').doc('weekly_cleanup').get();

    if (!doc.exists) return defaults;

    const data = doc.data() || {};
    return {
      enabled: data.enabled ?? defaults.enabled,
      deleteSummariesOlderThan: data.deleteSummariesOlderThan ?? defaults.deleteSummariesOlderThan,
      deleteRawLogsOlderThan: data.deleteRawLogsOlderThan ?? defaults.deleteRawLogsOlderThan,
      deleteAnalyticsOlderThan: data.deleteAnalyticsOlderThan ?? defaults.deleteAnalyticsOlderThan,
      requireCompressedBeforeDelete: data.requireCompressedBeforeDelete ?? defaults.requireCompressedBeforeDelete,
      dryRun: data.dryRun ?? defaults.dryRun,
      logLevel: data.logLevel ?? defaults.logLevel,
    };
  } catch (error) {
    console.error('[Cleanup] Error loading config:', error);
    return defaults;
  }
}

async function runCleanupJob(): Promise<{
  success: boolean;
  summariesDeleted: number;
  rawLogsDeleted: number;
  analyticsDeleted: number;
  errors: string[];
  dryRun: boolean;
  duration: number;
}> {
  const startTime = Date.now();
  const config = await getCleanupConfig();

  const result = {
    success: true,
    summariesDeleted: 0,
    rawLogsDeleted: 0,
    analyticsDeleted: 0,
    errors: [] as string[],
    dryRun: config.dryRun,
    duration: 0,
  };

  if (!config.enabled) {
    console.log('[Cleanup] Job is disabled');
    result.duration = Date.now() - startTime;
    return result;
  }

  console.log(`[Cleanup] Starting weekly cleanup (dryRun: ${config.dryRun})`);

  // Calculate cutoff dates
  const now = new Date();
  const summaryCutoff = new Date(now);
  summaryCutoff.setDate(summaryCutoff.getDate() - config.deleteSummariesOlderThan);

  const rawLogCutoff = new Date(now);
  rawLogCutoff.setDate(rawLogCutoff.getDate() - config.deleteRawLogsOlderThan);

  // 1. Delete old summaries
  try {
    // For each user's summaries collection
    const memoriesDocs = await db.collection('memories').listDocuments();

    for (const memoryDoc of memoriesDocs) {
      const summariesQuery = await memoryDoc.collection('summaries')
        .where('date', '<', admin.firestore.Timestamp.fromDate(summaryCutoff))
        .get();

      for (const doc of summariesQuery.docs) {
        if (!config.dryRun) {
          await doc.ref.delete();
        }
        result.summariesDeleted++;
      }
    }
  } catch (error: any) {
    result.errors.push(`Summary cleanup: ${error.message}`);
    result.success = false;
  }

  // 2. Delete old compressed chat logs
  try {
    const chatLogsDocs = await db.collection('chat_logs').listDocuments();

    for (const iinDoc of chatLogsDocs) {
      const sessionsSnapshot = await iinDoc.listCollections();

      for (const sessionRef of sessionsSnapshot) {
        // Only delete if all messages are compressed
        let query = sessionRef
          .where('timestamp', '<', admin.firestore.Timestamp.fromDate(rawLogCutoff));

        if (config.requireCompressedBeforeDelete) {
          query = query.where('compressed', '==', true);
        }

        const messagesQuery = await query.get();

        for (const doc of messagesQuery.docs) {
          if (!config.dryRun) {
            await doc.ref.delete();
          }
          result.rawLogsDeleted++;
        }
      }
    }
  } catch (error: any) {
    result.errors.push(`Raw log cleanup: ${error.message}`);
    result.success = false;
  }

  result.duration = Date.now() - startTime;

  console.log(`[Cleanup] ═══════════════════════════════════════════════`);
  console.log(`[Cleanup] Job Complete ${config.dryRun ? '(DRY RUN)' : ''}`);
  console.log(`[Cleanup] Summaries deleted: ${result.summariesDeleted}`);
  console.log(`[Cleanup] Raw logs deleted: ${result.rawLogsDeleted}`);
  console.log(`[Cleanup] Errors: ${result.errors.length}`);
  console.log(`[Cleanup] Duration: ${result.duration}ms`);
  console.log(`[Cleanup] ═══════════════════════════════════════════════`);

  return result;
}

export const weeklyCleanup = onSchedule(
  {
    schedule: '0 4 * * 0', // 4am Sundays
    timeZone: 'America/New_York',
    memory: '512MiB',
    timeoutSeconds: 300,
  },
  async (_event) => {
    console.log('[Cleanup] Starting scheduled weekly cleanup');
    await runCleanupJob();
  }
);

// HTTP endpoint for manual cleanup trigger
export const triggerCleanup = onRequest(
  { memory: '512MiB', timeoutSeconds: 300 },
  async (req, res) => {
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

    try {
      const result = await runCleanupJob();
      res.json(result);
    } catch (error: any) {
      console.error('[Cleanup] Manual trigger error:', error);
      res.status(500).json({ error: error.message || 'Internal server error' });
    }
  }
);

// ═══════════════════════════════════════════════════════════
// SUMMARY RETRIEVAL (for Context Injection)
// ═══════════════════════════════════════════════════════════

/**
 * Get recent summaries for a user (for Context Injection Layer 2)
 */
export async function getRecentSummaries(
  iin: string,
  limit: number = 7
): Promise<DailySummary[]> {
  try {
    const query = await db.collection('memories').doc(iin)
      .collection('summaries')
      .orderBy('date', 'desc')
      .limit(limit)
      .get();

    return query.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
    } as DailySummary));
  } catch (error) {
    console.error('[Compression] Error fetching summaries:', error);
    return [];
  }
}

/**
 * Format summaries for context injection
 */
export function formatSummariesForContext(
  summaries: DailySummary[]
): string {
  if (summaries.length === 0) {
    return '';
  }

  const lines = summaries.map(s => {
    const dateStr = s.date.toDate().toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
    });
    return `${dateStr}: ${s.content}`;
  });

  return `PAST CONVERSATIONS:\n${lines.join('\n')}`;
}

// Export for Context Injection
export { runCompressionJob };
