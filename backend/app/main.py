"""Aplicativo FastAPI principal do AI Tone Studio."""
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api.routes import router
from .api.pedal_references import router as references_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)

app = FastAPI(
    title="AI Tone Studio API",
    description="API para análise de áudio e geração de presets para pedaleiras M-VAVE",
    version="1.3.3",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Em produção: restringir para o app Android
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)
app.include_router(references_router)


@app.get("/")
async def root():
    return {"service": "AI Tone Studio", "version": "1.3.3", "docs": "/docs"}
