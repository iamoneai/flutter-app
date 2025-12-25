"""
Redis Service - Connects to Upstash Redis via REST API
Used for caching, rate limiting, and session storage
Version: 2.0 - Uses httpx directly instead of upstash-redis package
"""
import json
from typing import Optional, Any
import httpx

from app.config import settings


class RedisService:
    """Upstash Redis client using REST API"""

    def __init__(self):
        self.url = settings.upstash_redis_rest_url
        self._client: Optional[httpx.AsyncClient] = None

    @property
    def token(self) -> str:
        return settings.upstash_redis_rest_token

    async def connect(self):
        """Initialize the HTTP client"""
        if self.token:
            self._client = httpx.AsyncClient(timeout=10.0)
            print("Redis service initialized (Upstash REST API)")
        else:
            print("Warning: Upstash Redis token not configured")

    async def disconnect(self):
        """Close the HTTP client"""
        if self._client:
            await self._client.aclose()
            print("Redis service disconnected")

    async def _execute(self, *args) -> Any:
        """Execute a Redis command via REST API"""
        if not self._client or not self.token:
            return None

        try:
            response = await self._client.post(
                self.url,
                headers={"Authorization": f"Bearer {self.token}"},
                json=list(args),
            )
            response.raise_for_status()
            data = response.json()
            return data.get("result")
        except Exception as e:
            print(f"Redis error: {e}")
            return None

    async def get(self, key: str) -> Optional[str]:
        """Get a value by key"""
        return await self._execute("GET", key)

    async def set(
        self,
        key: str,
        value: str,
        ex: Optional[int] = None,
    ) -> bool:
        """Set a value with optional expiry"""
        if ex:
            result = await self._execute("SET", key, value, "EX", ex)
        else:
            result = await self._execute("SET", key, value)
        return result == "OK"

    async def delete(self, key: str) -> bool:
        """Delete a key"""
        result = await self._execute("DEL", key)
        return result is not None and result > 0

    async def incr(self, key: str) -> Optional[int]:
        """Increment a key"""
        return await self._execute("INCR", key)

    async def expire(self, key: str, seconds: int) -> bool:
        """Set expiry on a key"""
        result = await self._execute("EXPIRE", key, seconds)
        return result == 1

    async def get_json(self, key: str) -> Optional[dict]:
        """Get and parse JSON value"""
        value = await self.get(key)
        if value:
            return json.loads(value)
        return None

    async def set_json(
        self,
        key: str,
        value: Any,
        ex: Optional[int] = None,
    ) -> bool:
        """Set a JSON value"""
        return await self.set(key, json.dumps(value), ex=ex)

    async def check_rate_limit(
        self,
        key: str,
        limit: int,
        window_seconds: int = 60,
    ) -> tuple[bool, int]:
        """
        Check if rate limit is exceeded
        Returns (is_allowed, current_count)
        """
        if not self._client or not self.token:
            return True, 0

        current = await self.get(key)
        count = int(current) if current else 0

        if count >= limit:
            return False, count

        # Increment counter
        new_count = await self.incr(key)
        if count == 0:
            await self.expire(key, window_seconds)

        return True, new_count or count + 1

    async def get_cached(self, key: str) -> Optional[dict]:
        """Get cached value"""
        return await self.get_json(f"cache:{key}")

    async def set_cached(self, key: str, value: Any, ttl: int = 300) -> bool:
        """Cache a value with TTL"""
        return await self.set_json(f"cache:{key}", value, ex=ttl)

    async def get_conversation(self, user_id: str) -> list[dict]:
        """Get conversation history for a user"""
        data = await self.get_json(f"conv:{user_id}")
        return data.get("messages", []) if data else []

    async def save_conversation(
        self,
        user_id: str,
        messages: list[dict],
        ttl: int = 3600,
    ) -> bool:
        """Save conversation history"""
        return await self.set_json(f"conv:{user_id}", {"messages": messages}, ex=ttl)

    async def clear_conversation(self, user_id: str) -> bool:
        """Clear conversation history"""
        return await self.delete(f"conv:{user_id}")

    async def health_check(self) -> dict:
        """Check Redis connection health"""
        if not self._client or not self.token:
            return {"status": "not_configured"}

        try:
            result = await self._execute("PING")
            if result == "PONG":
                return {"status": "healthy"}
            return {"status": "unhealthy", "result": result}
        except Exception as e:
            return {"status": "error", "error": str(e)}


# Singleton instance
redis_service = RedisService()
