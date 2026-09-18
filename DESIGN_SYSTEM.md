# Comprehensive UI/UX Design System Specification: Apple Human Interface Guidelines (HIG) × Anti-AI-Slop Architecture

This document establishes the design standard, algorithmic layout rules, tactile affordance criteria, and visual tokens for generating and auditing digital interfaces across the NovaLunch ecosystem. It merges Apple’s Human Interface Guidelines (HIG) with modern, high-craft institutional fintech ergonomics.

> **Mandatory Agent Directive:** Whenever tasked with refactoring, redesigning, building, or auditing any view, portal, component, modal, or stylesheet in this codebase, **all rules in this specification MUST be strictly called, considered, and applied**. These rules supersede and overwrite all previous generic or legacy UI guidelines.

---

## 1. Executive Philosophy & Anti-AI-Slop Heuristics

AI-generated interfaces frequently fail not from a lack of technical components, but from an excess of superficial decorative styling ("AI Slop"). These guidelines eliminate synthetic noise in favor of Apple’s foundational trifecta: **Clarity, Deference, and Depth**.

### The 4 Laws of Anti-AI-Slop Visual Hygiene

```
[ AI SLOP ]                                 [ HIG STANDARD ]
"Submit Top-Up Verification • ₱500.00"   ➔  "Reload ₱500.00"
(Loud paragraph explaining fees)            (Crisp 44pt pill button, zero clutter)
```

1. **Strict Zero-Emoji Policy**
   - **Rule**: Raw Unicode emojis (`🍱`, `⚡`, `🎉`, `🗑`, `⚠️`, `💡`, `📍`, `👋`, `💳`, etc.) are **strictly banned** from production components, toasts, headers, labels, badges, empty states, and table cells.
   - **Implementation**: Calibrated vector glyphs (Apple SF Symbols or Lucide SVG) rendered at optical sizes (`12px`, `14px`, `16px`, `20px`) with a fixed `strokeWidth={2}` or `medium` scale weight.

2. **Confident Copywriting (Elimination of Explanatory Clutter)**
   - **Rule**: Interfaces must not narrate their own operations. Remove repetitive subtitles, parenthetical helpers (*"Click here to..."*, *"Please note that..."*), and defensive legalistic blurbs under action headers.
   - **Implementation**: Actions are active verbs (`Reload`, `Transfer`, `Export`, `Claim`). States are single-word badges (`Active`, `Cleared`, `Locked`, `Pending`).

3. **Eradication of Browser & Platform Artifacts**
   - **Rule**: Never expose raw HTML inputs, default blue focus outlines, or operating-system form elements without custom brand styling.
   - **CSS Normalization**:
     ```css
     /* Strip native number input spinners */
     input[type="number"] {
       appearance: textfield;
       -moz-appearance: textfield;
     }
     input[type="number"]::-webkit-outer-spin-button,
     input[type="number"]::-webkit-inner-spin-button {
       -webkit-appearance: none;
       margin: 0;
     }

     /* Apple-standard brand focus ring */
     *:focus-visible {
       outline: none;
       box-shadow: 0 0 0 2px var(--color-canvas), 0 0 0 4px var(--color-accent-subtle);
       border-color: var(--color-brand-primary);
     }
     ```

4. **Surface-First Hierarchy Over Drop-Shadow Stacking**
   - **Rule**: Stop applying arbitrary heavy CSS shadows (`box-shadow: 0 20px 25px -5px rgba(0,0,0,0.1)`) to elevate elements.
   - **Implementation**: Elevation is expressed through **tinted translucent materials**, **subtle hairline borders** (`1px solid rgba(0, 0, 0, 0.08)` or `rgba(255, 255, 255, 0.12)`), and **surface contrast** (Base `#F8FAFC` vs Surface `#FFFFFF`).

---

## 2. Dmitry Sergushkin's 11 Sidebar Masterclass Heuristics

For desktop and tablet dashboard shells, sidebars must adhere to Dmitry Sergushkin’s navigation framework, mapped directly to Apple HIG navigation patterns:

