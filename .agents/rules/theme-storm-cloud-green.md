---
description: Design system and color palette rules for update_me (Storm Cloud Green theme).
alwaysApply: true
---

# Design System: Storm Cloud Green 🌲🌊☁️

Mood: **Moody, Mono, Ocean, Forest, Intimate, Minimalist Scandinavian.**

## 1. Color Palette Tokens

| Role | Hex Code | Dart Color | Purpose / Usage |
| :--- | :--- | :--- | :--- |
| **Background / Canvas** | `#4E5A54` | `Color(0xFF4E5A54)` | Main screen background, surface canvas, scaffold. |
| **Primary Accent** | `#6E7A70` | `Color(0xFF6E7A70)` | Active buttons, chips, borders, highlighted icons, tab indicators. |
| **Secondary / Deep Surface** | `#2E3832` | `Color(0xFF2E3832)` | Card containers, bottom navigation bars, frosted glass backing, deep contrast. |
| **Text & Supporting Accent** | `#8E9A8E` | `Color(0xFF8E9A8E)` | Body text, subtle borders, inactive icons, metadata timestamps. |
| **High-Contrast Text / Highlight**| `#E8ECE9` | `Color(0xFFE8ECE9)` | Primary headlines, bold titles, crisp white-mint text for legibility. |

---

## 2. Frosted-Glass & Widget Overlay Specifications

For homescreen widgets and modal bottom sheets:
- **Frosted Glass Blur**: Backdrop filter with `sigmaX: 10`, `sigmaY: 10`.
- **Glass Tint**: `#2E3832` with `0.45` to `0.65` opacity (`rgba(46, 56, 50, 0.55)`).
- **Glass Border**: Subtle `1px` stroke using `#8E9A8E` with `0.20` opacity.
- **Top Metadata Scrim**: Linear gradient from `#2E3832` (70% opacity) to `Colors.transparent` to ensure location & time badges are 100% readable over any bright background photo.

---

## 3. Typography & Shapes
- **Corner Radii**:
  - Homescreen Widget: `22dp` (Material You standard).
  - In-App Cards & Buttons: `16dp` - `20dp`.
- **Typography Hierarchy**:
  - Titles: Crisp `#E8ECE9`, font-weight 600+.
  - Captions & Subtitles: `#8E9A8E`, clean geometric sans-serif.
