<p align="center">
  <img src="Resources/AppIcon-1024.png" width="160" alt="IPA Beam Icon">
</p>

<h1 align="center">IPA Beam</h1>
<p align="center"><b>Moderne macOS‑App zum Sideloaden von .ipa‑Dateien aufs iPhone – per USB‑C oder WLAN.</b></p>

---

## ✨ Funktionen

- **Drag & Drop:** `.ipa` ins Fenster ziehen, Doppelklick im Finder oder ⌘O.
- **App‑Vorschau:** Icon, Name, Bundle‑ID, Version, Größe, minimale iOS‑Version – ohne die IPA komplett zu entpacken.
- **USB‑C & WLAN:** Geräte werden automatisch erkannt (alle 4 s) und mit Verbindungsart angezeigt.
- **Zwei Installationswege:**
  - **Apple `devicectl`** (Xcode 15+): Apples offizieller CoreDevice‑Weg, USB und WLAN.
  - **libimobiledevice** (`ideviceinstaller`): Alternative ohne Xcode, ebenfalls USB und WLAN.
- **Neu signieren mit der eigenen Apple‑ID:** Zertifikate aus dem Schlüsselbund und Provisioning‑Profile von Xcode werden automatisch gefunden. Bundle‑ID‑Anpassung, Entfernen von Erweiterungen, Signatur aller Frameworks/Extensions.
- **Live‑Fortschritt:** Fortschrittsring, Schritt‑Anzeige (Vorbereiten → Signieren → Installieren) und ausklappbares Protokoll.
- **Verständliche Fehler:** Typische iOS‑Fehler (Entwicklermodus aus, falsches Profil, verschlüsselte IPA …) werden mit Lösungstipp angezeigt.
- **Zuletzt verwendet & Verlauf** in der Seitenleiste, Einrichtungsassistent beim ersten Start.

## 📋 Voraussetzungen

| | |
|---|---|
| Mac | macOS 14 Sonoma oder neuer (Apple Silicon oder Intel) |
| iPhone | iOS 16+ empfohlen (iOS 17+ für WLAN über `devicectl`) |
| Werkzeuge | **Xcode** (empfohlen, aus dem Mac App Store) **und/oder** `brew install libimobiledevice ideviceinstaller` |

## 🚀 Installation

### Fertige App (empfohlen)
1. Im GitHub‑Repo unter **Actions → Build macOS App** den neuesten Lauf öffnen und das Artefakt **IPA-Beam-macOS** herunterladen.
2. `IPA-Beam.zip` entpacken und **IPA Beam.app** in den Ordner *Programme* ziehen.
3. Die App ist nicht notarisiert – beim ersten Start **Rechtsklick → Öffnen** wählen
   (oder im Terminal: `xattr -dr com.apple.quarantine "/Applications/IPA Beam.app"`).

### Selbst bauen
```bash
git clone <repo-url> && cd Sideloading-App-iOS
./Scripts/build-app.sh          # erzeugt build/IPA Beam.app
open "build/IPA Beam.app"
```
Zum Entwickeln: `open Package.swift` (öffnet das Projekt in Xcode) oder `swift run`.

## 📱 Einrichtung des iPhones

1. **Per USB‑C verbinden**, iPhone entsperren und **„Diesem Computer vertrauen“** tippen.
2. **Entwicklermodus aktivieren:** Einstellungen → Datenschutz & Sicherheit → Entwicklermodus → Ein (iPhone startet neu).
3. **WLAN (optional):** Einmal per Kabel koppeln, dann in Xcode → *Window → Devices and Simulators* → **„Connect via network“** – oder im Finder **„Dieses iPhone im WLAN anzeigen“**. Mac und iPhone müssen im selben Netz sein.

## ✍️ Signieren mit deiner Apple‑ID

iOS installiert nur Apps, die für dein Gerät signiert sind. Wenn deine IPA nicht bereits passend signiert ist:

1. Xcode → *Settings → Accounts* → mit deiner Apple‑ID anmelden.
2. Einmal ein beliebiges (leeres) iOS‑Projekt mit deinem Team auf dem iPhone starten – dadurch erzeugt Xcode Zertifikat **und** Provisioning‑Profil.
3. In IPA Beam **„Neu signieren“** einschalten, Zertifikat und Profil auswählen (werden automatisch vorgeschlagen).

> **Kostenlose Apple‑ID:** Apps laufen 7 Tage, max. 3 gleichzeitig, keine Wildcard‑App‑IDs → „Erweiterungen entfernen“ aktiviert lassen und ggf. eine **eigene Bundle‑ID** passend zum Profil eintragen.
> **Bezahlter Developer Account:** Ein Wildcard‑Profil (`TEAMID.*`) funktioniert für beliebige Apps, 1 Jahr gültig.

## 🧱 Aufbau

```
Sources/IPABeam
├── App/            App-Einstieg, AppModel (Zustand, Installations-Pipeline)
├── Models/         Device, IPAInfo, InstallJob
├── Services/       ProcessRunner, devicectl/libimobiledevice, IPAInspector, SigningService
└── Views/          SwiftUI-Oberfläche (Sidebar, Hauptbereich, Fortschritt, Einstellungen, Onboarding)
```

## ⚠️ Hinweise

- **Verschlüsselte IPAs** (direkt aus dem App Store gezogen) lassen sich nicht installieren – nur entschlüsselte bzw. selbst gebaute IPAs.
- Nutze die App nur für Apps, die du rechtmäßig verwenden darfst (eigene Apps, Open Source, Testbuilds).