| # | Masterclass Principle | HIG & Platform Implementation |
|---|---|---|
| **1** | **Content Prioritization** | Preserve core system routes and semantic icons without collapse tricks that obscure daily workflows. Route titles stay concise and single-line. |
| **2** | **Quick Search** | Integrated native search field (`bg-slate-200/60 dark:bg-slate-800/60 rounded-xl px-3 py-1.5`) placed directly below the app identifier with client-side instant filtering. |
| **3** | **Identity Capsule** | An iOS-style identity card pinned at the top or bottom displaying avatar, full name, organization, and a `ChevronsUpDown` affordance for quick role/account switching. |
| **4** | **Subtle Hierarchy & Tracking** | Section divider labels styled with uppercase micro-tracking: `text-[10px] font-bold text-slate-400 uppercase tracking-widest px-3 py-1`. |
| **5** | **System Vitality Indicator** | A dedicated telemetry pill (*e.g., "Terminal Online • Node SJC-01"*) maintaining continuous awareness of real-time server/POS connection state. |
| **6** | **Single Active Focus** | Active menu items use a calm, tinted pill selection (`bg-brand-50 text-brand-700 font-semibold rounded-xl`) rather than high-contrast solid dark slabs. |
| **7** | **Calibrated Badges** | Numeric pills truncate high numbers cleanly (`9+`, `99+`) accompanied by an accent status dot. Badges use tabular numerals (`font-variant-numeric: tabular-nums`). |
| **8** | **Adaptive Fluid Collapse** | Desktop displays show full labels; tablets gracefully transition to icon-only dock rails with instant hover tooltips positioned at `offset-x: 8px`. |
| **9** | **Predictable Grouping** | Grouping strictly follows mental models: Operational (Orders, POS), Administrative (Inventory, Analytics), and Configuration (Settings, Permissions). |
| **10** | **Keyboard Ergonomics** | Global hotkeys bound to primary destinations (`⌘1`, `⌘2`, search hotkey `⌘K`) mapped to sidebar elements with small typographic glyph tags. |
| **11** | **Minimalist Action Bar** | Sign-out and auxiliary tools sit cleanly at the bottom edge with single-stroke SVG vector icons (`Icon.LogOut`), separated by a hairline border. |

---

## 3. Apple HIG Core System Tokens & Architecture

### Typography: Spatial Scale & Sizing Rules

Typography must prioritize optical hierarchy over decorative typefaces. Pair a geometric/display font (for digits and prominent headers) with an ultra-legible system neutral font (for body and functional metadata).

```
Display Large   ➔ 34pt / 41pt line-height / Bold (Tracking: -0.4px)
Title 1         ➔ 28pt / 34pt line-height / Bold (Tracking: -0.3px)
Title 2         ➔ 22pt / 28pt line-height / Semi-Bold (Tracking: -0.2px)
Title 3         ➔ 20pt / 25pt line-height / Semi-Bold (Tracking: -0.15px)
Headline        ➔ 17pt / 22pt line-height / Semi-Bold (Tracking: -0.4px)
Body            ➔ 17pt / 22pt line-height / Regular (Tracking: -0.4px)
Callout         ➔ 16pt / 21pt line-height / Regular (Tracking: -0.3px)
Subheadline     ➔ 15pt / 20pt line-height / Regular (Tracking: -0.2px)
Footnote        ➔ 13pt / 18pt line-height / Medium (Tracking: -0.1px)
Caption 1       ➔ 12pt / 16pt line-height / Regular (Tracking: 0px)
Caption 2       ➔ 11pt / 13pt line-height / Medium (Tracking: +0.1px)
Micro/Overline  ➔ 10pt / 12pt line-height / Bold (Tracking: +0.6px, Uppercase)
```

*Font Pairing*: **Outfit** or **SF Pro Display** for Hero metrics, numeric counters, and balance amounts. **Inter** or **SF Pro Text** for labels, transactions, descriptions, and tabular lists.

### Spatial Grid & Hit Target Boundaries

- **44pt Universal Minimum Target**: Any interactive touchpoint (buttons, segmented toggles, navigation items, checkboxes) must maintain a minimum bounding box of `44 × 44 pt` to guarantee tactile accuracy.
- **The 8pt Structural Grid**: Spacers, padding, and layout offsets strictly scale in increments of 8 (`4px`, `8px`, `16px`, `24px`, `32px`, `48px`, `64px`).
- **Continuous Corner Radii (Squircle Geometry)**:
  - Modal/Sheet Shells: `rounded-3xl` (`24px` to `28px`)
  - Content Cards: `rounded-2xl` (`16px` to `20px`)
  - Input Fields & Settings Rows: `rounded-xl` (`12px` to `14px`)
  - CTAs, Steppers, and Dynamic Badges: `rounded-full` (`9999px`)

### Materials & Translucency

