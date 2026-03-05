# EonCode

> AI-driven kodningsagent och utvecklingsmiljö för iOS + macOS

EonCode ersätter Claude Code CLI + Cursor + GitHub med en enhetlig app som körs på iPhone och Mac med delad kodbas.

---

## Kom igång

### Krav
- macOS 14+ / iOS 17+
- Xcode 15.2+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Anthropic API-nyckel

### Installation

```bash
# Klona repot
git clone https://github.com/Terrorbyte90/Eon-Code-v2.git
cd Eon-Code-v2

# Generera Xcode-projekt
chmod +x generate-xcode.sh
./generate-xcode.sh
```

Alternativt manuellt:
```bash
brew install xcodegen
xcodegen generate --spec project.yml
open EonCode.xcodeproj
```

### iCloud-setup
1. Öppna `EonCode.xcodeproj` i Xcode
2. Välj target `EonCode-iOS` → Signing & Capabilities
3. Lägg till ditt Team ID
4. Aktivera: iCloud (CloudKit + iCloud Drive), Keychain Sharing
5. Upprepa för `EonCode-macOS`

### API-nyckel
Starta appen → Inställningar → API-nycklar → Lägg in Anthropic-nyckel

---

## Arkitektur

```
EonCode/
├── Shared/           # Delad kod (iOS + macOS)
│   ├── Models/       # Datamodeller
│   ├── Services/     # Affärslogik & API
│   │   ├── ClaudeAPI/    # Anthropic API-klient
│   │   ├── Agent/        # Agent-motor med verktyg
│   │   ├── Sync/         # iCloud + Bonjour + HTTP
│   │   ├── Versioning/   # Versionshantering
│   │   ├── ProjectIndex/ # Filindexering
│   │   ├── Keychain/     # API-nyckelhantering
│   │   └── Voice/        # ElevenLabs TTS
│   ├── Views/        # SwiftUI-vyer
│   └── Utilities/    # Hjälpfiler
├── macOS/            # macOS-specifik kod
│   ├── Terminal/     # Shell-exekvering
│   ├── Xcode/        # xcodebuild-integration
│   ├── FileSystem/   # Filhantering
│   └── Background/   # Bakgrundsdaemon
└── iOS/              # iOS-specifik kod
    ├── InstructionComposer.swift  # iOS → Mac kommandokö
    └── OfflineManager.swift       # Offline-hantering
```

## Synk-metoder (3 redundanta)

| Prioritet | Metod | Beskrivning |
|-----------|-------|-------------|
| 1 | **iCloud Drive** | Primär, alltid aktiv, fungerar offline |
| 2 | **Bonjour/P2P** | Lokal WiFi, snabbt, ingen server |
| 3 | **Lokal HTTP** | REST-server på port 52731, iOS ansluter via IP |

## Funktioner

- **Claude AI-integration** — Haiku/Sonnet/Opus med streaming
- **Agent-motor** — Autonoma uppgifter med verktygsanrop (läs/skriv filer, terminal, xcodebuild)
- **Self-healing builds** — Bygg → fel → fixa → bygg, automatiskt upp till 20 iterationer
- **Projektversioner** — Automatiska snapshots vid varje ändring
- **iOS som mobil arbetsstation** — Koda på iPhone/iPad, köa kommandon till Mac
- **Kostnadsvisning** — Anthropic-kostnad i SEK per svar, session och historik
- **Syntax highlighting** — Swift, Python, JS/TS, HTML, CSS, JSON, YAML, Markdown
- **iCloud Keychain** — API-nycklar krypterade och synkade mellan enheter
- **ElevenLabs TTS** — Valfri uppläsning av agentens svar
- **Global sökning** — Full-text i alla projekt
- **Markdown-preview** — Live-rendering av README och docs

## Modeller & priser

| Modell | Input | Output | Användning |
|--------|-------|--------|------------|
| Haiku 4.5 (default) | $1/MTok | $5/MTok | Daglig kodning |
| Sonnet 4.5 | $3/MTok | $15/MTok | Komplexa uppgifter |
| Sonnet 4.6 | $3/MTok | $15/MTok | Senaste Sonnet |
| Opus 4.6 | $15/MTok | $75/MTok | Maximalt |

---

## Licens
Privat projekt — Terrorbyte90
