// IAMONEAI - Calendar/Events Stage (Stage ⑥.7)
// Config stored at: config/pipeline/stages/calendar
//
// PURPOSE: Handle calendar events - extraction, queries, conflicts
// FLOW: Conflict Check (⑥.5) → Calendar (⑥.7) → Curiosity Module (⑦)
//
// Handles:
//   - schedule_add: Extract and save new events
//   - schedule_query: Query and return events
//   - schedule_update: Modify existing events
//   - schedule_delete: Cancel/remove events

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

interface CalendarConfig {
  enabled: boolean;
  stageNumber: number;
  stageName: string;
  extraction: {
    mode: 'llm' | 'pattern' | 'hybrid';
    llm: {
      provider: string;
      model: string;
      temperature: number;
      maxTokens: number;
    };
    patterns: Record<string, string>;
  };
  defaults: {
    reminderMinutes: number;
    eventType: string;
    status: string;
    source: string;
  };
  recurrence: {
    enabled: boolean;
    types: string[];
    maxOccurrences: number;
  };
  conflictDetection: {
    enabled: boolean;
    bufferMinutes: number;
    askOnConflict: boolean;
  };
  eventTypes: Record<string, {
    icon: string;
    color: string;
    defaultReminder: number;
  }>;
  query: {
    defaultLookaheadDays: number;
    maxEventsPerQuery: number;
    includeCompleted: boolean;
  };
  prompts: {
    extraction: string;
    queryParse: string;
  };
}

interface CalendarEvent {
  id?: string;
  title: string;
  type: 'appointment' | 'reminder' | 'deadline' | 'event' | 'meeting';
  date: Date | admin.firestore.Timestamp;
  time?: string;
  endTime?: string;
  location?: string;
  description?: string;
  reminderSent: boolean;
  reminderTime?: number;
  recurrence: string;
  source: string;
  status: 'active' | 'completed' | 'cancelled';
  createdAt?: admin.firestore.Timestamp;
  updatedAt?: admin.firestore.Timestamp;
}

interface ExtractedEvent {
  title: string;
  type: string;
  date: string;
  time?: string;
  endTime?: string;
  location?: string;
  description?: string;
  recurrence?: string;
  confidence: number;
}

interface CalendarConflict {
  existingEvent: CalendarEvent;
  newEvent: ExtractedEvent;
  overlapType: 'exact' | 'overlap' | 'close';
}

interface CalendarInput {
  iin: string;
  message: string;
  intent: string;  // schedule_add | schedule_query | schedule_update | schedule_delete
  currentDate?: Date;
}

interface CalendarOutput {
  action: string;
  success: boolean;
  event?: CalendarEvent;
  events?: CalendarEvent[];
  extractedEvent?: ExtractedEvent;
  conflicts?: CalendarConflict[];
  needsClarification: boolean;
  clarificationQuestion?: string;
  missingFields?: string[];
  response?: string;
  processingTime: string;
}

// ═══════════════════════════════════════════════════════════
// CONFIG LOADER
// ═══════════════════════════════════════════════════════════

