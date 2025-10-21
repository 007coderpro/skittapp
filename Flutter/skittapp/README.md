# skittapp

Flutter-sovellus äänen- ja puheenkäsittelyyn / kitaran viritykseen.

## Esivalmistelut

Varmista että sinulla on asennettuna:
- **Flutter SDK** (suositus: uusin stable-versio)
- **Xcode** (macOS/iOS-kehitykseen)
- **Android Studio** tai **Android SDK** (Android-kehitykseen)
- **VS Code** tai **Android Studio** (kehitysympäristö)

### Flutter-asennuksen tarkistus

```bash
flutter doctor
```

Tämä komento näyttää puuttuvat riippuvuudet ja antaa ohjeita niiden asentamiseen.

## Projektin käynnistäminen

### 1. Riippuvuuksien asennus

Projektin juurihakemistossa aja:

```bash
flutter pub get
```

Tämä lataa kaikki `pubspec.yaml`-tiedostossa määritellyt riippuvuudet.

### 2. Sovelluksen ajaminen

#### Emulaattorissa/simulaattorissa

Käynnistä ensin emulaattori tai simulaattori:

```bash
# iOS-simulaattori (macOS)
open -a Simulator

# Android-emulaattori (jos avahi-daemon on asennettu)
flutter emulators --launch <emulaattori_id>
```

Aja sovellus:

```bash
flutter run
```

#### Fyysisellä laitteella

1. Kytke laite USB-kaapelilla
2. Ota kehittäjätila käyttöön laitteessa
3. Aja: `flutter devices` (nähdäksesi kytketyt laitteet)
4. Aja: `flutter run`

#### Tiettyyn laitteeseen

```bash
flutter run -d <laite-id>
```

### 3. Hot Reload ja Hot Restart

Kun sovellus on käynnissä:
- **r** = Hot reload (päivittää UI:n säilyttäen tilan)
- **R** = Hot restart (uudelleenkäynnistää sovelluksen)
- **q** = Lopeta sovellus

## Yleiset Flutter-komennot

### Projektin puhdistus

```bash
flutter clean
```

Poistaa `build/`-hakemiston ja välimuistin. Hyödyllinen ongelmatilanteissa.

### Koodin analysointi

```bash
flutter analyze
```

Tarkistaa koodin laatuongelmat ja varoitukset.

### Testien ajaminen

```bash
flutter test
```

Ajaa kaikki yksikkö- ja widget-testit `test/`-hakemistossa.

### Sovelluksen buildaaminen

```bash
# Android APK
flutter build apk

# Android App Bundle (suositeltu Google Playhin)
flutter build appbundle

# iOS (vaatii macOS:n)
flutter build ios

# macOS desktop-sovellus
flutter build macos

# Web-versio
flutter build web
```

## Projektin rakenne

```
lib/
  main.dart           # Sovelluksen pääsisääntulo
test/
  widget_test.dart    # Esimerkki widget-testistä
android/              # Android-projektin asetukset
ios/                  # iOS-projektin asetukset
macos/                # macOS-projektin asetukset
web/                  # Web-projektin asetukset
pubspec.yaml          # Projektin riippuvuudet ja asetukset
```

## Hyödyllisiä resursseja

- [Flutter-dokumentaatio](https://docs.flutter.dev/)
- [Dart-dokumentaatio](https://dart.dev/guides)
- [Flutter Widget -katalogi](https://docs.flutter.dev/ui/widgets)
- [Pub.dev](https://pub.dev/) - Flutter/Dart -paketit

## Yleisiä ongelmia

### "Flutter command not found"

Lisää Flutter `PATH`-ympäristömuuttujaan:

```bash
export PATH="$PATH:`pwd`/flutter/bin"
```

### Cocoapods-virheet (iOS/macOS)

```bash
cd ios
pod install
cd ..
```

### Gradle-ongelmat (Android)

```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
```

## Kehitysvinkkejä

- Käytä **Hot Reload** -ominaisuutta nopeaan iterointiin
- Asenna **Flutter/Dart -laajennukset** kehitysympäristöösi
- Käytä `flutter doctor` säännöllisesti tarkistaaksesi asennuksen kunnon
- Tutki `pubspec.yaml` lisätäksesi uusia paketteja [pub.dev](https://pub.dev/):stä
