# IAMONEAI Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              FRONTEND                                        │
│                      Vercel + Cloudflare (Edge/CDN)                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │  Flutter Web    │  │   Cloudflare    │  │     Vercel      │              │
│  │  (Static Build) │──│   (CDN/WAF)     │──│   (Hosting)     │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
├─────────────────────────────────────────────────────────────────────────────┤
│                              BACKEND                                         │
│                         Cloud Run (Google)                                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │  Python Gateway │  │  Chat API       │  │  Admin API      │              │
│  │  (FastAPI)      │  │  /api/chat      │  │  /api/admin     │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
├───────────────────┬───────────────────┬─────────────────────────────────────┤
│     DATABASE      │      VECTOR       │            CACHE                     │
│     Firestore     │     Pinecone      │        Upstash Redis                 │
│  ┌─────────────┐  │  ┌─────────────┐  │  ┌─────────────────────────────┐    │
│  │ Users       │  │  │ Memories    │  │  │ Session     │ Rate Limit   │    │
│  │ Chats       │  │  │ Embeddings  │  │  │ Conversation│ Temp Cache   │    │
│  │ Configs     │  │  │ Semantic    │  │  │ History     │              │    │
│  └─────────────┘  │  └─────────────┘  │  └─────────────────────────────┘    │
├───────────────────┴───────────────────┴─────────────────────────────────────┤
│                             LLM LAYER                                        │
│            Self-Hosted (RunPod) + API Providers (Smart Routing)              │
│  ┌───────────────────────────────────┐  ┌───────────────────────────────┐   │
│  │         SELF-HOSTED (RunPod)      │  │        API PROVIDERS          │   │
│  │  ┌─────────────┐ ┌─────────────┐  │  │ ┌─────────┐┌───────┐┌───────┐ │   │
│  │  │  Llama-3    │ │  Nemotron   │  │  │ │ Claude  ││ GPT-4 ││Gemini │ │   │
│  │  │  8B-Inst    │ │  70B        │  │  │ │ (Opus)  ││ Turbo ││ Pro   │ │   │
│  │  │  Chat/Gen   │ │  Classifier │  │  │ │ Complex ││Reason ││ Fast  │ │   │
│  │  └─────────────┘ └─────────────┘  │  │ └─────────┘└───────┘└───────┘ │   │
│  │  $0.20/hr GPU    $0.80/hr GPU     │  │  Pay-per-token                │   │
│  └───────────────────────────────────┘  └───────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────────────┤
│                          INFRASTRUCTURE                                      │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────┐  ┌─────────┐       │
│  │  Auth0  │  │ Datadog │  │ Sentry  │  │GitHub Actions│  │  Vault  │       │
│  │  Auth   │  │ Metrics │  │ Errors  │  │   CI/CD      │  │ Secrets │       │
│  └─────────┘  └─────────┘  └─────────┘  └─────────────┘  └─────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Service Summary

| Layer | Service | Purpose |
|-------|---------|---------|
| **Frontend** | Vercel | Flutter web hosting, edge functions |
| | Cloudflare | CDN, DDoS protection, WAF |
| **Backend** | Cloud Run | Python FastAPI containers |
| **Database** | Firestore | Users, chats, configs (NoSQL) |
| **Vector** | Pinecone | Memory embeddings, semantic search |
| **Cache** | Upstash Redis | Sessions, rate limiting, temp data |
| **LLM** | Llama-3 (RunPod) | Default chat, fast responses |
| | Nemotron (RunPod) | Intent classification, routing |
| | Claude (API) | Orchestrator, complex decisions |
| | GPT-4 (API) | Reasoning, multi-step tasks |
| | Gemini (API) | Fast execution, utility |
| **Infra** | Auth0 | User authentication |
| | Datadog | Monitoring, APM, logs |
| | Sentry | Error tracking |
| | GitHub Actions | CI/CD pipelines |
| | Vault | Secret management |

---

## LLM Layer Details

### Models Available

