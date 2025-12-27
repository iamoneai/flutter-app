"""
LLM Service - Connects to RunPod and Groq APIs
Supports Llama-3 (RunPod chat), Nemotron (RunPod orchestration), and Groq (ultra-fast)
"""
import httpx
import logging
from typing import Optional
from enum import Enum

from app.config import settings

logger = logging.getLogger(__name__)


class LLMModel(str, Enum):
    LLAMA3 = "llama3"      # Chat responses, conversation (RunPod)
    NEMOTRON = "nemotron"  # Classification, routing, intent detection (RunPod)
    GROQ = "groq"          # Ultra-fast inference (Groq API)


class LLMService:
    def __init__(self):
        # RunPod configuration
        self.runpod_api_key = settings.runpod_api_key
        self.runpod_endpoints = {
            LLMModel.LLAMA3: settings.runpod_llama3_endpoint_id,
            LLMModel.NEMOTRON: settings.runpod_nemotron_endpoint_id,
        }
        self.runpod_base_url = "https://api.runpod.ai/v2"

        # Groq configuration
        self.groq_api_key = settings.groq_api_key
        self.groq_base_url = "https://api.groq.com/openai/v1"
        self.groq_default_model = "llama-3.3-70b-versatile"

    def _get_runpod_endpoint_url(self, model: LLMModel) -> str:
        endpoint_id = self.runpod_endpoints[model]
        return f"{self.runpod_base_url}/{endpoint_id}/runsync"

    def _get_runpod_headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self.runpod_api_key}",
            "Content-Type": "application/json",
        }

    def _get_groq_headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self.groq_api_key}",
            "Content-Type": "application/json",
        }

    async def generate(
        self,
        prompt: str,
        model: LLMModel = LLMModel.LLAMA3,
        max_tokens: int = 1024,
        temperature: float = 0.7,
        system_prompt: Optional[str] = None,
    ) -> dict:
        """Generate a response from the specified model"""
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        return await self.generate_with_history(
            messages=messages,
            model=model,
            max_tokens=max_tokens,
            temperature=temperature,
        )

    async def generate_with_history(
        self,
        messages: list[dict],
        model: LLMModel = LLMModel.LLAMA3,
        max_tokens: int = 1024,
        temperature: float = 0.7,
    ) -> dict:
        """Generate a response with conversation history"""
        # Route to appropriate provider
        if model == LLMModel.GROQ:
            return await self._generate_groq(messages, max_tokens, temperature)
        else:
            return await self._generate_runpod(messages, model, max_tokens, temperature)

    async def _generate_groq(
        self,
        messages: list[dict],
        max_tokens: int = 1024,
        temperature: float = 0.7,
    ) -> dict:
        """Generate response using Groq API (OpenAI-compatible)"""
        url = f"{self.groq_base_url}/chat/completions"

        payload = {
            "model": self.groq_default_model,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
        }

        logger.info(f"[Groq] Sending request to {url} with model {self.groq_default_model}")

        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                url,
                headers=self._get_groq_headers(),
                json=payload,
            )
            response.raise_for_status()
            result = response.json()

            # Extract response from OpenAI-compatible format
            response_text = ""
            usage = {}
            if "choices" in result and len(result["choices"]) > 0:
                choice = result["choices"][0]
                if "message" in choice:
                    response_text = choice["message"].get("content", "")

            if "usage" in result:
                usage = {
                    "prompt_tokens": result["usage"].get("prompt_tokens"),
                    "completion_tokens": result["usage"].get("completion_tokens"),
                    "total_tokens": result["usage"].get("total_tokens"),
                }

            logger.info(f"[Groq] Response received: {len(response_text)} chars")

            return {
                "success": True,
                "model": self.groq_default_model,
                "response": response_text,
                "usage": usage,
                "raw": result,
            }

    async def _generate_runpod(
        self,
        messages: list[dict],
        model: LLMModel,
        max_tokens: int = 1024,
        temperature: float = 0.7,
    ) -> dict:
        """Generate response using RunPod API"""
        url = self._get_runpod_endpoint_url(model)

        payload = {
            "input": {
                "messages": messages,
                "max_tokens": max_tokens,
                "temperature": temperature,
            }
        }

        logger.info(f"[RunPod] Sending request to {url}")

        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                url,
                headers=self._get_runpod_headers(),
                json=payload,
            )
            response.raise_for_status()
            result = response.json()

            return {
                "success": True,
                "model": model.value,
                "response": self._extract_response(result),
                "usage": self._extract_usage(result),
                "raw": result,
            }

    async def classify(
        self,
        text: str,
        system_prompt: Optional[str] = None,
        max_tokens: int = 256,
        temperature: float = 0.3,
    ) -> dict:
        """Use Nemotron for classification/routing tasks"""
        return await self.generate(
            prompt=text,
            model=LLMModel.NEMOTRON,
            max_tokens=max_tokens,
            temperature=temperature,
            system_prompt=system_prompt,
        )

    async def chat(
        self,
        messages: list[dict],
        max_tokens: int = 1024,
        temperature: float = 0.7,
    ) -> dict:
        """Use Llama-3 for chat responses"""
        return await self.generate_with_history(
            messages=messages,
            model=LLMModel.LLAMA3,
            max_tokens=max_tokens,
            temperature=temperature,
        )

    def _extract_response(self, result) -> str:
        """Extract the text response from RunPod result"""
        if isinstance(result, list):
            if len(result) > 0:
                result = result[0]
            else:
                return ""

        if not isinstance(result, dict):
            return str(result)

        output = result.get("output", {})

        # Handle if output is a list (common in vLLM responses)
        if isinstance(output, list) and len(output) > 0:
            output = output[0]

        if isinstance(output, str):
            return output

        if isinstance(output, dict):
            # Handle vLLM choices format
            if "choices" in output:
                choices = output["choices"]
                if choices and len(choices) > 0:
                    choice = choices[0]
                    if "tokens" in choice:
                        tokens = choice["tokens"]
                        if isinstance(tokens, list) and len(tokens) > 0:
                            return tokens[0]
                    if "message" in choice:
                        return choice.get("message", {}).get("content", "")
                    if "text" in choice:
                        return choice["text"]

            # Handle text field
            if "text" in output:
                text = output["text"]
                if isinstance(text, list):
                    return text[0] if len(text) > 0 else ""
                return text

            if "response" in output:
                return output["response"]

            if "content" in output:
                return output["content"]

        if isinstance(output, list) and len(output) > 0:
            return str(output[0])

        return str(output)

    def _extract_usage(self, result) -> dict:
        """Extract usage info from RunPod result"""
        if isinstance(result, list):
            if len(result) > 0:
                result = result[0]
            else:
                return {}

        if not isinstance(result, dict):
            return {}

        output = result.get("output", {})

        if isinstance(output, list) and len(output) > 0:
            output = output[0]

        if isinstance(output, dict):
            usage = output.get("usage", {})
            if usage:
                return {
                    "prompt_tokens": usage.get("input") or usage.get("prompt_tokens"),
                    "completion_tokens": usage.get("output") or usage.get("completion_tokens"),
                    "total_tokens": (usage.get("input", 0) or usage.get("prompt_tokens", 0)) +
                                   (usage.get("output", 0) or usage.get("completion_tokens", 0)),
                }
        return {}

    async def health_check(self, model: LLMModel) -> dict:
        """Check if an endpoint is healthy"""
        if model == LLMModel.GROQ:
            # Groq doesn't have a health endpoint, test with a simple request
            try:
                url = f"{self.groq_base_url}/models"
                async with httpx.AsyncClient(timeout=10.0) as client:
                    response = await client.get(url, headers=self._get_groq_headers())
                    return {
                        "model": model.value,
                        "status": "healthy" if response.status_code == 200 else "unhealthy",
                        "provider": "groq",
                    }
            except Exception as e:
                return {
                    "model": model.value,
                    "status": "error",
                    "error": str(e),
                    "provider": "groq",
                }
        else:
            # RunPod health check
            endpoint_id = self.runpod_endpoints[model]
            url = f"{self.runpod_base_url}/{endpoint_id}/health"

            try:
                async with httpx.AsyncClient(timeout=10.0) as client:
                    response = await client.get(url, headers=self._get_runpod_headers())
                    return {
                        "model": model.value,
                        "status": "healthy" if response.status_code == 200 else "unhealthy",
                        "endpoint_id": endpoint_id,
                        "provider": "runpod",
                    }
            except Exception as e:
                return {
                    "model": model.value,
                    "status": "error",
                    "error": str(e),
                    "endpoint_id": endpoint_id,
                    "provider": "runpod",
                }


# Singleton instance
llm_service = LLMService()
