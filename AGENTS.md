# TempoLab Development Guidelines

## Project Overview

TempoLab is a native metronome application for musicians.

The application targets:

- iPhone
- iPad
- macOS

The project uses Swift and SwiftUI.

The main goals of the application are:

1. Accurate metronome playback
2. Tap Tempo
3. Adjustable click pitch
4. Automatic song tempo detection
5. Practice-oriented metronome features
6. A simple and musician-friendly user interface

---

# Technology

Use the following technologies unless there is a strong technical reason not to.

- Swift
- SwiftUI
- AVFoundation
- Accelerate
- XCTest

Use Apple native frameworks whenever possible.

Avoid third-party dependencies unless explicitly requested.

---

# Platform Support

The application must support:

- iOS
- iPadOS
- macOS

Share as much source code as reasonably possible between platforms.

Avoid platform-specific implementations unless required.

When platform-specific code is necessary, use appropriate conditional compilation such as:

#if os(iOS)

or

#if os(macOS)

Keep platform-specific code isolated.

---

# Architecture

Use a lightweight MVVM-style architecture.

UI code must not directly contain audio-processing logic.

Separate responsibilities into:

Views
ViewModels
Audio / Services
Models
Utilities

Suggested structure:

TempoLab
├── App
├── Views
├── ViewModels
├── Audio
├── Models
├── Utilities
└── Resources

Views should focus on presentation.

ViewModels should manage UI-related state and user actions.

Audio processing must be implemented separately from SwiftUI views.

---

# Metronome Timing

Timing accuracy is a critical requirement.

Do not implement the actual metronome click timing using:

- Timer
- DispatchSourceTimer
- asyncAfter
- SwiftUI animation timing

These may be used for non-critical UI updates, but not as the primary audio clock.

Use AVAudioEngine and AVAudioPlayerNode.

Schedule audio using audio sample time whenever possible.

The audio engine must remain independent from the SwiftUI rendering loop.

---

# Audio Architecture

The preferred architecture is:

AVAudioEngine
↓
AVAudioPlayerNode
↓
Main Mixer
↓
Audio Output

Metronome click sounds should preferably be generated as PCM buffers.

Avoid relying on bundled audio files unless there is a clear benefit.

The click sound generator should support configurable pitch.

---

# Metronome Requirements

The initial supported BPM range is:

30–300 BPM

The application should support:

- Start
- Stop
- BPM change
- Tap Tempo
- Time signatures
- Accent on the first beat
- Adjustable click volume
- Adjustable click pitch

Changing BPM while the metronome is running should not require restarting the entire application.

---

# Time Signatures

Initially support:

- 2/4
- 3/4
- 4/4
- 5/4
- 6/8

Represent time signatures using a dedicated model rather than raw strings whenever practical.

---

# Tap Tempo

Tap Tempo should use multiple recent taps rather than only two taps.

Prefer:

- median interval
- trimmed mean
- another robust statistical method

Avoid using a simple average if it makes the calculation too sensitive to accidental taps.

If there is a long pause between taps, reset the Tap Tempo session.

---

# Click Pitch

The user should be able to change the perceived pitch of the metronome click.

Prefer generating the click waveform directly rather than changing audio playback rate.

The implementation should eventually support a configurable frequency range.

Example:

300 Hz – 2000 Hz

The accent beat may use a different frequency than normal beats.

---

# Tempo Detection

Automatic tempo detection will be implemented later.

It must remain independent from the metronome engine.

The intended processing pipeline is approximately:

PCM input
↓
windowing
↓
frequency analysis
↓
spectral flux
↓
onset detection
↓
autocorrelation
↓
tempo candidate ranking

Use the Accelerate framework where appropriate.

Initial detection range:

50–220 BPM

The detector should consider common half-time and double-time ambiguities.

Examples:

60 / 120
80 / 160
100 / 200

Tempo detection results should eventually include:

- detected BPM
- confidence
- alternative tempo candidates

---

# Testing

Audio algorithms and tempo calculations should be testable independently from the UI.

Use XCTest.

Important logic should have unit tests, particularly:

- Tap Tempo calculation
- BPM calculations
- Tempo detection
- Click scheduling calculations

Tempo detection tests should eventually use synthetic click tracks.

Example test tempos:

60
80
100
120
140
160
180
200 BPM

---

# Code Quality

Prefer clear and maintainable Swift over overly clever implementations.

Do not create unnecessary abstractions.

Use descriptive names.

Keep files focused on one primary responsibility.

Prefer small types over very large classes.

Avoid force unwraps unless there is an exceptional and clearly justified reason.

Handle errors explicitly when practical.

---

# Swift Concurrency

Follow modern Swift concurrency practices.

UI state updates should occur on the MainActor.

Audio callbacks and real-time audio work should not perform expensive work on the main thread.

Avoid unnecessary Task creation in audio-critical code.

Be careful about thread safety between:

- SwiftUI
- ViewModels
- AVAudioEngine callbacks

---

# Real-Time Audio Rules

Do not perform expensive operations inside real-time audio callbacks.

Avoid:

- memory allocations where possible
- disk I/O
- logging every audio callback
- UI updates directly from audio callbacks
- heavy FFT calculations on the audio render thread

If processing is expensive, copy or queue required data and process it outside the real-time audio thread.

---

# UI Philosophy

The primary screen should remain simple.

Musicians must be able to operate the metronome quickly during practice.

Prioritize:

- large BPM display
- large Start / Stop control
- clear Tap Tempo control
- easy BPM adjustment
- minimal visual clutter

Do not over-design the UI during early development.

Functionality and reliability come first.

---

# Development Process

Implement features incrementally.

Do not attempt to build the entire application in one task.

Preferred implementation order:

1. Basic UI
2. State management
3. Metronome audio engine
4. Tap Tempo
5. Time signatures and accents
6. Click pitch
7. Practice modes
8. Microphone input
9. Tempo detection
10. Presets and persistence

Each task should leave the project buildable.

---

# Before Making Large Changes

Before making a significant architectural change:

1. Inspect the existing implementation.
2. Explain briefly why the change is needed.
3. Prefer the smallest change that solves the problem.
4. Avoid rewriting unrelated working code.

---

# After Each Task

After completing a task:

1. Build the project if possible.
2. Fix build errors caused by the change.
3. Report which files were created or modified.
4. Briefly explain the implementation.
5. Mention any known limitations.
6. Suggest the next logical implementation step.

Do not claim that a build or test passed unless it was actually run successfully.