| Model | Provider | Role | Use Case | Cost |
|-------|----------|------|----------|------|
| **Llama-3 8B** | RunPod | Chat/Generation | Default chat, fast responses | ~$0.20/hr GPU |
| **Nemotron 70B** | RunPod | Classifier | Intent detection, routing decisions | ~$0.80/hr GPU |
| **Claude Opus** | Anthropic API | Orchestrator | Complex decisions, planning | Pay-per-token |
| **GPT-4 Turbo** | OpenAI API | Reasoning | Multi-step reasoning | Pay-per-token |
| **Gemini Pro** | Google API | Executor | Fast utility tasks | Pay-per-token |

### Routing Logic

```
User Message
     │
     ▼
┌─────────────┐
│  Nemotron   │ ◄── Classify intent
│  (RunPod)   │
└─────────────┘
     │
     ├── Simple chat ──────► Llama-3 (RunPod) - cheap/fast
     ├── Complex reasoning ─► Claude/GPT-4 (API) - quality
     └── Quick utility ────► Gemini (API) - fast/cheap
```

### Routing Groups (Admin Configurable)

| Group | Purpose | Default Models |
|-------|---------|----------------|
| **Orchestrator** | Decision making, planning | Claude Opus, GPT-4 |
| **Reasoning** | Complex multi-step tasks | GPT-4, Claude |
| **Executors** | Fast utility tasks | Gemini, Llama-3 |

---

## Data Flow

### Chat Request Flow

```
┌──────────┐     ┌───────────┐     ┌──────────┐     ┌─────────┐
│  User    │────►│ Cloudflare│────►│  Vercel  │────►│ Flutter │
│ Browser  │     │   (CDN)   │     │ (Static) │     │   App   │
└──────────┘     └───────────┘     └──────────┘     └─────────┘
                                                          │
                                                          ▼
┌──────────┐     ┌───────────┐     ┌──────────┐     ┌─────────┐
│  LLM     │◄────│  Gateway  │◄────│Cloud Run │◄────│  API    │
│ (RunPod) │     │ (FastAPI) │     │ (Google) │     │ Request │
└──────────┘     └───────────┘     └──────────┘     └─────────┘
     │                 │
     │                 ▼
     │           ┌───────────┐
     │           │  Upstash  │ ◄── Cache conversation
     │           │   Redis   │
     │           └───────────┘
     │                 │
     ▼                 ▼
┌──────────┐     ┌───────────┐
│ Response │────►│ Firestore │ ◄── Persist chat history
└──────────┘     └───────────┘
```

---

## Repository Structure

```
quirky-lamarr/
├── lib/                      # Flutter (Dart)
│   ├── admin/                # Admin dashboard
│   │   ├── screens/
│   │   ├── services/
│   │   └── widgets/
│   ├── core/                 # Shared code
│   │   ├── models/
│   │   ├── services/
│   │   └── utils/
│   └── user/                 # User app
│       ├── screens/
│       ├── services/
│       └── widgets/
├── gateway/                  # Python (FastAPI)
│   ├── app/
│   │   ├── routers/          # API endpoints
│   │   └── services/         # Business logic
│   ├── main.py
│   ├── Dockerfile
│   └── cloudbuild.yaml
├── docs/                     # Documentation
├── firebase.json             # Firebase config
├── firestore.rules           # Security rules
└── pubspec.yaml              # Flutter dependencies
```

---

## Deployment

### Flutter Web (Frontend)
```bash
flutter build web --release
firebase deploy --only hosting
```

### Gateway (Backend)
```bash
gcloud builds submit --config=gateway/cloudbuild.yaml
```

---

## Environment Variables

### Gateway (.env)
```
# RunPod
RUNPOD_API_KEY=xxx
RUNPOD_LLAMA3_ENDPOINT_ID=xxx
RUNPOD_NEMOTRON_ENDPOINT_ID=xxx

# Upstash Redis
UPSTASH_REDIS_REST_URL=xxx
UPSTASH_REDIS_REST_TOKEN=xxx

# Google Cloud
GOOGLE_CLOUD_PROJECT=app-iamoneai-c36ec
```

### Secrets (Google Secret Manager)
- `anthropic-api-key` - Claude API
- `openai-api-key` - GPT-4 API
- `gemini-api-key` - Gemini API
- `RUNPOD_API_KEY` - RunPod API
