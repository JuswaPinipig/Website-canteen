---
name: NovaLunch Canteen Design System
description: Institutional iOS light glassmorphism design system for Saint Joseph College Canteen
colors:
  primary: "#7B1E22"
  primary-hover: "#5C1016"
  accent-gold: "#D97706"
  neutral-bg: "#F8FAFC"
  surface-glass: "rgba(255, 255, 255, 0.85)"
  text-primary: "#0F172A"
  text-secondary: "#64748B"
  border-glass: "rgba(226, 232, 240, 0.8)"
  success: "#059669"
  danger: "#E11D48"
  warning: "#D97706"
typography:
  display:
    fontFamily: "Outfit, Inter, sans-serif"
    fontSize: "2.25rem"
    fontWeight: 700
    lineHeight: 1.2
  headline:
    fontFamily: "Outfit, Inter, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "Inter, sans-serif"
    fontSize: "0.95rem"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Inter, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 600
    lineHeight: 1
rounded:
  sm: "8px"
  md: "12px"
  lg: "20px"
  full: "9999px"
spacing:
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "#FFFFFF"
    rounded: "{rounded.md}"
    padding: "12px 24px"
  button-primary-hover:
    backgroundColor: "{colors.primary-hover}"
---

# Design System: NovaLunch Canteen Portal

## Overview

**Creative North Star: "Institutional iOS Light Glassmorphism"**

The NovaLunch design system delivers an airy, highly legibile, iOS-inspired light glassmorphism interface tailored for Saint Joseph College (SJC). Designed for multi-role efficiency (Students, Parents, Cashiers, and Admins), it combines crisp translucent white surfaces, soft ambient elevation shadows, and SJC Crimson branding for a state-of-the-art campus dining experience.

**Key Characteristics:**
- Translucent light frosted glass panels (`rgba(255, 255, 255, 0.85)`) with backdrop blur (`12px` to `20px`).
- Institutional SJC Crimson (`#7B1E22`) paired with vibrant Amber Gold (`#D97706`) accents.
- Soft continuous curvature cards (`rounded-2xl`) and pill-shaped interactive controls (`rounded-full`).
- High-contrast slate typography (`#0F172A`) using Google Fonts Outfit & Inter.

## Colors

The palette establishes an authoritative, clean institutional atmosphere anchored in light slate tones and SJC Crimson.

### Primary
- **SJC Institutional Crimson** (`#7B1E22`): Used for primary action buttons, key metrics, active tab indicators, and brand focal points.
- **Deep Crimson Hover** (`#5C1016`): Hover state for interactive primary controls.

### Secondary
- **Amber Gold Accent** (`#D97706`): Secondary brand accent used for premium tier badges, e-wallet balances, and star ratings.

### Neutral
- **Light Slate Canvas** (`#F8FAFC`): The clean root canvas background.
- **Light Glass Surface** (`rgba(255, 255, 255, 0.85)`): Translucent frosted container cards with backdrop blur.
- **Primary Text** (`#0F172A`): High-contrast dark slate text for headings and primary content.
- **Secondary Text** (`#64748B`): Muted slate gray for labels, timestamps, and metadata.
- **Light Glass Border** (`rgba(226, 232, 240, 0.8)`): Hairline border stroke defining translucent card bounds.

### Named Rules
**The 10% Crimson Accent Rule.** Crimson accent is reserved for primary actions, current active tabs, and key badges. High contrast ensures immediate visual hierarchy.

## Typography

**Display Font:** Outfit, Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif
**Body Font:** Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif
**Character:** Clean, highly legible sans-serif with geometric precision and balanced letter spacing.

### Hierarchy
- **Display** (700 weight, 2.25rem, 1.2 line-height): Main dashboard header titles and key balance numbers.
- **Headline** (600 weight, 1.5rem, 1.3 line-height): Section headers and card block titles.
- **Title** (600 weight, 1.125rem, 1.4 line-height): Item titles, modal headers, and table section titles.
- **Body** (400 weight, 0.95rem, 1.5 line-height): Standard transaction logs, table data rows, and description copy.
- **Label** (600 weight, 0.75rem, uppercase tracking-wider): Table column headers, pill badges, and input label tags.

## Layout

- **Spatial Grid:** 8px base rhythm (`8px`, `16px`, `24px`, `32px`).
- **Container Structure:** Max width `1280px` for desktop dashboards with responsive fluid padding (`16px` mobile, `32px` desktop).
- **Flex & Grid:** CSS Grid for dashboard card panels (`repeat(auto-fit, minmax(300px, 1fr))`) and Flexbox for navbar headers and status bars.

## Elevation & Depth

NovaLunch uses iOS-style light glass depth combined with ambient soft shadows.

### Depth Strategy
- **Layer 0 (Canvas):** Light Slate `#F8FAFC` background.
- **Layer 1 (Card Containers):** Translucent `rgba(255, 255, 255, 0.85)` with `16px` blur, `1px` border `rgba(226, 232, 240, 0.8)`, and shadow `0 4px 16px -2px rgba(15, 23, 42, 0.04)`.
- **Layer 2 (Floating Modals / Dropdowns):** Elevated `rgba(255, 255, 255, 0.95)` with `20px` blur and modal shadow `0 20px 50px -12px rgba(15, 23, 42, 0.25)`.

### Named Rules
**The Light Frosted Glass Rule.** Elevation is created using translucent white backgrounds, backdrop blurs (`12px` to `20px`), hairline borders, and soft ambient drop shadows.

## Shapes

- **Card Containers:** `rounded-2xl` (`20px` border-radius).
- **Buttons & Inputs:** `rounded-xl` (`12px` border-radius).
- **Pill Badges & Tabs:** `rounded-full` (`9999px` border-radius).

## Components

### Buttons
- **Shape:** `rounded-xl` (12px radius).
- **Primary:** Background SJC Crimson `#7B1E22`, text `#FFFFFF`, padding `12px 24px`, font-weight 600.
- **Hover:** Darkens to `#5C1016` with subtle `scale(1.02)` press feedback.
- **Secondary / Glass:** Background `rgba(255, 255, 255, 0.9)`, border `rgba(226, 232, 240, 0.8)`, text `#0F172A`.

### Navigation
- **Style:** Left fixed dark maroon sidebar (`#1D0507`) or top sticky translucent glass bar with role selector tabs and profile badges.

### Cards / Containers
- **Corner Style:** `rounded-2xl` (20px).
- **Background:** `rgba(255, 255, 255, 0.85)` with `backdrop-filter: blur(16px)`.
- **Border:** `1px solid rgba(226, 232, 240, 0.8)`.

### Inputs / Fields
- **Style:** Background `#FFFFFF`, border `rgba(226, 232, 240, 0.9)`, text `#0F172A`, radius `12px`, padding `10px 16px`.
- **Focus:** Border turns SJC Crimson (`#7B1E22`) with subtle focus ring glow.

## Do's and Don'ts

### Do:
- **Do** use translucent white backgrounds (`rgba(255, 255, 255, 0.85)`) with `backdrop-filter: blur(16px)` for iOS-style light glass cards.
- **Do** keep text high-contrast (`#0F172A` for primary titles, `#64748B` for secondary labels).
- **Do** use pill-shaped badges (`rounded-full`) for role indicators, payment status, and category filters.

### Don't:
- **Don't** use heavy dark void backgrounds or harsh black borders in light mode.
- **Don't** use generic unstyled browser inputs or sharp 0px square corners.
- **Don't** saturate screens with multiple competing accent colors.
