// Setup Firestore config for Nightly Compression Job
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

async function setupCompression() {
  console.log('Setting up Nightly Compression config...\n');

  // ═══════════════════════════════════════════════════════════
  // PART A: SUMMARIES COLLECTION SCHEMA (for reference)
  // Path: memories/{iin}/summaries/{YYYY-MM-DD}
  // ═══════════════════════════════════════════════════════════

  console.log('═══════════════════════════════════════════════════════════');
  console.log('Summaries Collection Schema (memories/{iin}/summaries/{date}):');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(JSON.stringify({
    id: 'YYYY-MM-DD',
    date: 'Timestamp',
    content: 'User discussed vacation plans for Miami. Asked about best restaurants. Mentioned preference for seafood.',
    messageCount: 25,
    topics: ['travel', 'miami', 'food'],
    sessionIds: ['session_abc123', 'session_def456'],
    tokenCount: 45,
    createdAt: 'Timestamp',
  }, null, 2));

  // ═══════════════════════════════════════════════════════════
  // PART B: CHAT LOG SCHEMA (for reference)
  // Path: chat_logs/{iin}/{sessionId}/messages/{messageId}
  // ═══════════════════════════════════════════════════════════

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Chat Log Schema (chat_logs/{iin}/{sessionId}/messages/{msgId}):');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(JSON.stringify({
    role: 'user | assistant',
    content: 'The message content',
    timestamp: 'Timestamp',
    compressed: false,
  }, null, 2));

  // ═══════════════════════════════════════════════════════════
  // PART F: CONFIG DOCUMENT
  // Path: config/scheduled/nightly_compression
  // ═══════════════════════════════════════════════════════════

  const compressionConfigRef = db.collection('config').doc('scheduled')
    .collection('jobs').doc('nightly_compression');

  const compressionConfig = {
    enabled: true,
    runTime: '03:00',              // 3am
    timezone: 'America/New_York',  // Adjust as needed

    // Compression settings
    minMessagesToCompress: 10,     // Skip if fewer messages
    maxSummaryTokens: 150,         // Max tokens for summary

    // Retention
    retentionDays: 90,             // Keep summaries for 90 days
    rawLogRetentionDays: 30,       // Keep raw logs for 30 days after compression

    // LLM settings for summarization
    llm: {
      provider: 'gemini',
      model: 'gemini-2.0-flash-exp',
      temperature: 0.3,
      maxTokens: 200,
    },

    // Summary prompt template
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

    // Logging
    logLevel: 'info',  // 'none' | 'error' | 'info' | 'debug'

    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await compressionConfigRef.set(compressionConfig);
  console.log('\n✓ Created config/scheduled/jobs/nightly_compression');

  // ═══════════════════════════════════════════════════════════
  // PART G: WEEKLY CLEANUP CONFIG
  // Path: config/scheduled/weekly_cleanup
  // ═══════════════════════════════════════════════════════════

  const cleanupConfigRef = db.collection('config').doc('scheduled')
    .collection('jobs').doc('weekly_cleanup');

  const cleanupConfig = {
    enabled: true,
    runTime: '04:00',              // 4am Sundays
    timezone: 'America/New_York',

    // Cleanup rules
    deleteSummariesOlderThan: 90,      // Days
    deleteRawLogsOlderThan: 30,        // Days (only if compressed)
    deleteAnalyticsOlderThan: 365,     // Days

    // Safety
    requireCompressedBeforeDelete: true, // Never delete uncompressed logs
    dryRun: false,                       // Set true to test without deleting

    // Logging
    logLevel: 'info',

    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await cleanupConfigRef.set(cleanupConfig);
  console.log('✓ Created config/scheduled/jobs/weekly_cleanup');

  // ═══════════════════════════════════════════════════════════
  // Print final config
  // ═══════════════════════════════════════════════════════════

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Nightly Compression Config:');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(JSON.stringify(compressionConfig, null, 2));

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Weekly Cleanup Config:');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(JSON.stringify(cleanupConfig, null, 2));
}

setupCompression()
  .then(() => {
    console.log('\n✓ Compression setup complete!');
    process.exit(0);
  })
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
