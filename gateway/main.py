"""
IAMONEAI Gateway - FastAPI Backend
Connects to RunPod LLMs, Upstash Redis, and Firestore
"""
import os
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.routers import chat, health

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup - lazy initialize services
    print("Starting IAMONEAI Gateway...")
    try:
        from app.services.redis_service import redis_service
        from app.services.firestore_service import firestore_service
        await redis_service.connect()
        firestore_service.connect()
    except Exception as e:
        print(f"Warning: Service initialization error (non-fatal): {e}")
    yield
    # Shutdown
    print("Shutting down IAMONEAI Gateway...")
    try:
        from app.services.redis_service import redis_service
        await redis_service.disconnect()
    except Exception:
        pass


app = FastAPI(
    title="IAMONEAI Gateway",
    description="AI Gateway API connecting to RunPod LLMs",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for now
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(health.router, tags=["Health"])
app.include_router(chat.router, prefix="/api", tags=["Chat"])


@app.get("/")
async def root():
    return {
        "service": "IAMONEAI Gateway",
        "version": "1.0.0",
        "status": "running",
    }


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)
