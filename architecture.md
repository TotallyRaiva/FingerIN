# FingerIN Architecture & Requirements

## Role and Objective
Act as an expert macOS developer specializing in SwiftUI, Audio, and Game Development. Our goal is to build an educational rhythm game for macOS, designed to teach finger drumming using physical MIDI pad controllers (specifically targeting 4x4 matrices like Maschine Mikro in MIDI mode).

## Tech Stack Requirements
- **Platform:** macOS App (App Sandbox enabled: USB, Network, Audio).
- **UI Framework:** SwiftUI (App lifecycle).
- **Game Engine:** SpriteKit (embedded via SpriteView for the falling notes timeline).
- **Audio Engine:** AVAudioEngine for zero-latency sample triggering and backing track playback.
- **MIDI Input:** CoreMIDI for capturing Note On/Off and Velocity events.
- **Data Persistence:** SwiftData for user profiles, key mappings, and high scores.
- **Architecture Standard:** Strict separation of concerns using Managers (Singletons or ObservableObjects).

## Project Architecture Overview
- **MIDIManager:** Listens to MIDI ports, parses incoming signals, and broadcasts internal app events.
- **AudioManager:** Handles two streams — playing the background track and triggering sample .wav files instantly upon receiving pad hits.
- **GameScene (SpriteKit):** Handles the visual timeline, spawning notes falling towards a hit line. Needs to sync precisely with the audio track.
- **ScoreManager:** Calculates timing accuracy (Perfect, Good, Miss) comparing MIDIManager hits with GameScene node positions.
- **DataManager:** Manages SwiftData models to store accuracy history, streaks, and pad mappings.
