# 🚀 Pikastartti

Nopeat ohjeet päästä alkuun kehityksen kanssa.

## 1. Python-palvelin (HTTP)

```bash
cd Python
pip install -r requirements.txt
python3 pitch_service_http.py
```

Palvelin käynnistyy osoitteessa: `http://127.0.0.1:8000`

## 2. Flutter-sovellus

Toisessa terminaalissa:

```bash
cd Flutter/skittapp
flutter pub get
flutter run
```

Valitse laite (iOS simulator, Android emulator, tai desktop)

## 3. Testaa

1. Paina sovelluksessa **"Aloita viritys"**
2. Puhu mikrofoniin tai soita kitaraa
3. Näet RMS-arvon päivittyvän reaaliajassa

## 🔧 Vianmääritys

### "Python service not healthy"
- Varmista että `pitch_service_http.py` on käynnissä
- Tarkista että portti 8000 on vapaana

### "Mikrofonilupa evätty"
- **iOS**: Hyväksy mikrofonilupa kun sovellus pyytää
- **Android**: Hyväksy mikrofonilupa asetuksista
- **macOS**: System Preferences → Security & Privacy → Microphone

### "Import numpy could not be resolved"
- Python-virhe: asenna riippuvuudet `pip install -r requirements.txt`

## 📖 Lisätietoja

- Flutter-koodi: `Flutter/skittapp/lib/`
- Python-palvelin: `Python/`
- Täysi dokumentaatio: `README.md`

## 🎯 Dev-tila (yksinkertainen UI)

Jos haluat pelkän RMS-näytön ilman täyttä UI:ta, vaihda `main.dart`:ssa:

```dart
// Poista kommentointi main.dart:n lopusta ja käytä MyDevApp:ia
```

## 📱 Tuetut alustat

- ✅ iOS (iPhone/iPad)
- ✅ Android
- ✅ macOS
- ⬜ Linux (tulossa)
- ⬜ Windows (tulossa)