async function getCalendarConfig(): Promise<CalendarConfig> {
  const doc = await db.collection('config').doc('pipeline')
    .collection('stages').doc('calendar').get();

  const data = doc.data() ?? {};

  return {
    enabled: data.enabled ?? true,
    stageNumber: data.stageNumber ?? 6.7,
    stageName: data.stageName ?? 'Calendar/Events',
    extraction: {
      mode: data.extraction?.mode ?? 'llm',
      llm: {
        provider: data.extraction?.llm?.provider ?? 'gemini',
        model: data.extraction?.llm?.model ?? 'gemini-2.0-flash-exp',
        temperature: data.extraction?.llm?.temperature ?? 0.2,
        maxTokens: data.extraction?.llm?.maxTokens ?? 300,
      },
      patterns: data.extraction?.patterns ?? {},
    },
    defaults: {
      reminderMinutes: data.defaults?.reminderMinutes ?? 60,
      eventType: data.defaults?.eventType ?? 'event',
      status: data.defaults?.status ?? 'active',
      source: data.defaults?.source ?? 'chat',
    },
    recurrence: {
      enabled: data.recurrence?.enabled ?? true,
      types: data.recurrence?.types ?? ['none', 'daily', 'weekly', 'monthly'],
      maxOccurrences: data.recurrence?.maxOccurrences ?? 52,
    },
    conflictDetection: {
      enabled: data.conflictDetection?.enabled ?? true,
      bufferMinutes: data.conflictDetection?.bufferMinutes ?? 30,
      askOnConflict: data.conflictDetection?.askOnConflict ?? true,
    },
    eventTypes: data.eventTypes ?? {
      appointment: { icon: '🏥', color: '#4CAF50', defaultReminder: 60 },
      reminder: { icon: '⏰', color: '#FF9800', defaultReminder: 15 },
      deadline: { icon: '📅', color: '#F44336', defaultReminder: 1440 },
      event: { icon: '📌', color: '#2196F3', defaultReminder: 60 },
      meeting: { icon: '👥', color: '#9C27B0', defaultReminder: 15 },
    },
    query: {
      defaultLookaheadDays: data.query?.defaultLookaheadDays ?? 7,
      maxEventsPerQuery: data.query?.maxEventsPerQuery ?? 20,
      includeCompleted: data.query?.includeCompleted ?? false,
    },
    prompts: {
      extraction: data.prompts?.extraction ?? getDefaultExtractionPrompt(),
      queryParse: data.prompts?.queryParse ?? getDefaultQueryPrompt(),
    },
  };
}

function getDefaultExtractionPrompt(): string {
  return `Extract event details from this message. Today is {{currentDate}}.
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

Message: "{{message}}"`;
}

function getDefaultQueryPrompt(): string {
  return `Parse this schedule query. Today is {{currentDate}}.
Return JSON only:
{
  "queryType": "specific_date|range|availability|upcoming",
  "startDate": "YYYY-MM-DD",
  "endDate": "YYYY-MM-DD" or null,
  "time": "HH:MM" or null
}

Query: "{{message}}"`;
}

// ═══════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════

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

function formatDate(date: Date): string {
  return date.toISOString().split('T')[0];
}


function formatEventForResponse(event: CalendarEvent, config: CalendarConfig): string {
  const typeConfig = config.eventTypes[event.type] || config.eventTypes.event;
  const icon = typeConfig.icon;

  let dateStr: string;
  if (event.date instanceof Date) {
    dateStr = event.date.toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
  } else {
    dateStr = event.date.toDate().toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
  }

  let result = `${icon} ${event.title} on ${dateStr}`;
  if (event.time) {
    result += ` at ${event.time}`;
  }
  if (event.location) {
    result += ` (${event.location})`;
  }
  return result;
}

// ═══════════════════════════════════════════════════════════
// EVENT EXTRACTION (PART C)
// ═══════════════════════════════════════════════════════════

async function extractEventFromMessage(
  message: string,
  currentDate: Date,
  config: CalendarConfig
): Promise<{ event: ExtractedEvent | null; missingFields: string[] }> {
  try {
    const apiKey = await getSecret('gemini-api-key');
    if (!apiKey) {
      console.error('[CALENDAR] No API key found');
      return { event: null, missingFields: ['api_error'] };
    }

    const prompt = config.prompts.extraction
      .replace('{{currentDate}}', formatDate(currentDate))
      .replace('{{message}}', message);

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
      model: config.extraction.llm.model,
      generationConfig: {
        temperature: config.extraction.llm.temperature,
        maxOutputTokens: config.extraction.llm.maxTokens,
      },
    });

    const result = await model.generateContent(prompt);
    const responseText = result.response.text();

    // Parse JSON from response
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      console.warn('[CALENDAR] Could not parse LLM response');
      return { event: null, missingFields: ['parse_error'] };
    }

    const extracted: ExtractedEvent = JSON.parse(jsonMatch[0]);
    console.log(`[CALENDAR] Extracted event: ${extracted.title}, date: ${extracted.date}, confidence: ${extracted.confidence}`);

    // Check for missing required fields
    const missingFields: string[] = [];
    if (!extracted.title || extracted.title.toLowerCase() === 'event name') {
      missingFields.push('title');
    }
    if (!extracted.date || extracted.date === 'YYYY-MM-DD') {
      missingFields.push('date');
    }

    return { event: extracted, missingFields };

  } catch (error: any) {
    console.error('[CALENDAR] Extraction error:', error.message);
    return { event: null, missingFields: ['extraction_error'] };
  }
}