- **Canvas Underlay**: `#F8FAFC` (Slate Canvas) in light mode; `#0B0F17` in dark mode.
- **Frosted Glass (Vibrancy)**:
  ```css
  background: rgba(255, 255, 255, 0.85);
  backdrop-filter: blur(20px) saturate(180%);
  border: 1px solid rgba(226, 232, 240, 0.8);
  ```
- **Dark Mode Glass**:
  ```css
  background: rgba(15, 23, 42, 0.82);
  backdrop-filter: blur(24px) saturate(190%);
  border: 1px solid rgba(255, 255, 255, 0.08);
  ```

---

## 4. Component-Level Design Architecture

```
                                  [ INTERFACE PATTERNS ]
                                             │
      ┌───────────────────┬──────────────────┴─────────────────┬───────────────────┐
      │                   │                                    │                   │
[ Wallet List ]    [ Health Tile ]                    [ Settings Group ]    [ Island Pill ]
(Replaces Tables)  (Metric Progress)                  (Hairline Controls)   (Sticky Actions)
```

### Pattern A: Wallet-Style Transaction Cell (Anti-Table Pattern)

Data tables belong in administrative CSV engines. Mobile and consumer portals must display transactions as Apple Wallet-inspired visual list cells.

```
┌────────────────────────────────────────────────────────┐
│  [ Glyph ]  Primary Item or Merchant Name      ₱365.00 │
│             Aug 26 • 10:55 AM • ORD-2026-2655      (>) │
└────────────────────────────────────────────────────────┘
```

- **Left Container**: `40 × 40 px` rounded-2xl square (`bg-slate-100 dark:bg-slate-800`) framing a centered `18px` vector icon (`Icon.ShoppingBag`, `Icon.ArrowUpRight`).
- **Center Column**: Primary title in `text-[15px] font-semibold text-slate-900 dark:text-white`. Subline in `text-[13px] text-slate-500 font-normal truncate`.
- **Right Column**: Number formatted via `font-mono tabular-nums` in `text-[16px] font-bold text-slate-900 dark:text-white`, paired with a subtle muted chevron `(>)` indicator (`w-4 h-4 text-slate-400`).

### Pattern B: Apple Health Progress & Biometric Tile

Replace generic progress bars with Apple Health-style metric blocks.

```
┌────────────────────────────────────────────────────────┐
│  Calories Expended                             ( Icon )│
│  1,420 / 2,100 kcal                                    │
│  [═══════════════════════════════──────────────] 68%   │
│                                                        │
│  ┌─────────────────────────┐  ┌──────────────────────┐ │
│  │ PROTEIN                 │  │ GLUCOSE GUARD        │ │
│  │ 48g                     │  │ Optimal              │ │
│  │ 62% of target           │  │ Verified POS Shield  │ │
│  └─────────────────────────┘  └──────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

- **Primary Progress Gauge**: An `8px` rounded-full track (`bg-slate-100 dark:bg-slate-800`) with an animated fill gradient (`from-accent-500 to-brand-primary`).
- **Metric Cards**: Side-by-side sub-cards (`bg-slate-50/75 dark:bg-slate-900/50 border border-slate-200/60 dark:border-slate-800/80 rounded-2xl p-3.5`).
- **Typography**: Uppercase overline title (`text-[11px] font-bold tracking-wider text-slate-400`), prominent value (`text-xl font-extrabold text-slate-900`), and a contextual status footer (`text-[12px] text-slate-500`).

### Pattern C: iOS Grouped Settings Cell

Group related toggle switches, security parameters, and options inside unified containers with hairline dividers.

```
┌────────────────────────────────────────────────────────┐
│  ACCOUNT SECURITY                                      │
│  ┌──────────────────────────────────────────────────┐  │
│  │ (🛡) Two-Factor Authentication         [Enabled] │  │
│  │     Hardware security keys active                │  │
│  │──────────────────────────────────────────────────│  │
│  │ (💳) Auto-Reload Balance                 [Toggle]│  │
│  │     Triggers when balance drops < ₱100           │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

- **Container**: `bg-white dark:bg-slate-900 rounded-2xl border border-slate-200/80 dark:border-slate-800 overflow-hidden`.
- **Hairline Dividers**: Inner cells separated by `border-b border-slate-200/60 dark:border-slate-800/80 ml-14` (indented past the icon to mirror iOS settings).
- **Affordance Controls**: Uses genuine iOS-style toggle switches (`w-12 h-7 bg-slate-200 rounded-full transition-colors relative checked:bg-brand-primary`).

