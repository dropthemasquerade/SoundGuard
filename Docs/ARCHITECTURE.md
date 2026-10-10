# SoundGuard Architecture

Cyberpunk-style local sound recognition and persistent alarm for iPhone.

Minimum iOS: **17.0** (Observation, SwiftData, SwiftUI `fullScreenCover` lifecycle).
First-party APIs only: SwiftUI, AVFoundation, Accelerate, UserNotifications, Core Haptics, SwiftData.

## 1. Feature list (v1)

- Record a reference sound (0.3–8 s) or import wav/m4a/mp3/aiff/caf.
- Preview, rename, delete, and mark one active target.
- Arm listening on the microphone after permission.
- Local feature matching (MFCC + cosine similarity), not byte compare and not RMS-only.
- Configurable threshold, consecutive-hit count, energy gate, sound profile.
- On match: enter **ALARMING**, full-screen UI, looping alarm audio, haptics, local notifications.
- Alarm does **not** auto-clear when the target sound stops.
- Only explicit **Acknowledge** then **Reset** clears the event.
- Duplicate start of alarm audio/haptics/notifications is rejected (single latch).
- Event log: detect time, ack time, duration, confidence, target name.
- Settings: resume listening after reset, haptics, volume, notifications, interrupt resume.
- Honest capability copy: feature matching works for stable beeps/alarms; it is not a general-purpose classifier.

Out of v1: accounts, cloud, ads, subscriptions, Core ML, watch, widgets.

## 2. System architecture

```
┌──────────────────────────────────────────────────────────┐
│ SwiftUI  (Root / Monitor / Sounds / Events / Settings /  │
│           Alarm overlay)                                 │
│                     │ observes                           │
│                     ▼                                    │
│ AppModel  ─────────────────────────────────────────────  │
│   MonitoringCoordinator  (state machine owner)           │
│     ├ AudioCaptureService        mic tap, 16 kHz mono    │
│     ├ AudioFeatureExtractor      STFT → Mel → MFCC       │
│     ├ SoundMatcher               sliding cosine score    │
│     ├ DetectionEngine            threshold / hits / latch│
│     ├ AlarmManager               idempotent alarm latch  │
│     │   ├ AlertAudioService                              │
│     │   ├ HapticsService                                 │
│     │   └ NotificationService                            │
│     ├ AudioSessionController     playAndRecord + bg audio│
│     ├ ReferenceAudioService      record / import / files │
│     ├ EventStore (SwiftData)                             │
│     └ SettingsStore (UserDefaults)                       │
└──────────────────────────────────────────────────────────┘
```

Audio DSP runs on a dedicated serial queue. UI and the state machine stay on the main actor.

## 3. State machine

```
IDLE → (permission) → MONITORING → ALARMING → ACKNOWLEDGED → RESETTING → MONITORING | IDLE
                ↘ PERMISSION_DENIED
MONITORING → INTERRUPTED → MONITORING | IDLE
```

| From | Event | To | Effects |
| --- | --- | --- | --- |
| idle | startTapped | idle | request mic permission |
| idle / permissionDenied | permissionGranted | monitoring | start capture |
| * | permissionDenied | permissionDenied | stop capture |
| monitoring | targetDetected | alarming | stop capture, start alarm, persist |
| alarming | acknowledgeTapped | acknowledged | stop alarm output, persist ack |
| alarming / acknowledged | resetTapped | resetting | stop alarm, persist reset |
| resetting | resetCompleted | monitoring or idle | start capture if resumeAfterReset |
| monitoring | stopTapped | idle | stop capture |
| monitoring | interruptionBegan | interrupted | pause capture |
| interrupted | interruptionEnded | monitoring | start capture (if enabled) |
| alarming | targetDetected | alarming | ignore (no stacked players) |
| resetting | resetTapped | resetting | ignore |

Launch restore: an unacked stored event re-enters `alarming`; an acked unrestored event re-enters `acknowledged`. Force-quit stops audio; the latch is restored when the user opens the app.

## 4. Xcode layout

```
SoundGuard/
  SoundGuard.xcodeproj
  SoundGuard/                 app target
    App/  Audio/  Alarm/  Monitoring/  Persistence/
    Core/Models  Core/State
    UI/Theme  UI/Components  UI/Screens
    Assets.xcassets           AppIcon from appIcon.png
    Resources/alarm_loop.wav
  SoundGuardTests/
  Docs/ARCHITECTURE.md
```

## 5. Module interfaces

See Swift sources. Contract summary:

- `AudioCaptureService.start/stop` → Float32 16 kHz mono buffers.
- `ReferenceAudioService` records/imports, writes Documents/References, builds `ReferenceTemplate`.
- `AudioFeatureExtractor.append` → `[AudioFrameFeatures]` (MFCC 13, energy).
- `SoundMatcher.score` → cosine similarity in `[0, 1]`.
- `DetectionEngine.process` → optional `DetectionResult` once, then latched.
- `MonitoringCoordinator` is the only object that mutates `AppPhase`.
- `AlarmManager.start` is idempotent; `stop` is idempotent.
- `EventStore` / `SettingsStore` are the persistence façades.

## 6. Minimum iOS

**iOS 17.0**, iPhone, portrait. Xcode 15.2+.

## 7. Permissions and Info.plist

| Key | Why |
| --- | --- |
| `NSMicrophoneUsageDescription` | Capture and record |
| `UIBackgroundModes: audio` | Keep `AVAudioEngine` / alarm player alive when locked or backgrounded |
| Local notifications | Authorization request at runtime; no Info.plist usage string |
| Privacy manifest | UserDefaults (CA92.1), file timestamps (C617.1) |

No extra entitlements. No network.

## 8. Background limits (do not over-claim)

| Situation | Expected behavior |
| --- | --- |
| Foreground listening | Supported path |
| Lock screen / background with audio session active | May continue while iOS keeps the audio session; `audio` background mode is required |
| Phone call / Siri / route change | `AVAudioSession` interruption; resume if the user enabled it |
| User force-quits | Process dies. Listening and alarm audio stop. Event can restore UI on next launch |
| Reboot | Nothing runs until the user opens the app |
| Local notifications | Best-effort; not a guaranteed continuous alarm channel |
| App Review | Background audio must be justified as active recording/playback of an alarm tool |

Battery: 16 kHz tap + MFCC on a serial queue. Listening is a continuous cost; show that in Settings copy.

## 9. Phased implementation

1. Project, icon, theme, state machine, persistence.
2. Record/import, DSP, matcher, detection, live monitor.
3. Alarm latch, full-screen UI, haptics, notifications, interruptions.
4. Device tests and threshold tuning.

v1 ships 1–3.

## 10. Test plan

**Unit (simulator):** state machine transitions, detection latch / consecutive hits, cosine of identical vs different sines, AlarmManager idempotency.

**On device:** mic permission deny/allow; record beep; arm; play the beep; alarm stays after sound ends; ack/reset; double-reset; import file; background with alarm audio; incoming call interruption; kill-and-relaunch restores unacked alarm UI.

**Matching limits:** test with the actual target, similar tones, speech, and silence. Raise threshold if false positives appear.
