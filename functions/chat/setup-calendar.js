// Setup Firestore config for Calendar/Events System
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

async function setupCalendar() {
  console.log('Setting up Calendar/Events config...\n');

  // ═══════════════════════════════════════════════════════════
  // PART A: Calendar Stage Config
  // ═══════════════════════════════════════════════════════════

  const calendarConfigRef = db.collection('config').doc('pipeline')
    .collection('stages').doc('calendar');

  const calendarConfig = {
    enabled: true,
    stageNumber: 6.7,  // After Conflict Check (6.5), before Curiosity (7)
    stageName: 'Calendar/Events',

    // Extraction settings
    extraction: {
      mode: 'llm',  // 'llm' | 'pattern' | 'hybrid'
      llm: {
        provider: 'gemini',
        model: 'gemini-2.0-flash-exp',
        temperature: 0.2,
        maxTokens: 300,
      },
      patterns: {
        // Regex patterns for common time expressions
        time: '\\b(\\d{1,2})(:\\d{2})?\\s*(am|pm|AM|PM)?\\b',
        date: '\\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b',
        relative: '\\b(next|this|in \\d+)\\s*(day|week|month)s?\\b',
      },
    },

    // Default settings
    defaults: {
      reminderMinutes: 60,
      eventType: 'event',
      status: 'active',
      source: 'chat',
    },

    // Recurrence options
    recurrence: {
      enabled: true,
      types: ['none', 'daily', 'weekly', 'monthly', 'yearly'],
      maxOccurrences: 52,  // Max 1 year of weekly events
    },

    // Conflict detection
    conflictDetection: {
      enabled: true,
      bufferMinutes: 30,  // Consider events within 30 min as potential conflict
      askOnConflict: true,
    },

    // Event types
    eventTypes: {
      appointment: {
        icon: '🏥',
        color: '#4CAF50',
        defaultReminder: 60,
      },
      reminder: {
        icon: '⏰',
        color: '#FF9800',
        defaultReminder: 15,
      },
      deadline: {
        icon: '📅',
        color: '#F44336',
        defaultReminder: 1440,  // 24 hours
      },
      event: {
        icon: '📌',
        color: '#2196F3',
        defaultReminder: 60,
      },
      meeting: {
        icon: '👥',
        color: '#9C27B0',
        defaultReminder: 15,
      },
    },

    // Query settings
    query: {
      defaultLookaheadDays: 7,
      maxEventsPerQuery: 20,
      includeCompleted: false,
    },

    // Prompt templates
    prompts: {
      extraction: `Extract event details from this message. Today is {{currentDate}}.
Return JSON only, no explanation:
{
  "title": "event name",
  "type": "appointment|reminder|deadline|event|meeting",
  "date": "YYYY-MM-DD",
  "time": "HH:MM" or null,
  "endTime": "HH:MM" or null,
  "location": "place" or null,
  "description": "additional details" or null,
  "recurrence": "none|daily|weekly|monthly" or null,
  "confidence": 0.0-1.0
}

Message: "{{message}}"`,

      queryParse: `Parse this schedule query. Today is {{currentDate}}.
Return JSON only:
{
  "queryType": "specific_date|range|availability|upcoming",
  "startDate": "YYYY-MM-DD",
  "endDate": "YYYY-MM-DD" or null,
  "time": "HH:MM" or null
}

Query: "{{message}}"`,
    },

    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await calendarConfigRef.set(calendarConfig);
  console.log('✓ Created config/pipeline/stages/calendar');

  // ═══════════════════════════════════════════════════════════
  // Update Intent Resolution Config with Calendar Intents
  // ═══════════════════════════════════════════════════════════

  const intentConfigRef = db.collection('config').doc('pipeline')
    .collection('stages').doc('intent_resolution');

  const intentDoc = await intentConfigRef.get();
  const existingIntentConfig = intentDoc.data() || {};

  // Add calendar intents to existing config
  const calendarIntents = {
    schedule_add: {
      triggers: ['i have', 'appointment', 'meeting', 'remind me', 'schedule', 'dentist', 'doctor', 'call at', 'at \\d'],
      description: 'User wants to create/add an event',
      priority: 8,
      requiresExtraction: true,
    },
    schedule_query: {
      triggers: ['what do i have', "what's on", 'am i free', 'my schedule', 'do i have anything', 'what are my plans', 'what events'],
      description: 'User asking about their schedule',
      priority: 7,
      requiresExtraction: false,
    },
    schedule_update: {
      triggers: ['move my', 'change the', 'reschedule', 'postpone', 'push back'],
      description: 'User modifying existing event',
      priority: 8,
      requiresExtraction: true,
    },
    schedule_delete: {
      triggers: ['cancel my', 'delete the', 'remove my', 'cancel the'],
      description: 'User cancelling/deleting event',
      priority: 8,
      requiresExtraction: true,
    },
  };

  // Merge with existing intents
  const updatedIntents = {
    ...existingIntentConfig.intents,
    ...calendarIntents,
  };

  await intentConfigRef.set({
    ...existingIntentConfig,
    intents: updatedIntents,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  console.log('✓ Updated config/pipeline/stages/intent_resolution with calendar intents');

  // ═══════════════════════════════════════════════════════════
  // Create sample event document structure (for reference)
  // ═══════════════════════════════════════════════════════════

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Event Document Schema (memories/{iin}/events/{eventId}):');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(JSON.stringify({
    id: 'auto-generated',
    title: 'Dentist Appointment',
    type: 'appointment',
    date: 'Timestamp',
    time: '15:00',
    endTime: '16:00',
    location: '123 Main St',
    description: 'Annual checkup',
    reminderSent: false,
    reminderTime: 60,
    recurrence: 'none',
    source: 'chat',
    status: 'active',
    createdAt: 'Timestamp',
    updatedAt: 'Timestamp',
  }, null, 2));

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('Calendar Config:');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(JSON.stringify(calendarConfig, null, 2));
}

setupCalendar()
  .then(() => {
    console.log('\n✓ Calendar setup complete!');
    process.exit(0);
  })
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
