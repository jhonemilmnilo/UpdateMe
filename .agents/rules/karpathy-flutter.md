---
description: Karpathy coding philosophy adapted for Flutter, Supabase, and Android Widget development in update_me.
alwaysApply: true
---

# Supreme Engineering Guidelines (update_me)

Adapted from Andrej Karpathy's core behavioral tenets, tailored specifically for **Flutter mobile engineering, Supabase backend integration, and Android Homescreen Widgets**.

---

## 1. Think Before Coding
**Don't assume. Don't hide confusion. Surface tradeoffs.**

- **Clarify Architecture First**: Bago maglapag ng code, make sure the data flow (Flutter App ⇄ Supabase DB/Storage ⇄ Firebase FCM ⇄ Android Widget) is crystal clear.
- **Surface Tradeoffs**: If an approach saves 10 lines of code but drains the user's phone battery or increases egress, point it out.
- **Ask Before Guessing**: Kapag may ambiguous user requirements, stop and ask. Don't guess.

---

## 2. Simplicity & Lean Architecture First
**Minimum code that solves the problem cleanly. Zero speculative abstraction.**

- **No Overengineered State Management**: Don't introduce 10 layers of abstractions, repositories, and interfaces for a simple 2-person couple widget. Keep business logic clear, direct, and readable.
- **Battery & Memory Vigilance**:
  - Homescreen widgets have strict memory limits on Android (RemoteViews/AppWidgets).
  - Always compress images client-side before upload (`flutter_image_compress`). Never feed raw camera snapshots into widget memory.
- **YAGNI (You Aren't Gonna Need It)**: No premature features (e.g. multi-user group chat, complex payment systems) unless explicitly requested.

---

## 3. Surgical Changes & Clean Git Diffs
**Touch only what you must. Respect existing structure.**

- When editing Flutter code, touch only the relevant widget or service.
- Never reformat or rewrite adjacent working files just because of personal style preferences.
- Keep `.env` and sensitive credentials strictly managed and never hardcoded in git.
- If an edit introduces dead imports or deprecated Flutter calls, clean them up immediately.

---

## 4. Aesthetic & Visual Excellence (The "Wow" Factor)
**Never build cheap or basic-looking UI.**

- The homescreen widget must feature:
  - 1:1 Square aspect ratio with modern rounded corners (`16-24dp`).
  - Top header badge: Location pin + timestamp with semi-transparent contrast scrim.
  - Bottom caption overlay: Frosted-glass glassmorphism effect with clean modern typography.
- In-app experience: Smooth micro-interactions, sleek dark/light theme harmony, and intuitive camera/upload preview.

---

## 5. Goal-Driven & Verified Execution
**Define success criteria before running code.**

Every multi-step milestone must follow this verification loop:
1. **Database & Storage**: Verify Supabase table insertions & public image URLs.
2. **Push Mechanism**: Verify FCM background message delivery to partner's token.
3. **Widget Lifecycle**: Verify `home_widget` successfully renders the bitmap in Android launcher without clipping or crash.
