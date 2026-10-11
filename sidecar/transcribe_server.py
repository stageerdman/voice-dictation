#!/usr/bin/env python3
"""Long-lived transcription sidecar for Voice Dictation.

Reads one JSON request per line on stdin and writes one JSON response per line
on stdout, keeping MLX models warm across requests so each dictation pays no
model-load cost — the low-latency pattern proven in the sibling `transcriber`
project.

Request:  {"audio_path": "/tmp/x.wav", "model": "mlx-community/parakeet-tdt-0.6b-v3", "language": "en"}
Response: {"ok": true, "text": "..."}  |  {"ok": false, "error": "..."}

All logging goes to stderr; stdout carries only protocol JSON.
"""
from __future__ import annotations

import json
import sys


def log(msg: str) -> None:
    print(f"[sidecar] {msg}", file=sys.stderr, flush=True)


# Warm model caches, keyed by backend id. Kept for the process lifetime.
_parakeet: dict[str, object] = {}


def _is_parakeet(model: str) -> bool:
    return "parakeet" in model.lower()


def _transcribe_parakeet(model_name: str, audio_path: str) -> str:
    if model_name not in _parakeet:
        log(f"loading parakeet model {model_name} …")
        from parakeet_mlx import from_pretrained

        _parakeet[model_name] = from_pretrained(model_name)
        log("parakeet model ready")
    model = _parakeet[model_name]
    result = model.transcribe(audio_path)
    # parakeet-mlx returns an object with `.text` (and per-sentence detail).
    text = getattr(result, "text", None)
    if text is None:
        text = " ".join(s.text for s in getattr(result, "sentences", []))
    return text.strip()


def _transcribe_whisper(model_name: str, audio_path: str, language: str) -> str:
    import mlx_whisper

    log(f"transcribing with whisper {model_name} …")
    # Tuned anti-hallucination options borrowed from the transcriber project:
    # condition_on_previous_text=False stops one bad window poisoning later ones.
    result = mlx_whisper.transcribe(
        audio_path,
        path_or_hf_repo=model_name,
        language=language or None,
        verbose=False,
        condition_on_previous_text=False,
        temperature=(0.0, 0.2, 0.4),
        no_speech_threshold=0.6,
        compression_ratio_threshold=2.4,
        logprob_threshold=-1.0,
    )
    return (result.get("text") or "").strip()


def handle(request: dict) -> dict:
    audio_path = request.get("audio_path")
    model = request.get("model") or "mlx-community/parakeet-tdt-0.6b-v3"
    language = request.get("language") or ""
    if not audio_path:
        return {"ok": False, "error": "no audio_path"}
    try:
        if _is_parakeet(model):
            text = _transcribe_parakeet(model, audio_path)
        else:
            text = _transcribe_whisper(model, audio_path, language)
        return {"ok": True, "text": text}
    except Exception as exc:  # report the failure, keep the process alive
        log(f"error: {exc!r}")
        return {"ok": False, "error": str(exc)}


def main() -> None:
    log("ready")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            response = {"ok": False, "error": f"bad request json: {exc}"}
        else:
            response = handle(request)
        sys.stdout.write(json.dumps(response) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
