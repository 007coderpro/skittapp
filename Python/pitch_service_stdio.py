#!/usr/bin/env python3
"""
STDIO-versio: lukee JSON-rivejä stdinistä, kirjoittaa vastaukset stdouttiin.
Käynnistä: python3 pitch_service_stdio.py

Protokolla:
- Input: {"sr": 48000, "data_b64": "..."}
- Output: {"f0": null, "confidence": 0.0, "rms": 0.123, ...}
- Quit: {"cmd": "quit"}
"""
import sys
import json
import base64
import numpy as np

def pcm16_to_float32(b):
    """Konvertoi PCM16 bytes -> float32 array [-1.0, 1.0]"""
    x = np.frombuffer(b, dtype=np.int16)
    return x.astype(np.float32) / 32768.0

def process(data_b64, sr):
    """
    Placeholder: palauttaa RMS-tason.
    """
    raw = base64.b64decode(data_b64)
    x = pcm16_to_float32(raw)
    
    # Laske RMS
    rms = float(np.sqrt(np.mean(np.square(x))) + 1e-12)
    
    return {
        "f0": None,
        "confidence": 0.0,
        "note": None,
        "cents": None,
        "rms": rms
    }

def main():
    # Lue rivejä stdinistä
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        
        try:
            obj = json.loads(line)
            
            # Tarkista onko quit-komento
            if obj.get("cmd") == "quit":
                break
            
            # Prosessoi kehys
            sr = int(obj["sr"])
            data_b64 = obj["data_b64"]
            result = process(data_b64, sr)
            
            # Kirjoita vastaus stdouttiin
            sys.stdout.write(json.dumps(result) + "\n")
            sys.stdout.flush()
            
        except Exception as e:
            # Virhetilanne: palauta error
            sys.stdout.write(json.dumps({"error": str(e)}) + "\n")
            sys.stdout.flush()

if __name__ == "__main__":
    main()
