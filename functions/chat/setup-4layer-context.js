// Setup Firestore config for Stage ⑩ 4-Layer Context Injection
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

async function setup4LayerContext() {
  console.log('Setting up 4-Layer Context Injection config...\n');

  const configRef = db.collection('config').doc('pipeline').collection('stages').doc('context_injection');

  // Get existing config to preserve non-layer settings
  const existingDoc = await configRef.get();
  const existingData = existingDoc.data() || {};

  const config = {
    // Preserve existing settings
    ...existingData,

    // ═══════════════════════════════════════════════════════════
    // 4-LAYER CONTEXT SYSTEM
    // ═══════════════════════════════════════════════════════════

    layers: {
      // Layer 1: IMMEDIATE (Last N messages)
      immediate: {
        enabled: true,
        maxMessages: 10,
        tokenBudget: 400,
        format: 'conversation',  // 'conversation' | 'summary' | 'json'
      },

      // Layer 2: SESSION SUMMARY (For long conversations)
      sessionSummary: {
        enabled: true,
        threshold: 20,          // Trigger summary if session > 20 messages
        summarizeCount: 15,     // Summarize first 15 messages
        tokenBudget: 200,
        cacheEnabled: true,     // Cache summaries to avoid re-generating
        cacheTTLMinutes: 30,    // Cache TTL
      },

      // Layer 3: USER PROFILE (Memories from Firestore)
      profile: {
        enabled: true,
        maxMemories: 10,
        tokenBudget: 300,
        queryMethod: 'semantic', // 'semantic' | 'keyword' | 'hybrid'
        includeTypes: ['fact', 'preference', 'relationship', 'goal'],
        excludeTypes: ['note', 'event'],  // Events go in Layer 4
      },

      // Layer 4: CALENDAR (Upcoming events)
      calendar: {
        enabled: true,
        lookaheadHours: 48,
        tokenBudget: 100,
        maxEvents: 10,
        format: 'list',         // 'list' | 'prose' | 'json'
      },
    },

    // Token management
    tokens: {
      maxTotalContextTokens: 1500,
      trimOrder: ['immediate', 'sessionSummary', 'profile', 'calendar'],  // Trim in this order
      reserveResponseTokens: 1000,
      estimationMethod: 'chars_divided_by_4',
    },

    // Prompt structure
    promptStructure: {
      systemPromptTemplate: `You are IAmOneAI, a personal AI guardian for {{userName}}.

You have access to the user's profile, recent conversation, and upcoming events.
Use this context to provide personalized, helpful responses.
Be warm, conversational, and reference what you know when relevant.`,

      sectionHeaders: {
        profile: 'USER PROFILE:',
        calendar: 'UPCOMING EVENTS:',
        sessionSummary: 'SESSION CONTEXT:',
        immediate: 'RECENT CONVERSATION:',
      },

      // Section order in the final prompt
      sectionOrder: ['profile', 'calendar', 'sessionSummary', 'immediate'],
    },

    // LLM for session summary generation
    summaryLLM: {
      provider: 'gemini',
      model: 'gemini-2.0-flash-exp',
      temperature: 0.3,
      maxTokens: 200,
      prompt: `Summarize the following conversation in 2-3 sentences, focusing on:
1. What topics were discussed
2. Any decisions or conclusions reached
3. Important facts mentioned

Conversation:
{{messages}}

Summary:`,
    },

    // Debug logging
    debug: {
      logLayerTokens: true,
      logAssembly: true,
      logTrimming: true,
    },

    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await configRef.set(config, { merge: true });
  console.log('Updated config/pipeline/stages/context_injection');
  console.log('\n4-Layer Config:');
  console.log(JSON.stringify(config.layers, null, 2));
  console.log('\nToken Config:');
  console.log(JSON.stringify(config.tokens, null, 2));
}

setup4LayerContext()
  .then(() => {
    console.log('\nSetup complete!');
    process.exit(0);
  })
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
