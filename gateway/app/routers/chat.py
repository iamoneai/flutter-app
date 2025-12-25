"""
Chat Router - Handles chat/completion endpoints
"""
import re
import time
import logging
from typing import Optional
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, Field

from app.services.llm_service import llm_service, LLMModel
from app.services.redis_service import redis_service
from app.services.firestore_service import firestore_service

# Configure logging
logger = logging.getLogger(__name__)


def clean_response(text: str) -> str:
    """Strip <think>...</think> tags from LLM responses"""
    if not text:
        return text
    cleaned = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL)
    return cleaned.strip()


router = APIRouter()


class ChatMessage(BaseModel):
    role: str = Field(..., description="Role: 'user', 'assistant', or 'system'")
    content: str = Field(..., description="Message content")


class ChatRequest(BaseModel):
    message: str = Field(..., description="User message")
    model: Optional[str] = Field(default="llama3", description="Model: 'llama3' or 'nemotron'")
    max_tokens: Optional[int] = Field(default=1024, ge=1, le=4096)
    temperature: Optional[float] = Field(default=0.7, ge=0.0, le=2.0)
    system_prompt: Optional[str] = Field(default=None, description="System prompt")
    conversation_id: Optional[str] = Field(default=None, description="Conversation ID for history")
    use_history: Optional[bool] = Field(default=False, description="Include conversation history")


class ChatWithHistoryRequest(BaseModel):
    messages: list[ChatMessage] = Field(..., description="Conversation messages")
    model: Optional[str] = Field(default="llama3", description="Model: 'llama3' or 'nemotron'")
    max_tokens: Optional[int] = Field(default=1024, ge=1, le=4096)
    temperature: Optional[float] = Field(default=0.7, ge=0.0, le=2.0)


class ChatResponse(BaseModel):
    success: bool
    response: str
    model: str
    provider: str = "runpod"
    latency_ms: Optional[int] = None
    usage: Optional[dict] = None
    conversation_id: Optional[str] = None


@router.post("/chat", response_model=ChatResponse)
async def chat(
    request: ChatRequest,
    x_user_id: Optional[str] = Header(default=None, alias="X-User-ID"),
):
    """
    Send a chat message and get a response from the LLM
    """
    start_time = time.time()
    user_id = x_user_id or "anonymous"

    # Always use llama3 for chat (nemotron is for classification only)
    model = LLMModel.LLAMA3
    logger.info(f"[{user_id}] Chat request - model: {model.value}")

    # Rate limiting check
    is_allowed, count = await redis_service.check_rate_limit(
        f"rate:{user_id}",
        limit=60,
        window_seconds=60,
    )
    if not is_allowed:
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded. Please wait before sending more messages.",
        )

    # Build messages array for LLM
    messages = []

    # Add system prompt if provided
    if request.system_prompt:
        messages.append({"role": "system", "content": request.system_prompt})

    # Load conversation history from Redis
    history = []
    if request.use_history and user_id != "anonymous":
        history = await redis_service.get_conversation(user_id)
        logger.info(f"[{user_id}] Loaded {len(history)} messages from Redis")
        # Add history to messages (last 10 exchanges = 20 messages)
        messages.extend(history[-20:])

    # Add current user message
    messages.append({"role": "user", "content": request.message})

    # Log the full prompt being sent
    logger.info(f"[{user_id}] Sending {len(messages)} messages to LLM")
    for i, msg in enumerate(messages):
        logger.info(f"[{user_id}] Message {i}: [{msg['role']}] {msg['content'][:100]}...")

    try:
        result = await llm_service.generate_with_history(
            messages=messages,
            model=model,
            max_tokens=request.max_tokens,
            temperature=request.temperature,
        )

        # Clean response (strip <think> tags)
        raw_response = result["response"]
        response_text = clean_response(raw_response)
        logger.info(f"[{user_id}] LLM response (cleaned): {response_text[:100]}...")

        latency_ms = int((time.time() - start_time) * 1000)

        # Save to conversation history in Redis
        if request.use_history and user_id != "anonymous":
            # Append new user message and assistant response to history
            history.append({"role": "user", "content": request.message})
            history.append({"role": "assistant", "content": response_text})
            await redis_service.save_conversation(user_id, history)
            logger.info(f"[{user_id}] Saved exchange to Redis (total: {len(history)} messages)")

        # Save to Firestore for persistence
        if user_id != "anonymous":
            await firestore_service.save_chat_message(
                user_id=user_id,
                message=request.message,
                response=response_text,
                model=model.value,
                metadata={
                    "max_tokens": request.max_tokens,
                    "temperature": request.temperature,
                    "latency_ms": latency_ms,
                },
            )

        # Log the request
        await firestore_service.log_request(
            user_id=user_id,
            endpoint="/api/chat",
            model=model.value,
            latency_ms=latency_ms,
            success=True,
        )

        return ChatResponse(
            success=True,
            response=response_text,
            model=model.value,
            provider="runpod",
            latency_ms=latency_ms,
            usage=result.get("usage"),
            conversation_id=user_id if request.use_history else None,
        )

    except Exception as e:
        logger.error(f"[{user_id}] Error: {str(e)}")
        latency_ms = int((time.time() - start_time) * 1000)
        await firestore_service.log_request(
            user_id=user_id,
            endpoint="/api/chat",
            model=model.value,
            latency_ms=latency_ms,
            success=False,
            error=str(e),
        )

        raise HTTPException(
            status_code=500,
            detail=f"Error generating response: {str(e)}",
        )


@router.post("/chat/complete", response_model=ChatResponse)
async def chat_with_history(
    request: ChatWithHistoryRequest,
    x_user_id: Optional[str] = Header(default=None, alias="X-User-ID"),
):
    """
    Send a full conversation and get a response
    """
    start_time = time.time()
    user_id = x_user_id or "anonymous"

    # Parse model (default to llama3)
    try:
        model = LLMModel(request.model.lower()) if request.model else LLMModel.LLAMA3
    except ValueError:
        model = LLMModel.LLAMA3

    is_allowed, _ = await redis_service.check_rate_limit(
        f"rate:{user_id}",
        limit=60,
        window_seconds=60,
    )
    if not is_allowed:
        raise HTTPException(status_code=429, detail="Rate limit exceeded")

    messages = [{"role": m.role, "content": m.content} for m in request.messages]

    try:
        result = await llm_service.generate_with_history(
            messages=messages,
            model=model,
            max_tokens=request.max_tokens,
            temperature=request.temperature,
        )

        latency_ms = int((time.time() - start_time) * 1000)

        # Clean response (strip <think> tags)
        response_text = clean_response(result["response"])

        return ChatResponse(
            success=True,
            response=response_text,
            model=model.value,
            provider="runpod",
            latency_ms=latency_ms,
            usage=result.get("usage"),
        )

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error generating response: {str(e)}",
        )


@router.delete("/chat/history")
async def clear_history(
    x_user_id: str = Header(..., alias="X-User-ID"),
):
    """Clear conversation history for a user"""
    await redis_service.clear_conversation(x_user_id)
    return {"success": True, "message": "Conversation history cleared"}


@router.get("/chat/history")
async def get_history(
    x_user_id: str = Header(..., alias="X-User-ID"),
    limit: int = 20,
):
    """Get chat history from Firestore"""
    history = await firestore_service.get_chat_history(x_user_id, limit=limit)
    return {"success": True, "history": history}
