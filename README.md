# KitaranViritys

Sovellus äänen- ja puheenkäsittelyyn / kitaran viritykseen. Hybridipohjainen taajuus-/aikatasopitchdetector toteutettu Dartilla.

## Projektin rakenne

```
Flutter/skittapp/          # Flutter-sovellus
  lib/
    core/
      audio/
        audio_recorder.dart      # PCM16-kehysten kaappaus mikrofonista
      models/
        pitch_result.dart        # Pitch-detektorin tulosrakenne
    features/
      tuner/
        presentation/
          tuner_page.dart        # Päänäkymä (UI-logiikka, EMA-smoothing)
          widgets/               # Mittarit ja visualisoinnit
        application/
          pitch_engine.dart      # HPS/THS/MPM-pitchdetektori
        domain/                  # Tilat ja presetit
    utils/                       # Apuluokat (logger, throttler)
    app/                         # App wrapper
    main.dart                    # Entry point
  PITCH_ENGINE_EXPLAINED.md    # Algoritmin dokumentaatio

Python/                    # Vanhat Python-palvelimet (ei enää käytössä)
  HPS.py, HPS_real.py, HPS_file.py  # Alkuperäiset Python-prototyypit
  pitch_service_*.py                # Vanhat IPC-palvelimet
  requirements.txt, README.md
```

## Arkkitehtuuri

### Audio Pipeline

1. **AudioRecorderService** kaappaa mikrofonista PCM16-dataa (48 kHz, mono)
2. Puskuroi tasapituisiksi kehyksiksi (4096 näytettä = ~85 ms)
3. **TunerPage** lähettää kehykset **HpsPitchEngine**:lle (Dart)
4. Pitch-moottori analysoi ja palauttaa tuloksen (f0, cents, confidence)
5. UI päivittyy attack hold + EMA-smoothing -logiikalla

### Pitch Detection Engine (Dart)

**HpsPitchEngine** toteuttaa hybridipohjaisen f0-estimoinnin:

#### Auto Mode (ei nappia painettuna)
- **HPS (Harmonic Product Spectrum)**: 50–1000 Hz laaja haku
- Kertoo spektrit (orders 2–5) → korostaa harmoniset
- Parabolic refinement (QIFFT) → sub-bin tarkkuus

#### Pressed Mode (kielipainike aktiivinen)
- **THS (Targeted Harmonic Sum)**: ±120 centtiä kohteen ympärillä
- 1/k harmoninen painotus + local median whitening
- 121 kandidaatin grid search (2 centin askelilla)
- **MPM (McLeod Pitch Method)** fallback heikoille signaaleille
  - NSDF aikatasossa kun THS conf < 0.45
  - Blendaa 60% THS + 40% MPM tarvittaessa
- Octave guard: testaa 2× ja 0.5× frekvensseillä

#### Smoothing (UI-taso)
- **Attack hold**: 150 ms jäädytys kun RMS hyppää >6 dB
- **EMA-smoothing**: α ≈ 0.22 (~200 ms aikavakio)
- Display gate: näytä vain kun conf ≥ 0.55

**Tarkkuus**:
- Auto mode: ±0.3–0.6 Hz (≈±6–12¢ @ E2)
- Pressed mode: tyypillisesti ≤±5¢ ~300 ms jälkeen (sub-cent mahdollinen puhtaalla signaalilla)

Katso tarkempi selitys: [`PITCH_ENGINE_EXPLAINED.md`](Flutter/skittapp/PITCH_ENGINE_EXPLAINED.md)

## Käyttöönotto

### 1. Flutter-riippuvuudet

```bash
cd Flutter/skittapp
flutter pub get
```

### 2. Aja Flutter-sovellus

```bash
cd Flutter/skittapp
flutter run
```

**Huom:** Python ei enää tarvita – kaikki DSP-logiikka on toteutettu Dartilla (`pitch_engine.dart`)

## Platform-oikeudet

- **Android**: `RECORD_AUDIO` (AndroidManifest.xml) ✅
- **iOS**: `NSMicrophoneUsageDescription` (Info.plist) ✅
- **macOS**: `com.apple.security.device.microphone` (entitlements) ✅

## Toteutetut ominaisuudet

1. ✅ Audio-puskurointi ja kehysten lähetys (48 kHz, mono, 4096 samples)
2. ✅ HPS-pitchdetektori (auto mode: 50–1000 Hz)
3. ✅ THS-pitchdetektori (pressed mode: ±120¢ kohteen ympärillä)
4. ✅ MPM time-domain fallback heikoille signaaleille
5. ✅ Nuotintunnistus ja cents-laskenta
6. ✅ Octave guard (2×/0.5× testaus)
7. ✅ Attack hold (150 ms) + EMA-smoothing (α=0.22)
8. ✅ UI: NeedleGauge, kielipainikkeet, confidence-gating

## Seuraavat vaiheet

- ⬜ Lisää spektri/waveform-visualisoinnit
- ⬜ Tallenna virityspresettejä
- ⬜ Lisää vaihtoehtoisia viritysjärjestelmiä (Drop D, DADGAD, jne.)
- ⬜ Optimoi suorituskyky (profiloi FFT/THS/MPM-ajat)
- ⬜ Lisää unit-testit pitch_engine.dart:lle

## Testaus

### Flutter-sovelluksen testaus

```bash
cd Flutter/skittapp
flutter run
```

1. Paina "Aloita viritys"
2. Testaa **Auto Mode**: soita mikä tahansa nuotti → sovellus tunnistaa sen
3. Testaa **Pressed Mode**: valitse kielipainike → soita kyseinen kieli → näet cents-eron
4. Tarkkaile confidence-arvoa: vihreä (≥0.7), keltainen (0.55–0.7), punainen (<0.55)

### Pitch Engine -yksikkötestaus

```bash
cd Flutter/skittapp
flutter test test/pitch_engine_test.dart  # (jos toteutettu)
```


