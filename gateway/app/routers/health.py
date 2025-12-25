"""
Health Router - Health check endpoints
"""
from fastapi import APIRouter

from app.services.llm_service import llm_service, LLMModel
from app.services.redis_service import redis_service
from app.services.firestore_service import firestore_service


router = APIRouter()


@router.get("/health")
async def health_check():
    """
    Basic health check endpoint
    """
    return {
        "status": "healthy",
        "service": "iamoneai-gateway",
    }


@router.get("/health/detailed")
async def detailed_health_check():
    """
    Detailed health check with all service statuses
    """
    redis_status = await redis_service.health_check()
    firestore_status = await firestore_service.health_check()
    llama3_status = await llm_service.health_check(LLMModel.LLAMA3)
    nemotron_status = await llm_service.health_check(LLMModel.NEMOTRON)

    all_healthy = all([
        redis_status.get("status") in ["healthy", "not_configured"],
        firestore_status.get("status") in ["healthy", "not_configured"],
    ])

    return {
        "status": "healthy" if all_healthy else "degraded",
        "service": "iamoneai-gateway",
        "components": {
            "redis": redis_status,
            "firestore": firestore_status,
            "llm_llama3": llama3_status,
            "llm_nemotron": nemotron_status,
        },
    }


@router.get("/health/ready")
async def readiness_check():
    """
    Readiness check for Kubernetes/Cloud Run
    """
    # Check critical services
    redis_status = await redis_service.health_check()
    firestore_status = await firestore_service.health_check()

    # We consider the service ready if core services are available
    # LLM endpoints are external and don't affect readiness
    is_ready = all([
        redis_status.get("status") != "error",
        firestore_status.get("status") != "error",
    ])

    if is_ready:
        return {"status": "ready"}
    else:
        return {"status": "not_ready", "reason": "Core services unavailable"}


@router.get("/health/live")
async def liveness_check():
    """
    Liveness check for Kubernetes/Cloud Run
    """
    return {"status": "alive"}
