import * as admin from 'firebase-admin';

const db = admin.firestore();

// ═══════════════════════════════════════════════════════════
// CHAT LOG TRACKING UTILITY
// Ensures all chat messages are stored for compression
// Path: chat_logs/{iin}/{sessionId}/messages/{messageId}
// ═══════════════════════════════════════════════════════════

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
  timestamp: admin.firestore.FieldValue | admin.firestore.Timestamp;
  compressed: boolean;
}

interface LogMessageOptions {
  iin: string;
  sessionId: string;
  role: 'user' | 'assistant';
  content: string;
  metadata?: Record<string, any>;
}

/**
 * Log a chat message for future compression
 * Called after each message exchange in the pipeline
 */
export async function logChatMessage(options: LogMessageOptions): Promise<string> {
  const { iin, sessionId, role, content, metadata } = options;

  const messageDoc: ChatMessage & Record<string, any> = {
    role,
    content,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    compressed: false,
  };

  // Add optional metadata
  if (metadata) {
    Object.assign(messageDoc, metadata);
  }

  try {
    const docRef = await db.collection('chat_logs').doc(iin)
      .collection(sessionId).add(messageDoc);

    console.log(`[ChatLog] Logged ${role} message for ${iin}/${sessionId}`);
    return docRef.id;
  } catch (error) {
    console.error('[ChatLog] Failed to log message:', error);
    throw error;
  }
}

/**
 * Log both user and assistant messages at once (convenience method)
 */
export async function logConversationTurn(options: {
  iin: string;
  sessionId: string;
  userMessage: string;
  assistantMessage: string;
  metadata?: Record<string, any>;
}): Promise<{ userMessageId: string; assistantMessageId: string }> {
  const { iin, sessionId, userMessage, assistantMessage, metadata } = options;

  // Log user message first
  const userMessageId = await logChatMessage({
    iin,
    sessionId,
    role: 'user',
    content: userMessage,
    metadata: { ...metadata, turnRole: 'user' },
  });

  // Log assistant message
  const assistantMessageId = await logChatMessage({
    iin,
    sessionId,
    role: 'assistant',
    content: assistantMessage,
    metadata: { ...metadata, turnRole: 'assistant' },
  });

  return { userMessageId, assistantMessageId };
}

/**
 * Get or create a session ID for a user
 * Sessions help group related messages together
 */
export async function getOrCreateSession(iin: string, sessionHint?: string): Promise<string> {
  // If a session hint is provided, use it
  if (sessionHint) {
    return sessionHint;
  }

  // Try to find an active session from the last hour
  const oneHourAgo = new Date();
  oneHourAgo.setHours(oneHourAgo.getHours() - 1);

  try {
    // Get the most recent session
    const sessionsRef = db.collection('chat_logs').doc(iin);
    const collections = await sessionsRef.listCollections();

    for (const collection of collections) {
      // Check if this session has recent activity
      const recentMessages = await collection
        .orderBy('timestamp', 'desc')
        .limit(1)
        .get();

      if (!recentMessages.empty) {
        const lastMessage = recentMessages.docs[0].data();
        const lastTimestamp = lastMessage.timestamp?.toDate?.() || new Date(0);

        if (lastTimestamp > oneHourAgo) {
          return collection.id;
        }
      }
    }
  } catch (error) {
    console.log('[ChatLog] Error checking existing sessions:', error);
  }

  // Create a new session
  const sessionId = `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  console.log(`[ChatLog] Created new session: ${sessionId}`);
  return sessionId;
}

/**
 * Get chat history for a session
 */
export async function getSessionHistory(
  iin: string,
  sessionId: string,
  limit: number = 50
): Promise<Array<{ role: string; content: string; timestamp: Date }>> {
  try {
    const query = await db.collection('chat_logs').doc(iin)
      .collection(sessionId)
      .orderBy('timestamp', 'asc')
      .limit(limit)
      .get();

    return query.docs.map(doc => {
      const data = doc.data();
      return {
        role: data.role,
        content: data.content,
        timestamp: data.timestamp?.toDate?.() || new Date(),
      };
    });
  } catch (error) {
    console.error('[ChatLog] Failed to get session history:', error);
    return [];
  }
}

/**
 * Get uncompressed message count for a user
 * Useful for monitoring compression status
 */
export async function getUncompressedMessageCount(iin: string): Promise<number> {
  let count = 0;

  try {
    const iinRef = db.collection('chat_logs').doc(iin);
    const collections = await iinRef.listCollections();

    for (const collection of collections) {
      const query = await collection
        .where('compressed', '==', false)
        .get();
      count += query.size;
    }
  } catch (error) {
    console.error('[ChatLog] Error counting uncompressed messages:', error);
  }

  return count;
}

export { ChatMessage };
