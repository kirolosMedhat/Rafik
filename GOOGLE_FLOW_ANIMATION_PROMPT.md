# Google Flow (flow.google) — Refqa Animated App Intro Guide

> **Target Platform:** Google Flow (Google Labs VideoFX / Veo AI Video Generator)  
> **URL:** [https://flow.google](https://flow.google)  
> **Output:** 3-to-4 Second Cinematic Mobile App Intro Animation (MP4 / GIF)

---

## 1. How to Use in Google Flow

1. Open **[flow.google](https://flow.google)** in your browser and sign in with your Google account.
2. In the project workspace, click **"Ingredients"** or **"Add Image Reference"** and upload our new flat mono logo:
   - File: `e:\SOFTWARE\uper girl\design\refqa_mono_logo.jpg`
   - Tag the image ingredient as: `@RefqaLogo`
3. In the prompt box, paste the exact master prompt below and select **Aspect Ratio: 9:16 (Vertical Mobile)** or **1:1**.

---

## 2. Google Flow Master Prompt

```text
Cinematic minimalist 3D motion graphics intro for a luxury mobile ride-hailing app named 'Refqa'. 

Scene starts on a clean, solid deep obsidian black-burgundy background (#12080C). 
A solid flat rose-gold (#B76E79) map location pin drops smoothly from the top center with fluid inertia and lands precisely in the center of the frame. 

Upon impact, a crisp geometric capital letter 'R' organically expands outward from the pin, perfectly encasing the location pin inside the upper loop of the 'R' matching @RefqaLogo. 

The letter 'R' settles into a bold, flat, confident silhouette. Below the emblem, the wordmark 'REFQA' in luxury serif typography and the Arabic calligraphy 'رِفقَة' smoothly fade in with elegant tracked letter-spacing. 

Subtle, high-end motion design, fluid 60fps physics, zero cheesy glow or neon flares, clean corporate luxury tech aesthetic, smooth ease-in-out easing, 4k resolution, seamless loop ready.
```

---

## 3. Alternative Motion Variations

### Variation A: Route Line Trace (Path Animation)
```text
A single glowing rose-gold vector road line traces an organic GPS route from the bottom-left corner across an obsidian dark screen. The route sweeps upward and curves in a loop to form the capital letter 'R', while the inner gap reveals a clean map location pin dropping into place. The emblem solidifies into @RefqaLogo, followed by the text 'REFQA — تنقّل آمن للمرأة'. Ultra clean, vector motion graphics.
```

### Variation B: Minimalist Morph
```text
A single minimalist location marker pin smoothly unfolds and morphs into the letter 'R' of @RefqaLogo on a solid matte dark background. Clean, modern kinetic typography, fluid transition, high aesthetic dignity.
```

---

## 4. Converting to App Assets

Once Google Flow generates your video:
1. Download the generated `.mp4` video.
2. Place it in `mobile_app/assets/videos/refqa_intro.mp4`.
3. The Flutter app can play it via `video_player` on first launch, or we can use our native Flutter code animation (using `CustomPainter` & `AnimationController`) which requires 0MB download and runs at native 60fps!
