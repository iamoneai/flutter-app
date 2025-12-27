"""
Configuration settings loaded from environment variables and Google Secret Manager
"""
import os
from functools import lru_cache
from typing import Optional


class SecretManager:
    """Lazy-loaded Secret Manager client"""
    _client = None

    @classmethod
    def get_client(cls):
        if cls._client is None:
            try:
                from google.cloud import secretmanager
                cls._client = secretmanager.SecretManagerServiceClient()
            except Exception as e:
                print(f"Warning: Could not initialize Secret Manager client: {e}")
        return cls._client

    @classmethod
    def get_secret(cls, secret_id: str, project_id: str) -> Optional[str]:
        """Fetch a secret from Google Cloud Secret Manager."""
        # First check environment variable (for local dev)
        env_value = os.getenv(secret_id)
        if env_value:
            return env_value

        client = cls.get_client()
        if client is None:
            return None

        try:
            name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
            response = client.access_secret_version(request={"name": name})
            return response.payload.data.decode("UTF-8")
        except Exception as e:
            print(f"Warning: Could not fetch secret {secret_id}: {e}")
            return None


class Settings:
    """Application settings with Secret Manager support"""

    def __init__(self):
        # Google Cloud Configuration
        self.google_cloud_project: str = os.getenv(
            "GOOGLE_CLOUD_PROJECT", "app-iamoneai-c36ec"
        )

        # RunPod Configuration
        self.runpod_llama3_endpoint_id: str = os.getenv(
            "RUNPOD_LLAMA3_ENDPOINT_ID", "nw34gp84qjli46"
        )
        self.runpod_nemotron_endpoint_id: str = os.getenv(
            "RUNPOD_NEMOTRON_ENDPOINT_ID", "29j7gu09q5l6x1"
        )

        # Upstash Redis Configuration
        self.upstash_redis_rest_url: str = os.getenv(
            "UPSTASH_REDIS_REST_URL", "https://popular-marmot-46531.upstash.io"
        )

        # App Configuration
        self.environment: str = os.getenv("ENVIRONMENT", "development")
        self.debug: bool = os.getenv("DEBUG", "true").lower() == "true"

        # LLM Defaults
        self.default_model: str = os.getenv("DEFAULT_MODEL", "llama3")
        self.default_max_tokens: int = int(os.getenv("DEFAULT_MAX_TOKENS", "1024"))
        self.default_temperature: float = float(os.getenv("DEFAULT_TEMPERATURE", "0.7"))

        # Secrets are loaded lazily
        self._runpod_api_key: Optional[str] = None
        self._upstash_redis_rest_token: Optional[str] = None
        self._groq_api_key: Optional[str] = None

    @property
    def runpod_api_key(self) -> str:
        """Lazy load RunPod API key from Secret Manager"""
        if self._runpod_api_key is None:
            self._runpod_api_key = SecretManager.get_secret(
                "RUNPOD_API_KEY", self.google_cloud_project
            ) or ""
        return self._runpod_api_key

    @property
    def upstash_redis_rest_token(self) -> str:
        """Lazy load Upstash Redis token from Secret Manager"""
        if self._upstash_redis_rest_token is None:
            self._upstash_redis_rest_token = SecretManager.get_secret(
                "UPSTASH_REDIS_REST_TOKEN", self.google_cloud_project
            ) or ""
        return self._upstash_redis_rest_token

    @property
    def groq_api_key(self) -> str:
        """Lazy load Groq API key from Secret Manager"""
        if self._groq_api_key is None:
            self._groq_api_key = SecretManager.get_secret(
                "groq-api-key", self.google_cloud_project
            ) or ""
        return self._groq_api_key


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
