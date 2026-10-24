# Master Prompt for Figma AI: Uper Girl Mobile App

Copy and paste the prompt below directly into **Figma AI ("Make Designs")**, **Figma First Draft**, or Figma AI plugins like **Galileo AI** / **Prompt to Design**.

---

```markdown
Design a production-ready, high-fidelity iOS mobile app design system and a 5-screen flow for "Uper Girl", a women-centric ride-hailing app (inspired by Uber, DiDi, and Careem) built around reassurance, ambient safety, and calm, warm visual language.

### 1. DESIGN SYSTEM & VISUAL IDENTITY
- **Form Factor**: Mobile screens (393 x 852 px, iPhone 16 / iOS 18 standard).
- **Aesthetic**: Soft, warm, human, reassuring. Zero aggressive blacks or high-energy neon oranges. Generous 16px–24px card corner radius, full-pill (9999px) buttons, and circular 48px avatars.
- **Color Palette (Strict Tokens)**:
  * Primary (Deep Berry): #7A1F3D (Key brand elements, headers)
  * Dark Surface (Berry Dark): #4A1226 (Header backgrounds, card surfaces)
  * Secondary (Dusty Rose): #C77186 (Subheadings, borders, inactive tabs)
  * Soft Highlight (Rose Soft): #EAC7CD (Badges, subtle card fills)
  * Sharp Accent (Coral): #E2745B (Primary Action / Confirm Booking button)
  * Verified / Safe (Sage Green): #3E7A54 (Ambient verified badges, online indicators)
  * Emergency Alert (Crimson SOS): #C23B3B (Reserved STRICTLY for SOS panic button and active SOS state)
  * Background Neutral: #FAF6F7 (Warm off-white base)
  * Text Primary: #261017 (Deep warm charcoal)
  * Text Muted: #6B4E57 (Soft warm gray)
- **Typography Hierarchy**:
  * Display / Greetings: Fraunces (Serif), 32px, Bold
  * Headlines: Fraunces (Serif), 22px, SemiBold
  * Body Text: Inter (Sans-serif), 15px, Regular
  * Labels & Buttons: Inter (Sans-serif), 12px–14px, Weight 600, uppercase tracking +0.5px
  * Captions: Inter (Sans-serif), 11px, Regular
  *(For Arabic counterpart: Noto Kufi Arabic for Serif-equivalent warmth, Noto Sans Arabic for body).*

---

### 2. FIVE CORE SCREENS TO GENERATE

#### SCREEN 1: Rider Home & Map Entry ("Rider Home")
- **Top Status & Greeting**:
  - Greeting text in Fraunces 32px: "Good evening, Mona".
  - Ambient Trust Strip (Soft pill badge in Sage #3E7A54 tint with white text): "✓ Verified drivers only, always".
- **Map Viewport**:
  - Full-screen minimalist map background in warm monochromatic tones with subtle street lines.
  - Floating circular location target button on bottom-right of map.
- **Floating Bottom Search Card**:
  - White/warm-tinted card with 24px top radius and subtle drop shadow.
  - Search input with soft rose border and search icon: "📍 Where are you headed?".
  - Quick saved destination chips below: "🏠 Home", "💼 Work", "☕ Frequent".

#### SCREEN 2: Ride Selection & Upfront Fare ("Choose a Ride")
- **Top Bar**: Back chevron arrow, centered title "Choose a ride" (Fraunces 22px).
- **Map Thumbnail**: Upper half shows route polyline connecting pickup to dropoff with ETA pill "14 min".
- **Ride Options List (Auto-layout vertical cards, 12px gap)**:
  * Card 1 (Selected State - Berry border 2px, Rose Soft background #EAC7CD at 20% opacity):
    - Vehicle icon, Option Name "Standard", Sage badge "● Verified · 4 min away".
    - Upfront price: "EGP 68".
  * Card 2 (Unselected State - 1px soft border #EAC7CD):
    - Vehicle icon, Option Name "Premium", Sage badge "● Verified · 6 min away".
    - Upfront price: "EGP 110".
- **Bottom Booking Bar**:
  - Payment method pill: "💳 Visa ending 4567 (Tap to change)".
  - Large full-width pill button in Coral #E2745B with white text: "Confirm Booking".

#### SCREEN 3: Active Ride Tracking & Verification ("Ride In Progress")
- **Full-Screen Live Map**:
  - Car icon with driver avatar heading along a dusty rose route line.
- **Floating Driver & Trust Card (Top layer)**:
  - 20px rounded card with 16px padding.
  - Left: 48px circular avatar with initial "S", driver photo, and green verified checkmark.
  - Middle: Driver name "Salma A. · 3 min away", subtitle "✓ Verified · White Kia · Plate 2314".
  - Right: Rating "4.9 ★".
- **Pickup PIN Box (Center highlight)**:
  - Soft Berry tinted container with dotted border: "Share this PIN with your driver".
  - 4 large distinct numeric blocks: [ 4 ] [ 8 ] [ 2 ] [ 1 ] in bold monospace font.
- **Safety Floating Action Bar**:
  - Horizontal pill bar: Chat button (💬), Masked Call button (📞), and a prominent high-contrast SOS button (🚨 #C23B3B with white bold text).

#### SCREEN 4: Full-Screen Emergency State ("SOS Activated")
- **Urgent Emergency Canvas**:
  - High-urgency dark berry #4A1226 background with Crimson #C23B3B top hazard banner.
  - Bold header: "SOS ACTIVATED" (Fraunces 26px, white).
  - Subtitle: "Live GPS location sharing started with local response team and emergency contacts."
- **Live Contact Notification Feed**:
  - Contact 1 Card: Circular avatar "M", "Mama", status in Sage Green: "Notified · viewing location live".
  - Contact 2 Card: Circular avatar "N", "Nourhan", status in Sage Green: "Notified · viewing location live".
- **Large Thumb-Zone Action Buttons (Stacked at bottom)**:
  - Primary button (Crimson Red #C23B3B, 56px height, full-pill): "🚨 Call Police (122)".
  - Secondary button (Outlined white/rose, 48px height, full-pill): "I'm safe, cancel alert".

#### SCREEN 5: Driver Pre-Shift Liveness Gate ("Driver Shift Verification")
- **Purpose**: Prevents account sharing and verifies female driver identity before unlocking shift.
- **Header**: Back arrow, title "Verify to go online" (Fraunces 22px).
- **Body instruction**: "Align your face in the frame — confirms it's really you before every shift."
- **Biometric Scanner Frame**:
  - Centered oval camera viewfinder (220 x 280 px) with a soft Sage Green #3E7A54 scanning guide ring.
  - Subtle face mesh overlay and guidance prompt: "Look straight into camera and blink".
- **Trust Reassurance Note**: "Photos are processed securely and deleted immediately after shift verification."
- **Bottom Action**:
  - Full-width pill button in Deep Berry #7A1F3D with white text: "Verify & Go Online".

---

### 3. COMPONENT & AUTO-LAYOUT REQUIREMENTS
- Build with native Figma Auto-Layout on all frames, cards, and buttons.
- Use explicit 8px grid spacing (gaps: 8px, 12px, 16px, 24px; padding: 16px, 20px).
- Define reusable Figma Color Styles matching the exact hex codes provided above.
- Support RTL mirroring compatibility with start/end padding.
```