### Pattern D: Dynamic Floating Action Pill (Dynamic Island)

Eliminate full-width sticky footer bars. Use centered, floating pill containers with translucent surfaces.

```
┌──────────────────────────────────────────────────────────────────┐
│  ( 2 )  ₱450.00                   [Clear]   [ Review & Pay  → ]  │
│         Morning Recess • SJC Canteen                             │
└──────────────────────────────────────────────────────────────────┘
```

- **Wrapper**: Fixed viewport-bottom position (`bottom-6 inset-x-0 mx-auto w-[92%] max-w-lg`).
- **Material**: `bg-slate-950/90 dark:bg-black/90 text-white backdrop-blur-2xl border border-white/15 rounded-full px-5 py-3 shadow-2xl flex items-center justify-between`.
- **Item Indicator**: Compact circle badge (`w-7 h-7 rounded-full bg-white/15 flex items-center justify-center text-xs font-bold`).
- **Tactile CTA**: Brand button pill (`bg-brand-primary text-white rounded-full px-5 py-2 font-semibold text-sm active:scale-95 transition-transform`).

---

## 5. Micro-Interactions & Spring Dynamics

Apple interfaces feel physical because they operate on spring physics rather than linear CSS timings.

- **Spring Physics Formula**:
  - **Sheet / Modal Presentation**: Mass `1.0`, Stiffness `300`, Damping `30`.
  - **Button Press Feedback**: Mass `0.5`, Stiffness `400`, Damping `25`.
  - **Quick Toggles / Pills**: Mass `0.8`, Stiffness `350`, Damping `28`.

- **Universal Active State Utility**:
  ```css
  /* Apply to all interactive surfaces */
  .interactive-tap {
    transition: transform 180ms cubic-bezier(0.16, 1, 0.3, 1), 
                opacity 180ms ease, 
                filter 180ms ease;
  }
  .interactive-tap:active {
    transform: scale(0.97);
    filter: brightness(0.96);
  }
  ```

---

## 6. Comprehensive Token Reference

| Category | Token Key | Value (Light Mode) | Value (Dark Mode) | Purpose |
|---|---|---|---|---|
| **Canvas** | `canvas.bg` | `#F8FAFC` (Slate 50) | `#090D16` | Full body backdrop |
| **Surface** | `surface.card` | `rgba(255, 255, 255, 0.92)` | `rgba(15, 23, 42, 0.85)` | Elevated cards and sheets |
| **Border** | `border.hairline` | `rgba(226, 232, 240, 0.8)` | `rgba(255, 255, 255, 0.08)` | Dividers, card strokes |
| **Brand Primary** | `brand.primary` | `#7B1E22` (SJC Crimson) | `#A3282D` | Primary action anchors |
| **Brand Hover** | `brand.active` | `#631418` | `#851F23` | Pressed and focused states |
| **Text Primary** | `text.headline` | `#0F172A` (Slate 900) | `#F8FAFC` (Slate 50) | Headers and balances |
| **Text Secondary** | `text.sub` | `#64748B` (Slate 500) | `#94A3B8` (Slate 400) | Metadata and sublines |
| **Radius Base** | `radius.card` | `1.25rem` (`20px`) | `1.25rem` (`20px`) | Standard grouping cards |
| **Radius Pill** | `radius.full` | `9999px` | `9999px` | Action buttons, badges |

---

## 7. AI Design Auditor: Self-Verification Checklist

Before generating or updating any view, component, or screen, verify against this algorithmic checklist:

- [ ] **1. ZERO RAW EMOJIS**: Are all glyphs rendered via vector components (`Lucide SVG` / `SF Symbols`)?
- [ ] **2. 44PT COMPLIANCE**: Do all interactive triggers have at least `44 × 44 pt` bounding boxes?
- [ ] **3. COPY CONFIDENCE**: Has explanatory filler text below buttons and titles been stripped?
- [ ] **4. PHYSICAL FEEDBACK**: Is `active:scale-[0.97]` or equivalent spring tap feedback defined?
- [ ] **5. SQUIRCLE GEOMETRY**: Are card corners using smooth, large-radius geometry (`16px` - `24px`)?
- [ ] **6. VIBRANCY / FROST**: Do overlays use `backdrop-filter: blur()` with subtle hairline borders?
- [ ] **7. TABULAR METRICS**: Are financial values, dates, and times set to tabular numerals?
- [ ] **8. NO DATA TABLES**: Are transaction histories formatted as Apple Wallet list cells?
