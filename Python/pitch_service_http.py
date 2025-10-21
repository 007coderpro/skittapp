#!/usr/bin/env python3
"""
FastAPI-palvelin placeholder-testaukseen.
Käynnistä: uvicorn pitch_service_http:app --host 127.0.0.1 --port 8000 --reload
tai: python3 pitch_service_http.py
"""
from fastapi import FastAPI
from pydantic import BaseModel
import base64
import numpy as np

app = FastAPI()

class FrameIn(BaseModel):
    sr: int
    data_b64: str

def pcm16_to_float32(b):
    """Konvertoi PCM16 bytes -> float32 array [-1.0, 1.0]"""
    x = np.frombuffer(b, dtype=np.int16)
    return x.astype(np.float32) / 32768.0

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/process_frame")
def process_frame(payload: FrameIn):
    """
    Placeholder: palauttaa RMS-tason ja dummy-arvot.
    Myöhemmin tähän lisätään oikea f0-laskenta.
    """
    # Dekoodaa PCM16
    raw = base64.b64decode(payload.data_b64)
    x = pcm16_to_float32(raw)
    
    # Laske RMS
    rms = float(np.sqrt(np.mean(np.square(x))) + 1e-12)
    
    # Placeholder-vastaus
    result = {
        "f0": None,          # ei vielä käytössä
        "confidence": 0.0,   # placeholder
        "note": None,        # placeholder
        "cents": None,       # placeholder
        "rms": rms
    }
    return result

if __name__ == "__main__":
    import uvicorn
    print("Käynnistetään pitch_service HTTP-palvelin...")
    print("Endpoint: http://127.0.0.1:8000/process_frame")
    uvicorn.run(app, host="127.0.0.1", port=8000)