// ═══════════════════════════════════════════════════════════
// CONFLICT CHECKING (PART D)
// ═══════════════════════════════════════════════════════════

async function checkEventConflicts(
  iin: string,
  newEvent: ExtractedEvent,
  config: CalendarConfig
): Promise<CalendarConflict[]> {
  if (!config.conflictDetection.enabled) {
    return [];
  }

  const conflicts: CalendarConflict[] = [];
  const eventDate = new Date(newEvent.date + 'T00:00:00');

  try {
    // Query events on the same day
    const startOfDay = new Date(eventDate);
    startOfDay.setHours(0, 0, 0, 0);
    const endOfDay = new Date(eventDate);
    endOfDay.setHours(23, 59, 59, 999);

    const snapshot = await db.collection('memories').doc(iin)
      .collection('events')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(startOfDay))
      .where('date', '<=', admin.firestore.Timestamp.fromDate(endOfDay))
      .where('status', '==', 'active')
      .get();

    if (snapshot.empty) {
      console.log('[CALENDAR] No existing events on this date');
      return [];
    }

    for (const doc of snapshot.docs) {
      const existing = { id: doc.id, ...doc.data() } as CalendarEvent;

      // Check for time overlap
      if (newEvent.time && existing.time) {
        const newTime = parseTimeToMinutes(newEvent.time);
        const existingTime = parseTimeToMinutes(existing.time);

        if (newTime !== null && existingTime !== null) {
          const diff = Math.abs(newTime - existingTime);

          if (diff === 0) {
            conflicts.push({
              existingEvent: existing,
              newEvent,
              overlapType: 'exact',
            });
          } else if (diff <= config.conflictDetection.bufferMinutes) {
            conflicts.push({
              existingEvent: existing,
              newEvent,
              overlapType: 'close',
            });
          }
        }
      } else if (!newEvent.time && !existing.time) {
        // Both all-day events on same day
        conflicts.push({
          existingEvent: existing,
          newEvent,
          overlapType: 'overlap',
        });
      }
    }

    if (conflicts.length > 0) {
      console.log(`[CALENDAR] Found ${conflicts.length} potential conflicts`);
    }

    return conflicts;

  } catch (error) {
    console.error('[CALENDAR] Conflict check error:', error);
    return [];
  }
}

function parseTimeToMinutes(time: string): number | null {
  const match = time.match(/(\d{1,2}):(\d{2})/);
  if (!match) return null;
  return parseInt(match[1]) * 60 + parseInt(match[2]);
}

// ═══════════════════════════════════════════════════════════
// EVENT QUERIES (PART E)
// ═══════════════════════════════════════════════════════════

