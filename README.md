# Operator Pass

Offline face ID for people who work alongside robots. A concept built for Vingroup's robotics companies (VinRobotics, VinMotion, VinDynamics); it is not affiliated with them.

The app runs face detection and recognition entirely on the phone. The release build has no INTERNET permission. Faces are stored only as encrypted embeddings (vectors), never as photos.

## What works now

| Area | Status |
|---|---|
| Owner setup | Consent → guided face registration → 6-digit backup PIN. Nothing is saved until the last step. |
| Face login | 4 of the last 6 frames must match the owner, with exactly one face in view. After 5 failed scans only the PIN works. 5 wrong PINs lock the PIN for 60 s, and the lockout doubles each time. The app relocks after 30 s in the background (configurable). Screenshots are blocked on the lock and registration screens. |
| Register a new face | 5 prompts × 2 quality-checked samples. Outliers are dropped. A face that is already registered is **blocked**. A verify step follows. The owner confirms (face or PIN) before every registration. |
| Operators | List with initials (no photos). Rename, change role, re-scan, add appearance, delete. |
| Change my face / PIN | Settings. Each needs a fresh face scan or the PIN first. The old face is replaced in one DB transaction. |
| Activity log | Unlocks, failures, registrations, duplicates blocked, settings changes. |
| Dev Lab | Live boxes, the crop the embedder sees, per-stage timings, quality values and the live score against every registered person (for calibrating thresholds). |
| Next phases | Robot View (tracker + HUD), Cell Check-in, liveness. |

## Models

Put the model files here. The app reads them at launch, so no code change is needed:

| File | Path | Required |
|---|---|---|
| Face detector (YOLO) | `assets/models/face_detector.tflite` | Yes |
| Face embedder (e.g. MobileFaceNet) | `assets/models/face_embedder.tflite` | No, but needed for real security |

- **Detector:** the input size (320, 640, …) and output layout are read from the model. The app supports YOLO11 `[1, 5, N]`, transposed `[1, N, 5]`, and YOLO26 end-to-end `[1, 300, 6]`, with normalized or pixel coordinates and float or int8 input/output. The current file is the 640 px `yolo11` export from the `train` run.
- **Embedder:** expects an `S×S×3` RGB input normalized as `(x − 127.5) / 128`, and a `D`-dimensional output. 112×112 with 128-d or 192-d output is typical. Models with a batch of 2 get the face and its mirror image, and the two embeddings are summed. Check the weights' license.
- **Without an embedder** a built-in LBP texture matcher stands in so the whole flow can be tested. It is **not secure**: lookalikes and photos can pass. While it is in use, the app shows a "Test matcher" warning.
- **Swapping the embedder:** every embedding is stored with the model's fingerprint. After a swap, people registered with the old model are marked "Needs re-scan". The owner unlocks with the PIN and re-scans in Settings. Thresholds are stored per model.
- After adding a model, rebuild the app (`flutter run`). Hot reload doesn't pick up new assets.

### Calibrating thresholds

Defaults are a starting point: MobileFaceNet-style unlock ≥ 0.60 and label ≥ 0.50; placeholder unlock ≥ 0.70. To calibrate:

1. Register yourself and at least 5 other people.
2. In Dev Lab, watch your score and theirs in different light.
3. In Settings, set **Unlock** above every score another person ever reached, plus a margin.

## Architecture

```
lib/
  main.dart                 Bootstrap (DB + models) → ProviderScope → router
  app/                      theme, go_router with the lock guard, Riverpod providers
  core/ml/                  FrameData, fused YUV sampler, YOLO decode + NMS, TFLite
                            detector/embedder, LBP placeholder, quality, matcher,
                            ml_worker (isolate that owns both interpreters)
  core/auth/                lock controller, PIN service (PBKDF2), enrollment
                            session, face vote, owner frame check
  data/                     SQLCipher database, identities, events, settings
  features/                 setup, unlock (+ re-auth), enrollment, home,
                            operators, settings, activity, dev_lab
  widgets/                  live camera view, scan ring, face overlay, PIN pad
legacy/                     the original prototype pages (not compiled)
```

- **Pipeline:** camera YUV → ML isolate → fused rotate/letterbox/normalize → YOLO → NMS → largest face → embedding → cosine match on the UI isolate. Frames are dropped while the worker is busy, and only the worker touches the interpreters.
- **Storage:** an SQLCipher DB with a random 256-bit key in the Android Keystore (flutter_secure_storage). The PIN is stored as PBKDF2-HMAC-SHA256 (100k iterations, random salt). Cloud backup and device transfer are disabled.

## Run

```bash
flutter pub get
flutter test
flutter run            # a physical Android phone (API 26+); emulators have no useful front camera
```

## Licenses

Ultralytics YOLO is AGPL-3.0, which is fine for a portfolio demo. A commercial product would need an Enterprise license or another detector. Many public face-embedding weights (for example InsightFace's) are licensed for non-commercial research only. Without liveness detection, face login is a convenience lock: a good photo of the owner may pass.
