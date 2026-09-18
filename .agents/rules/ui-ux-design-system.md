# Rule: Apple HIG × Anti-AI-Slop UI/UX Design System Specification

This rule is mandatory and permanently active for all UI/UX design, refactoring, frontend styling, and code generation across the NovaLunch ecosystem. It overwrites and supersedes all previous generic or legacy UI design guidelines.

Refer to the master document at [`DESIGN_SYSTEM.md`](file:///Users/louiseadrianvnonog/PROJMAN/Website-canteen/DESIGN_SYSTEM.md) for complete details.

---

## 1. The 4 Laws of Anti-AI-Slop Visual Hygiene
1. **Strict Zero-Emoji Policy [CRITICAL]**:
   - Raw Unicode emojis (`🍱`, `⚡`, `🎉`, `🗑`, `⚠️`, `💡`, `📍`, `👋`, `💳`, etc.) are **strictly banned** from production components, toasts, headers, labels, badges, empty states, and table cells.
   - All visual semantics must use standardized Lucide SVG vector components (`Icon.Utensils`, `Icon.MapPin`, `Icon.Package`, `Icon.AlertTriangle`, `Icon.CheckCircle2`, `Icon.Info`, `Icon.XCircle`, `Icon.Clock`, `Icon.DollarSign`, `Icon.Users`, `Icon.ShieldCheck`, `Icon.Activity`, `Icon.CreditCard`, `Icon.QrCode`, etc.) at optical sizes (`12px`, `14px`, `16px`, `20px`) with a fixed `strokeWidth={2}`.
2. **Confident Copywriting (No Explanatory Clutter)**:
   - Interfaces must not narrate their own operations. Remove repetitive subtitles, parenthetical helpers (*"Click here to..."*, *"Please note that..."*), and defensive legalistic blurbs under action headers.
   - Use active verbs (`Reload`, `Transfer`, `Export`, `Claim`) and single-word status badges (`Active`, `Cleared`, `Locked`, `Pending`).
3. **Eradication of Browser & Platform Artifacts**:
   - Strip native number input spinners (`appearance: textfield`).
   - Implement Apple-standard brand focus rings: `outline: none; box-shadow: 0 0 0 2px var(--color-canvas), 0 0 0 4px var(--color-accent-subtle); border-color: var(--color-brand-primary);`.
4. **Surface-First Hierarchy Over Drop-Shadow Stacking**:
   - Ban arbitrary heavy CSS drop shadows (`box-shadow: 0 20px 25px -5px rgba(0,0,0,0.1)`).
   - Express elevation through tinted translucent materials, subtle hairline borders (`1px solid rgba(0, 0, 0, 0.08)` or `rgba(255, 255, 255, 0.12)`), and surface contrast (Base `#F8FAFC` vs Surface `#FFFFFF`).

---

## 2. Dmitry Sergushkin's 11 Sidebar Masterclass Heuristics
1. **Content Prioritization**: Single-line concise labels for core routes without collapse tricks that obscure daily work.
2. **Quick Search**: Native search field (`bg-slate-200/60 dark:bg-slate-800/60 rounded-xl px-3 py-1.5`) below app identifier.
3. **Identity Capsule**: iOS-style identity card with avatar, name, org, and `ChevronsUpDown` role/account switcher.
4. **Subtle Hierarchy & Tracking**: Uppercase micro-tracking section labels: `text-[10px] font-bold text-slate-400 uppercase tracking-widest px-3 py-1`.
5. **System Vitality Indicator**: Live telemetry pill (*"Terminal Online • Node SJC-01"*).
6. **Single Active Focus**: Calm, tinted pill selection (`bg-brand-50 text-brand-700 font-semibold rounded-xl`).
7. **Calibrated Badges**: Truncate (`9+`, `99+`) with accent status dot and tabular numerals (`font-variant-numeric: tabular-nums`).
8. **Adaptive Fluid Collapse**: Desktop full labels; tablet icon-only dock rail with instant tooltips at `offset-x: 8px`.
9. **Predictable Grouping**: Operational, Administrative, and Configuration grouping.
10. **Keyboard Ergonomics**: Global hotkeys (`⌘1`, `⌘2`, `⌘K`) mapped with typographic glyph tags.
11. **Minimalist Action Bar**: Clean bottom edge with hairline border and single-stroke SVG vector icons.

---

## 3. Apple HIG Core System Tokens & Architecture
- **Typography Scale**: Display Large (34pt), Title 1 (28pt), Title 2 (22pt), Title 3 (20pt), Headline/Body (17pt), Callout (16pt), Subheadline (15pt), Footnote (13pt), Caption 1 (12pt), Caption 2 (11pt), Micro/Overline (10pt).
  - *Pairing*: **Outfit** (or SF Pro Display) for metrics/amounts + **Inter** (or SF Pro Text) for functional metadata.
- **Spatial Grid & 44pt Hit Target**: All interactive touchpoints must maintain a minimum `44 × 44 pt` bounding box. Spacers scale on the 8pt grid (`4px`, `8px`, `16px`, `24px`, `32px`, `48px`, `64px`).
- **Continuous Squircle Geometry**: Modals (`rounded-3xl` / 24-28px), Cards (`rounded-2xl` / 16-20px), Inputs/Rows (`rounded-xl` / 12-14px), CTAs/Badges (`rounded-full` / 9999px).
- **Materials**: Canvas underlay `#F8FAFC`, Frosted Glass `rgba(255, 255, 255, 0.85); backdrop-filter: blur(20px) saturate(180%); border: 1px solid rgba(226, 232, 240, 0.8);`. Brand Primary `#7B1E22` (SJC Crimson).

---

## 4. Component-Level Design Architecture
- **Pattern A (Wallet-Style Transaction Cell)**: Ban raw tables for transactions. Use Apple Wallet cells: `40 × 40 px` rounded-2xl icon square + bold title / muted subline + tabular-nums right-aligned amount with muted chevron.
- **Pattern B (Apple Health Progress Tile)**: 8px rounded-full gradient progress track + side-by-side metric sub-cards + uppercase overline tags.
- **Pattern C (iOS Grouped Settings Cell)**: Unified `rounded-2xl` white container with hairline inner dividers indented past the icon (`ml-14`) and genuine iOS toggle switches (`w-12 h-7`).
- **Pattern D (Dynamic Floating Action Pill)**: Translucent, centered floating pill (`bottom-6 inset-x-0 mx-auto w-[92%] max-w-lg`) with item badge, summary, and active brand button.

---

## 5. Micro-Interactions & Spring Dynamics
- Spring physics: Modals (Mass 1.0, Stiffness 300, Damping 30), Buttons (Mass 0.5, Stiffness 400, Damping 25).
- Interactive tap utility: `.interactive-tap:active { transform: scale(0.97); filter: brightness(0.96); }`.

---

## 6. Self-Verification Checklist Before Every Output
- [ ] 1. ZERO RAW EMOJIS: All glyphs rendered via vector components (`Lucide SVG`)?
- [ ] 2. 44PT COMPLIANCE: All interactive triggers have at least 44x44pt hit targets?
- [ ] 3. COPY CONFIDENCE: Explanatory filler text stripped?
- [ ] 4. PHYSICAL FEEDBACK: `active:scale-[0.97]` or spring tap feedback defined?
- [ ] 5. SQUIRCLE GEOMETRY: Card corners using smooth 16-24px radii?
- [ ] 6. VIBRANCY / FROST: Overlays using `backdrop-filter: blur()` and hairline borders?
- [ ] 7. TABULAR METRICS: Financial amounts, dates, and times formatted with tabular numerals?
- [ ] 8. NO DATA TABLES: Consumer/student histories formatted as Apple Wallet list cells?