async function queryEvents(
  iin: string,
  message: string,
  currentDate: Date,
  config: CalendarConfig
): Promise<{ events: CalendarEvent[]; queryType: string; response: string }> {
  try {
    // Parse the query using LLM
    const apiKey = await getSecret('gemini-api-key');
    let startDate = currentDate;
    let endDate = new Date(currentDate);
    endDate.setDate(endDate.getDate() + config.query.defaultLookaheadDays);
    let queryType = 'upcoming';
    let checkTime: string | null = null;

    if (apiKey) {
      const prompt = config.prompts.queryParse
        .replace('{{currentDate}}', formatDate(currentDate))
        .replace('{{message}}', message);

      const genAI = new GoogleGenerativeAI(apiKey);
      const model = genAI.getGenerativeModel({
        model: config.extraction.llm.model,
        generationConfig: { temperature: 0.1, maxOutputTokens: 200 },
      });

      const result = await model.generateContent(prompt);
      const responseText = result.response.text();
      const jsonMatch = responseText.match(/\{[\s\S]*\}/);

      if (jsonMatch) {
        const parsed = JSON.parse(jsonMatch[0]);
        queryType = parsed.queryType || 'upcoming';
        if (parsed.startDate) startDate = new Date(parsed.startDate + 'T00:00:00');
        if (parsed.endDate) endDate = new Date(parsed.endDate + 'T23:59:59');
        if (parsed.time) checkTime = parsed.time;
      }
    }

    // Query Firestore
    let query = db.collection('memories').doc(iin)
      .collection('events')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(startDate))
      .where('date', '<=', admin.firestore.Timestamp.fromDate(endDate))
      .orderBy('date', 'asc')
      .limit(config.query.maxEventsPerQuery);

    if (!config.query.includeCompleted) {
      query = query.where('status', '==', 'active');
    }

    const snapshot = await query.get();
    const events: CalendarEvent[] = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
    } as CalendarEvent));

    // Build natural response
    let response: string;
    if (events.length === 0) {
      if (queryType === 'availability' && checkTime) {
        response = `You're free at ${checkTime}!`;
      } else if (queryType === 'specific_date') {
        response = `You don't have anything scheduled for that day.`;
      } else {
        response = `Your schedule is clear for the next ${config.query.defaultLookaheadDays} days.`;
      }
    } else if (queryType === 'availability' && checkTime) {
      const atTime = events.find(e => e.time === checkTime);
      if (atTime) {
        response = `You have ${formatEventForResponse(atTime, config)} at that time.`;
      } else {
        response = `You're free at ${checkTime}. Your events that day: ${events.map(e => formatEventForResponse(e, config)).join(', ')}`;
      }
    } else if (events.length === 1) {
      response = `You have ${formatEventForResponse(events[0], config)}.`;
    } else {
      const formatted = events.map(e => formatEventForResponse(e, config));
      response = `You have ${events.length} events:\n${formatted.map(f => `• ${f}`).join('\n')}`;
    }

    console.log(`[CALENDAR] Query returned ${events.length} events`);

    return { events, queryType, response };

  } catch (error) {
    console.error('[CALENDAR] Query error:', error);
    return { events: [], queryType: 'error', response: 'I had trouble checking your schedule.' };
  }
}

// ═══════════════════════════════════════════════════════════
// SAVE EVENT
// ═══════════════════════════════════════════════════════════

async function saveEvent(
  iin: string,
  extracted: ExtractedEvent,
  config: CalendarConfig
): Promise<CalendarEvent> {
  const eventDate = new Date(extracted.date + 'T00:00:00');
  const typeConfig = config.eventTypes[extracted.type] || config.eventTypes.event;

  const event: Omit<CalendarEvent, 'id'> = {
    title: extracted.title,
    type: (extracted.type as CalendarEvent['type']) || 'event',
    date: admin.firestore.Timestamp.fromDate(eventDate),
    time: extracted.time || undefined,
    endTime: extracted.endTime || undefined,
    location: extracted.location || undefined,
    description: extracted.description || undefined,
    reminderSent: false,
    reminderTime: typeConfig.defaultReminder,
    recurrence: extracted.recurrence || 'none',
    source: config.defaults.source,
    status: 'active',
    createdAt: admin.firestore.Timestamp.now(),
    updatedAt: admin.firestore.Timestamp.now(),
  };

  const docRef = await db.collection('memories').doc(iin)
    .collection('events')
    .add(event);

  console.log(`[CALENDAR] Saved event ${docRef.id}: ${event.title}`);

  return { id: docRef.id, ...event };
}

