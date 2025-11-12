# Python Pitch Service

Placeholder-palvelimet testaukseen. Myöhemmin lisätään oikea f0-laskenta.

## 🚀 Pikastartti

### 1. Asenna riippuvuudet

```bash
pip install -r requirements.txt
```

tai yksitellen:

```bash
pip install fastapi uvicorn numpy pydantic
```

### 2. Käynnistä palvelin

**HTTP-versio (suositeltu kehitykseen):**

```bash
python3 pitch_service_http.py
```

tai

```bash
uvicorn pitch_service_http:app --host 127.0.0.1 --port 8000 --reload
```

**STDIO-versio (tuotantoon):**

```bash
python3 pitch_service_stdio.py
```

### 3. Testaa palvelin

**HTTP:**

```bash
# Health check
curl http://127.0.0.1:8000/health

# Testaa process_frame (dummy data)
curl -X POST http://127.0.0.1:8000/process_frame \
  -H "Content-Type: application/json" \
  -d '{"sr": 44100, "data_b64": "AAAA"}'
```

**STDIO (manuaalinen testaus):**

```bash
python3 pitch_service_stdio.py
```

Kirjoita terminaaliin:

```json
{"sr": 44100, "data_b64": "AAAA"}
```

Paina Enter → saat JSON-vastauksen

Lopeta:

```json
{"cmd": "quit"}
```

## 📋 API-dokumentaatio

### HTTP Endpoints

**GET /health**
- Palauttaa: `{"status": "ok"}`

**POST /process_frame**

Request body:
```json
{
  "sr": 44100,
  "data_b64": "base64-encoded PCM16 data"
}
```

Response:
```json
{
  "f0": null,
  "confidence": 0.0,
  "rms": 0.0234,
  "note": null,
  "cents": null
}
```

### STDIO Protocol

**Input (JSON line):**
```json
{"sr": 44100, "data_b64": "..."}
```

**Output (JSON line):**
```json
{"f0": null, "confidence": 0.0, "rms": 0.0234, "note": null, "cents": null}
```

**Quit command:**
```json
{"cmd": "quit"}
```

## 🔧 Toiminnallisuus (placeholder)

Tällä hetkellä molemmat palvelimet:
- ✅ Vastaanottavat PCM16-äänidataa base64-enkoodattuna
- ✅ Konvertoivat PCM16 → float32 [-1.0, 1.0]
- ✅ Laskevat **RMS-tason** (äänenvoimakkuus)
- ⬜ Palauttavat placeholder-arvot muille kentille

## 📊 RMS-arvon tulkinta

- **< 0.01**: Hiljaisuus / taustaääni
- **0.01 - 0.1**: Normaali puhe
- **0.1 - 0.5**: Voimakas puhe / musiikki
- **> 0.5**: Hyvin voimakas signaali

## 🎯 Seuraavat vaiheet

1. ⬜ Lisää f0-estimointi (CREPE, YIN, pYIN)
2. ⬜ Nuotintunnistus (Hz → note name)
3. ⬜ Cents-laskenta (poikkeama lähimmästä nuotista)
4. ⬜ Luotettavuusarvio (confidence)
5. ⬜ PyInstaller-bundle tuotantoon

## 🧪 Flutter-integraatio

Flutter-sovelluksessa valitse silta `main.dart`:ssa:

```dart
// HTTP-versio (kehitys)
final bridge = PythonBridgeHttp('http://127.0.0.1:8000');

// STDIO-versio (tuotanto)
final bridge = PythonBridgeStdio('/path/to/pitch_service_stdio');
```

Käynnistä Python-palvelin ennen Flutter-sovellusta!
