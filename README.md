<p align="center">
  <img src="Resources/AppIcon-1024.png" width="150" alt="IPA Beam Icon">
</p>

<h1 align="center">IPA Beam</h1>
<p align="center"><b>IPA-Dateien per USB‑C oder WLAN aufs iPhone beamen – für Windows, macOS und als iPhone-App.</b></p>

<p align="center">
  <img src="docs/screenshots/desktop/installing.jpg" width="900" alt="IPA Beam – Installation läuft">
</p>

---

## 🖼️ Screenshots

| Bereit | App wird gebeamt |
|---|---|
| ![Bereit](docs/screenshots/desktop/ready.jpg) | ![Installation](docs/screenshots/desktop/installing.jpg) |
| **Installiert** | **Drag & Drop** |
| ![Erfolg](docs/screenshots/desktop/success.jpg) | ![Drop](docs/screenshots/desktop/drop.jpg) |

Native macOS-Version (SwiftUI):

| | |
|---|---|
| ![macOS Bereit](docs/screenshots/macos/ready.jpg) | ![macOS Erfolg](docs/screenshots/macos/success.jpg) |

iPhone-App:

| Beam | Installation läuft | Quellen & Updates | Einrichtung |
|---|---|---|---|
| <img src="docs/screenshots/ios/ready.jpg" width="200"> | <img src="docs/screenshots/ios/run.jpg" width="200"> | <img src="docs/screenshots/ios/sources.jpg" width="200"> | <img src="docs/screenshots/ios/setup.jpg" width="200"> |

## 📱 iPhone-App (Ordner [`ios/`](ios)) – ohne PC

- **IPA öffnen** aus Dateien, Safari, Mail oder AirDrop („Öffnen in IPA Beam“)
- **Signieren direkt auf dem iPhone** – zsign ist in die App eingebaut (mit OpenSSL)
- **Installieren direkt auf dem iPhone** – über den iOS-eigenen Installer:
  1. *Mehr → Installation einrichten → Profil laden* (Safari lädt das Profil)
  2. Profil in den Einstellungen installieren
  3. *Allgemein → Info → Zertifikatsvertrauenseinstellungen* → „IPA Beam Local CA“ einschalten

  Das Zertifikat wird **auf deinem iPhone erzeugt**, gilt **nur für 127.0.0.1**, und der Hauptschlüssel wird sofort verworfen.
- **Quellen & Updates ohne neue .ipa**: App-Listen im AltStore/SideStore-Format abonnieren. IPA Beam erkennt neue Versionen und aktualisiert per Tipp (laden → signieren → installieren).
- **Ablauf-Anzeige**: mit kostenloser Apple‑ID laufen Signaturen nach 7 Tagen ab – „Erneut installieren“ erneuert sie.
- **Erste Installation von IPA Beam selbst** (einmalig mit PC/Mac): Artefakt **IPA-Beam-iOS-unsigned** aus *Actions → Build iOS App* mit IPA Beam Desktop (Neu signieren an) aufs iPhone beamen.
- Selbst bauen: `cd ios && ./scripts/fetch-zsign.sh && brew install xcodegen && xcodegen generate && open IPABeam.xcodeproj`

> ⚠️ Die Installation auf dem iPhone konnte noch nicht auf einem echten Gerät getestet werden (nur im Simulator gebaut).

## 📦 Zwei Versionen

| | **IPA Beam Desktop** | **IPA Beam für Mac (nativ)** |
|---|---|---|
| Plattform | **Windows 10/11** und macOS | macOS 14+ |
| Technik | Electron, Ordner [`desktop/`](desktop) | SwiftUI, Ordner [`Sources/`](Sources) |
| iPhone-Verbindung | Apple-Gerätedienst (usbmuxd) direkt – **USB‑C & WLAN** | Apple `devicectl` (Xcode) oder libimobiledevice – **USB‑C & WLAN** |
| Signieren | Zertifikat **.p12** + **.mobileprovision** (via zsign) | Zertifikat aus dem Schlüsselbund + Profil (via codesign) |
| Download | Actions → **Build Desktop** → `IPA-Beam-Windows` / `IPA-Beam-Desktop-macOS` | Actions → **Build macOS App** → `IPA-Beam-macOS` |

## ✨ Funktionen

