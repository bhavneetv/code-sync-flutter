# Code Sync – Flutter App

This repository contains the **Flutter wrapper application** for Code Sync.  
It provides a native app experience for mobile and desktop platforms while loading the main Code Sync web editor.

---

## Main Project Repository

The core Code Sync project (web app, backend logic, and runtime integration) is hosted here:

👉 https://github.com/bhavneetv/codesync

---

## How to Run the Flutter App Locally

### Prerequisites
- Flutter SDK (stable channel)
- Android Studio / Xcode / Windows desktop setup (as needed)
- A working internet connection

Verify Flutter installation:
```bash
flutter doctor
flutter run --dart-define=APP_URL=https://codesyncioo.netlify.app/
flutter build apk --release --dart-define=APP_URL=https://codesyncioo.netlify.app/
```

