// Setup Firestore config for Stage ⑥.5 Conflict Check
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

async function setupConflictCheck() {
  console.log('Setting up Conflict Check stage config...\n');

  const configRef = db.collection('config').doc('pipeline').collection('stages').doc('conflict_check');

  const config = {
    enabled: true,
    stageNumber: 6.5,
    stageName: 'Conflict Check',

    // Similarity settings
    similarity: {
      threshold: 0.75,           // Min similarity to consider a match
      algorithm: 'keyword',      // 'keyword' | 'semantic' | 'hybrid'
      maxCandidates: 10,         // Max memories to compare against
    },

    // LLM settings for conflict determination
    llm: {
      provider: 'gemini',
      model: 'gemini-2.0-flash-exp',
      temperature: 0.2,
      maxTokens: 200,
    },

    // Conflict categories to check
    categories: [
      'location',      // Where user lives/works
      'job',           // Employment, role, company
      'relationship',  // Family, friends status
      'name',          // User's name, nicknames
      'preference',    // Likes, dislikes, favorites
      'personal_info', // Age, birthday, etc.
    ],

    // Conflict types
    conflictTypes: {
      CONFLICT: 'Contradictory information that needs clarification',
      UPDATE: 'New information that replaces old (temporal change)',
      ADDITION: 'Complementary information, both can coexist',
      DUPLICATE: 'Same information, no action needed',
    },

    // Behavior settings
    behavior: {
      autoResolveUpdates: false,    // Auto-accept UPDATE type without asking
      skipDuplicates: true,         // Skip saving if DUPLICATE detected
      askForAllConflicts: true,     // Always ask user for CONFLICT type
      logAllChecks: true,           // Log even when no conflict found
    },

    // Prompt template for LLM conflict detection
    promptTemplate: `You are analyzing whether two pieces of information about a user conflict.

EXISTING MEMORY: {{existing}}
NEW INFORMATION: {{new}}

Determine the relationship between these. Respond with exactly one of:
- CONFLICT: They directly contradict each other (e.g., "lives in NYC" vs "lives in Miami")
- UPDATE: The new info is a temporal update to old info (e.g., job change, moved locations)
- ADDITION: They can both be true simultaneously (e.g., two different hobbies)
- DUPLICATE: They express the same information

Respond in JSON format:
{
  "type": "CONFLICT|UPDATE|ADDITION|DUPLICATE",
  "confidence": 0.0-1.0,
  "reason": "Brief explanation"
}`,

    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await configRef.set(config);
  console.log('Created config/pipeline/stages/conflict_check');
  console.log('\nConfig structure:');
  console.log(JSON.stringify(config, null, 2));
}

setupConflictCheck()
  .then(() => {
    console.log('\nSetup complete!');
    process.exit(0);
  })
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