- **Drag & Drop** einer `.ipa` irgendwo ins Fenster, Doppelklick im Explorer/Finder oder Strg/⌘+O
- **3D-iPhone in der Mitte**, das der Maus folgt – die App wird per Lichtstrahl „hineingebeamt“, Fortschritt wie beim App‑Store‑Download direkt auf dem Homescreen
- **Automatische Geräteerkennung** über USB‑C und WLAN mit Verbindungs-Badge
- **App-Vorschau**: Icon, Name, Bundle‑ID, Version, Größe, minimale iOS‑Version (ohne Entpacken)
- **Neu signieren** mit eigenem Zertifikat & Profil, Prüfung ob dein iPhone im Profil steht
- **Live-Fortschritt**: Schritt-Timeline + Terminal‑Protokoll, verständliche Fehlermeldungen mit Lösungstipp
- **Bibliothek & Verlauf** der zuletzt verwendeten IPAs und Installationen

## 🪟 Windows – Einrichtung

1. **„Apple Devices“** aus dem Microsoft Store installieren (alternativ iTunes). Das liefert den Apple‑Gerätedienst, über den IPA Beam mit dem iPhone spricht.
2. `IPA-Beam-Setup-x.y.z.exe` (Installer) oder `IPA-Beam-Portable-x.y.z.exe` starten. Da die App nicht signiert ist, zeigt Windows evtl. „Der Computer wurde durch Windows geschützt“ → **Weitere Informationen → Trotzdem ausführen**.
3. iPhone per USB‑C anschließen, entsperren, **„Vertrauen“** tippen.
4. Auf dem iPhone **Entwicklermodus** aktivieren (Einstellungen → Datenschutz & Sicherheit).
5. **WLAN:** In „Apple Devices“ beim iPhone **„Dieses iPhone im WLAN anzeigen“** aktivieren – danach geht’s kabellos.

## 🍎 macOS – Einrichtung

- **Desktop-Version:** `.dmg` öffnen, App in *Programme* ziehen, beim ersten Start **Rechtsklick → Öffnen**.
- **Native Version:** `IPA-Beam.zip` entpacken, ebenso **Rechtsklick → Öffnen**. Nutzt Xcode (`devicectl`) oder `brew install libimobiledevice ideviceinstaller`.
- WLAN: Im Finder beim iPhone **„Dieses iPhone im WLAN anzeigen“** aktivieren (bzw. in Xcode „Connect via network“).

## ✍️ Signieren

iOS installiert nur Apps, die für dein Gerät signiert sind. Ist deine IPA das nicht:

- **Desktop (Windows/Mac):** Unter „Signierung“ dein Zertifikat als **.p12** (inkl. Passwort) und ein passendes **.mobileprovision** wählen. Das Passwort wird verschlüsselt im System-Schlüsselspeicher abgelegt. Optional eigene Bundle‑ID.
- **Native Mac-App:** In Xcode mit der Apple‑ID anmelden, einmal ein Projekt aufs iPhone starten – Zertifikat & Profil werden automatisch gefunden.

> Kostenlose Apple‑ID: Apps laufen 7 Tage. Mit bezahltem Developer Account (Wildcard‑Profil) 1 Jahr.

## 🛠️ Selbst bauen

```bash
# Desktop (Windows/macOS)
cd desktop
npm install
npm start                 # starten
npm run dist:win          # Windows-Installer + Portable (auf Windows)
npm run dist:mac          # macOS .dmg (auf macOS)
npm run screenshots       # Demo-Screenshots rendern

# Native macOS-App
./Scripts/build-app.sh    # erzeugt build/IPA Beam.app
```

## ⚠️ Hinweise

- **Verschlüsselte IPAs** (direkt aus dem App Store) lassen sich nicht installieren.
- Nutze die App nur für Apps, die du rechtmäßig verwenden darfst (eigene Apps, Open Source, Testbuilds).
- Verwendete Open-Source-Komponenten: [appium-ios-device](https://github.com/appium/appium-ios-device) (Apache‑2.0), [zsign](https://github.com/zhlynn/zsign) (MIT), [OpenSSL](https://github.com/krzyzanowskim/OpenSSL) (Apache‑2.0), [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (MIT), Schrift [Inter](https://rsms.me/inter/) (OFL).
