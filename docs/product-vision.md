# Product vision

## Vision

Saywing should feel like a small native macOS system feature: press a hotkey, mark visible text, and hear it in a natural voice without any further dialog.

## Positioning

> **Read aloud & dictate on your Mac.**
>
> **Hear text. Write with your voice.**

German:

> **Vorlesen & Diktieren für macOS.**
>
> **Text hören. Mit der Stimme schreiben.**

The project is not a full screen reader, not a document library and not a cloud TTS platform. The product idea covers two explicit actions: reading aloud and dictating. Reading aloud and local German/English dictation are integrated in the development build. Dictation integration was approved on 2026-10-13; broader compatibility and publication remain to be verified. Saywing never records automatically, does not guarantee support for every text field, and has no guaranteed release date.

## Core promises

1. **Open source:** data flows, network access and model integration can be publicly audited.
2. **Local by design:** the official build includes the local default model. After installation, OCR and TTS run entirely on the Mac.
3. **Full control:** no account, no cloud sync, no telemetry in the official build and no history by default.
4. **Natural voice:** modern local neural TTS rather than relying only on macOS system voices.
5. **Minimal friction:** one gesture from visible text to playback.

## Target audiences

- people with reading strain, dyslexia or ADHD who do not need a full screen reader;
- knowledge workers who want to listen to short passages from PDFs, presentations, tickets, chats or videos;
- privacy-conscious users in research, medicine, law or business;
- German- and English-speaking users, and later language learners.

## Deliberate boundaries

Saywing must not be marketed as a replacement for VoiceOver. Semantic navigation, recognition of interface controls and complete non-visual system operation are outside the scope of the first product.

## MVP success criteria

The MVP is convincing only if it:

1. sounds noticeably more natural than Apple's system TTS;
2. subjectively starts speaking immediately once the model is warm;
3. is at least as easy to use as established screen OCR tools;
4. works without a network connection and without a separate model setup after installation;
5. can reliably cancel the running operation at any time.
