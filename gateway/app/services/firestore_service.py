"""
Firestore Service - Connects to Google Cloud Firestore
Used for persistent storage of users, conversations, etc.
"""
from typing import Optional, Any
from datetime import datetime
from google.cloud import firestore
from google.cloud.firestore_v1 import FieldFilter

from app.config import settings


class FirestoreService:
    def __init__(self):
        self.db: Optional[firestore.AsyncClient] = None

    def connect(self):
        """Initialize Firestore connection"""
        try:
            if settings.google_cloud_project:
                self.db = firestore.AsyncClient(project=settings.google_cloud_project)
            else:
                # Will use default credentials from environment
                self.db = firestore.AsyncClient()
            print("Connected to Firestore")
        except Exception as e:
            print(f"Warning: Could not connect to Firestore: {e}")
            self.db = None

    # User operations
    async def get_user(self, user_id: str) -> Optional[dict]:
        """Get user by ID"""
        if not self.db:
            return None
        doc = await self.db.collection("users").document(user_id).get()
        if doc.exists:
            return {"id": doc.id, **doc.to_dict()}
        return None

    async def update_user(self, user_id: str, data: dict) -> bool:
        """Update user data"""
        if not self.db:
            return False
        data["updatedAt"] = datetime.utcnow()
        await self.db.collection("users").document(user_id).update(data)
        return True

    # Chat history operations
    async def save_chat_message(
        self,
        user_id: str,
        message: str,
        response: str,
        model: str,
        metadata: Optional[dict] = None,
    ) -> str:
        """Save a chat message and response"""
        if not self.db:
            return ""

        doc_data = {
            "userId": user_id,
            "message": message,
            "response": response,
            "model": model,
            "metadata": metadata or {},
            "createdAt": datetime.utcnow(),
        }

        doc_ref = await self.db.collection("chat_history").add(doc_data)
        return doc_ref[1].id

    async def get_chat_history(
        self,
        user_id: str,
        limit: int = 20,
    ) -> list[dict]:
        """Get recent chat history for a user"""
        if not self.db:
            return []

        query = (
            self.db.collection("chat_history")
            .where(filter=FieldFilter("userId", "==", user_id))
            .order_by("createdAt", direction=firestore.Query.DESCENDING)
            .limit(limit)
        )

        docs = await query.get()
        return [{"id": doc.id, **doc.to_dict()} for doc in docs]

    # Memory operations (for future use)
    async def save_memory(
        self,
        user_id: str,
        memory_type: str,
        content: str,
        metadata: Optional[dict] = None,
    ) -> str:
        """Save a memory for a user"""
        if not self.db:
            return ""

        doc_data = {
            "userId": user_id,
            "type": memory_type,
            "content": content,
            "metadata": metadata or {},
            "createdAt": datetime.utcnow(),
        }

        doc_ref = await self.db.collection("memories").document(user_id).collection("items").add(doc_data)
        return doc_ref[1].id

    async def get_memories(
        self,
        user_id: str,
        memory_type: Optional[str] = None,
        limit: int = 50,
    ) -> list[dict]:
        """Get memories for a user"""
        if not self.db:
            return []

        query = self.db.collection("memories").document(user_id).collection("items")

        if memory_type:
            query = query.where(filter=FieldFilter("type", "==", memory_type))

        query = query.order_by("createdAt", direction=firestore.Query.DESCENDING).limit(limit)

        docs = await query.get()
        return [{"id": doc.id, **doc.to_dict()} for doc in docs]

    # Analytics/logging
    async def log_request(
        self,
        user_id: str,
        endpoint: str,
        model: str,
        latency_ms: int,
        success: bool,
        error: Optional[str] = None,
    ) -> None:
        """Log an API request for analytics"""
        if not self.db:
            return

        doc_data = {
            "userId": user_id,
            "endpoint": endpoint,
            "model": model,
            "latencyMs": latency_ms,
            "success": success,
            "error": error,
            "createdAt": datetime.utcnow(),
        }

        await self.db.collection("api_logs").add(doc_data)

    async def health_check(self) -> dict:
        """Check Firestore connection health"""
        if not self.db:
            return {"status": "not_configured"}

        try:
            # Try to read a document to verify connection
            await self.db.collection("_health").document("check").get()
            return {"status": "healthy"}
        except Exception as e:
            return {"status": "error", "error": str(e)}


# Singleton instance
firestore_service = FirestoreService()
