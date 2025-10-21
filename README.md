# KitaranViritys

Sovellus äänen- ja puheenkäsittelyyn / kitaran viritykseen.

## Projektin rakenne

```
Flutter/skittapp/          # Flutter-sovellus (UI + äänenkaappaus)
  lib/
    core/
      audio/
        audio_recorder.dart      # PCM16-kehysten kaappaus mikrofonista
      ipc/
        python_bridge.dart       # Abstrakti rajapinta
        python_bridge_http.dart  # HTTP-yhteys (FastAPI)
        python_bridge_stdio.dart # STDIO-yhteys (prosessi)
    features/
      tuner/
        presentation/
          tuner_page.dart        # Päänäkymä
          widgets/               # Mittarit ja visualisoinnit
        application/
          tuner_controller.dart  # ChangeNotifier-pohjainen controller
        domain/                  # Tilat ja presetit
    utils/                       # Apuluokat
    app/                         # App wrapper
    main.dart                    # Entry point

Python/                    # Python-palvelimet (placeholder)
  pitch_service_http.py    # FastAPI HTTP-palvelin
  pitch_service_stdio.py   # STDIO-versio
  requirements.txt         # Python-riippuvuudet
  README.md                # Python-ohjeet
```

## Arkkitehtuuri

### Audio Pipeline

1. **AudioRecorderService** kaappaa mikrofonista PCM16-dataa (48 kHz, mono)
2. Puskuroi tasapituisiksi kehyksiksi (esim. 4096 näytettä = ~85 ms)
3. **TunerController** lähettää kehykset **PythonBridge**:lle
4. Python-palvelu analysoi ja palauttaa tuloksen (f0, RMS, jne.)
5. UI päivittyy ChangeNotifier-patternilla

### Python-sillat

- **PythonBridgeHttp**: HTTP REST API (kehitys/testaus)
  - Käynnistä: `python3 Python/pitch_service_http.py`
  - Endpoint: `http://127.0.0.1:8000/process_frame`

- **PythonBridgeStdio**: Prosessi-IPC (tuotanto)
  - Käynnistä: `python3 Python/pitch_service_stdio.py`
  - JSON-rivit stdin/stdout-kommunikaatio

### Placeholder-tila

Tällä hetkellä Python-palvelimet palauttavat vain:
- **RMS**: Äänenvoimakkuustaso
- Muut kentät (f0, note, cents): null/placeholder

## Käyttöönotto

### 1. Flutter-riippuvuudet

```bash
cd Flutter/skittapp
flutter pub get
```

### 2. Python-palvelin (valinnainen testaus)

```bash
cd Python
pip install -r requirements.txt

# HTTP-versio
python3 pitch_service_http.py

# TAI stdio-versio
python3 pitch_service_stdio.py
```

### 3. Aja Flutter-sovellus

```bash
cd Flutter/skittapp
flutter run
```

**Huom:** 
- HTTP-versio edellyttää että `pitch_service_http.py` on käynnissä
- Voit vaihtaa stdio-versioon muuttamalla `TunerPage`:n `initState`-metodissa bridge-tyyppiä

## Platform-oikeudet

- **Android**: `RECORD_AUDIO` (AndroidManifest.xml) ✅
- **iOS**: `NSMicrophoneUsageDescription` (Info.plist) ✅
- **macOS**: `com.apple.security.device.microphone` (entitlements) ✅

## Seuraavat vaiheet

1. ✅ Audio-puskurointi ja kehysten lähetys
2. ✅ Python HTTP/STDIO-sillat placeholder-datalla
3. ⬜ Toteuta oikea f0-estimointi (CREPE, YIN, pYIN)
4. ⬜ Nuotintunnistus ja cents-laskenta
5. ⬜ UI-parannukset ja visualisoinnit
6. ⬜ PyInstaller-bundle tuotantoon (stdio)

## Testaus

### Placeholder HTTP-palvelimen testaus

```bash
# Käynnistä palvelin
python3 Python/pitch_service_http.py

# Toisessa terminaalissa: testaa
curl http://127.0.0.1:8000/health

# Käynnistä Flutter-sovellus ja paina "Aloita viritys"
# RMS-arvo päivittyy kun puhut/soitat
```