// ═══════════════════════════════════════════════════════════
// MAIN CALENDAR PROCESSOR
// ═══════════════════════════════════════════════════════════

async function processCalendar(input: CalendarInput): Promise<CalendarOutput> {
  const startTime = Date.now();
  const config = await getCalendarConfig();

  console.log(`[CALENDAR] Processing intent: ${input.intent}`);

  if (!config.enabled) {
    return {
      action: 'disabled',
      success: false,
      needsClarification: false,
      response: 'Calendar feature is currently disabled.',
      processingTime: `${Date.now() - startTime}ms`,
    };
  }

  const currentDate = input.currentDate || new Date();

  // Handle different intents
  switch (input.intent) {
    case 'schedule_add': {
      // Extract event from message
      const { event: extracted, missingFields } = await extractEventFromMessage(
        input.message, currentDate, config
      );

      if (!extracted || missingFields.length > 0) {
        // Need clarification
        let question = 'I couldn\'t understand all the event details.';
        if (missingFields.includes('date')) {
          question = 'What day is this for?';
        } else if (missingFields.includes('title')) {
          question = 'What should I call this event?';
        }

        return {
          action: 'schedule_add',
          success: false,
          extractedEvent: extracted || undefined,
          needsClarification: true,
          clarificationQuestion: question,
          missingFields,
          processingTime: `${Date.now() - startTime}ms`,
        };
      }

      // Check for conflicts
      const conflicts = await checkEventConflicts(input.iin, extracted, config);

      if (conflicts.length > 0 && config.conflictDetection.askOnConflict) {
        const conflict = conflicts[0];
        const existingDesc = formatEventForResponse(conflict.existingEvent, config);
        const question = `You already have ${existingDesc}. Should I still schedule ${extracted.title}?`;

        return {
          action: 'schedule_add',
          success: false,
          extractedEvent: extracted,
          conflicts,
          needsClarification: true,
          clarificationQuestion: question,
          processingTime: `${Date.now() - startTime}ms`,
        };
      }

      // Save the event
      const savedEvent = await saveEvent(input.iin, extracted, config);
      const eventDesc = formatEventForResponse(savedEvent, config);

      return {
        action: 'schedule_add',
        success: true,
        event: savedEvent,
        extractedEvent: extracted,
        needsClarification: false,
        response: `Got it! I've added ${eventDesc} to your calendar.`,
        processingTime: `${Date.now() - startTime}ms`,
      };
    }

    case 'schedule_query': {
      const { events, queryType: _queryType, response } = await queryEvents(
        input.iin, input.message, currentDate, config
      );

      return {
        action: 'schedule_query',
        success: true,
        events,
        needsClarification: false,
        response,
        processingTime: `${Date.now() - startTime}ms`,
      };
    }

    case 'schedule_update': {
      // TODO: Implement event update logic
      return {
        action: 'schedule_update',
        success: false,
        needsClarification: true,
        clarificationQuestion: 'Which event would you like to update?',
        processingTime: `${Date.now() - startTime}ms`,
      };
    }

    case 'schedule_delete': {
      // TODO: Implement event deletion logic
      return {
        action: 'schedule_delete',
        success: false,
        needsClarification: true,
        clarificationQuestion: 'Which event would you like to cancel?',
        processingTime: `${Date.now() - startTime}ms`,
      };
    }

    default:
      return {
        action: 'unknown',
        success: false,
        needsClarification: false,
        response: 'I\'m not sure what you want to do with your calendar.',
        processingTime: `${Date.now() - startTime}ms`,
      };
  }
}

// ═══════════════════════════════════════════════════════════
// EXPORTS
// ═══════════════════════════════════════════════════════════

export {
  processCalendar,
  getCalendarConfig,
  extractEventFromMessage,
  checkEventConflicts,
  queryEvents,
  saveEvent,
  CalendarInput,
  CalendarOutput,
  CalendarEvent,
  ExtractedEvent,
  CalendarConflict,
};
