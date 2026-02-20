# Prototype Details — Tech World

**Project:** Tech World
**Studio:** Enspyrco Pty Ltd
**Date:** February 2026

---

## Platform & Access

| | |
|---|---|
| **Platform** | Web (browser-based, no download required) |
| **URL** | https://adventures-in-tech.world |
| **Recommended browsers** | Google Chrome or Microsoft Edge (latest version) |
| **Also works on** | Safari, Firefox (Chrome/Edge recommended for best experience) |
| **Hardware required** | Any modern computer with a webcam and microphone |
| **Internet connection** | Required (multiplayer, AI tutor, and authentication all require connectivity) |
| **Cost to play** | Free — no account creation fees, no in-app purchases |

> **Note for assessors:** The prototype is a live multiplayer web application. It will remain accessible at the URL above throughout the assessment period. No installation, download, or special hardware is required — open the link in Chrome and you're playing.

---

## Getting Started (Step-by-Step)

### 1. Open the prototype

Navigate to **https://adventures-in-tech.world** in Chrome or Edge.

You'll see a loading screen with a progress bar while the game initialises.

### 2. Sign in

The authentication screen offers several options:

- **Email & password** — Create an account or sign in with an existing one
- **Google Sign-In** — Sign in with your Google account (one click)
- **Anonymous guest login** — Play immediately without creating an account

Any option works. Guest login is the fastest way to get into the game.

### 3. Enter the game world

After signing in, you'll enter Tech World — a top-down 2D game world. You'll see your character (an animated sprite) in the centre of the screen.

The default map is **The L-Room**, which has a background image, wall art, and two coding terminal stations (green rectangles).

### 4. Move around

**Click or tap anywhere on the map** to move your character. Your sprite will walk along a path to the destination, automatically navigating around barriers and walls. The character animates in 8 directions.

### 5. Open a coding challenge

Walk your character near a **green terminal station** (within 2 grid squares). Click or tap the terminal. A code editor panel will open on the right side of the screen, replacing the chat panel.

The terminal displays a coding challenge — for example, "Write a function that returns the sum of all elements in a list." Read the description, write your solution in Dart, and click **Submit** to send it to the AI tutor for review.

### 6. Chat with Clawd (the AI tutor)

The **chat panel** on the right side of the screen connects you to Clawd, an AI companion powered by the Claude API. Clawd joins the game as a participant.

- **Type a message** in the chat input and press Enter to send
- **Click the microphone button** to speak instead of typing (Web Speech API — Chrome only)
- Clawd responds with text and also **speaks the response aloud** (text-to-speech)
- All participants in the room can see all messages — chat is shared

Ask Clawd for help with a challenge, general coding questions, or just say hello.

### 7. See other players

Tech World is multiplayer. If another person is playing at the same time, you'll see their character sprite moving around the world. Walk within **3 grid squares** of another player and their **live video feed** will appear as a circular bubble above their character — proximity-based video chat.

> **Note:** To test multiplayer, open the prototype in two separate browser windows (or two different browsers) and sign in with different accounts. Both players will appear in the same world.

### 8. Explore the maps

Click the **map dropdown** in the toolbar (top-right) to switch between 6 maps:

| Map | What to see |
|---|---|
| **The L-Room** (default) | Background art, wall occlusion, 2 terminals |
| **The Library** | Bookshelf layout, 4 terminals, ASCII-parsed design |
| **The Workshop** | Maker space theme, 2 terminals, ASCII-parsed design |
| **Open Arena** | Open space, no barriers |
| **Four Corners** | Barrier blocks in each corner |
| **Simple Maze** | Outer walls and internal maze |

### 9. Try the map editor (optional)

Click the **grid icon** in the toolbar to open the map editor. Paint barriers, set a spawn point, and place terminals on a 50x50 grid. The game canvas updates in real time as you paint. Click the grid icon again to exit.

---

## Controls Summary

| Action | How |
|---|---|
| Move | Click/tap anywhere on the map |
| Open terminal | Click a green terminal (must be within 2 squares) |
| Submit code | Type solution in editor, click Submit |
| Chat with Clawd | Type in chat panel, press Enter |
| Voice input | Click microphone button in chat (Chrome) |
| Switch map | Map dropdown in toolbar (top-right) |
| Open map editor | Grid icon in toolbar |
| Sign out | Auth menu in toolbar (top-right) |

---

## What to Experience

For the best sense of what Tech World offers, we recommend this walkthrough (approximately 5–10 minutes):

1. **Sign in** using Google or guest login
2. **Walk around The L-Room** — notice the animated character, the wall art, and the walls your character walks behind (wall occlusion)
3. **Walk to a green terminal** and open a coding challenge — try a Beginner challenge like "Sum a List" or "FizzBuzz"
4. **Write and submit a solution** — Clawd will review your code
5. **Open the chat panel** and ask Clawd a question (e.g. "What coding challenges are available?" or "Can you explain what FizzBuzz is?")
6. **Switch maps** using the dropdown — try The Library (4 terminals, bookshelf layout) or Open Arena (open space)
7. **Open the map editor** — paint a few barriers, place a terminal, then exit

If two assessors can test simultaneously (or use two browser windows), also try:
8. **Walk near each other** to trigger proximity video chat — video bubbles appear above nearby players

---

## Technical Architecture (Brief)

| Component | Technology |
|---|---|
| **Game engine** | Flutter + Flame (Dart) |
| **Multiplayer** | LiveKit (WebRTC data channels for positions/chat, media tracks for video) |
| **AI tutor** | Claude API (Claude 3.5 Haiku) via Node.js bot on GCP Compute Engine |
| **Authentication** | Firebase Auth |
| **Hosting** | Firebase Hosting (auto-deployed from GitHub on merge to main) |
| **Voice I/O** | Web Speech API (browser-native, Chrome) |
| **Code editor** | code_forge_web with re_highlight for Dart syntax highlighting |

---

## Known Limitations

These are acknowledged gaps that the funded development phase will address:

- **No progression system yet** — Challenges can be completed but there is no tracking of which challenges you've solved, no scores, and no persistent record of progress. This is the primary game loop gap and the first deliverable in the funded roadmap.
- **No save/resume** — Closing the browser loses any in-progress work. Challenge persistence via Firebase is planned.
- **No sound** — The game is currently silent. Ambient music and interaction sound effects are a funded phase deliverable.
- **No onboarding** — New players must explore on their own. A guided first-time experience is planned.
- **Voice features require Chrome** — Speech-to-text and text-to-speech use the Web Speech API, which works best in Chrome. Other browsers may not support voice input.
- **Single hardcoded room** — All players join the same LiveKit room. Room management and multiple concurrent rooms are post-grant scope.

---

## Troubleshooting

| Issue | Solution |
|---|---|
| Page loads but stays on loading screen | Refresh the page. Check that your browser is Chrome or Edge. |
| Camera/microphone not working | Grant browser permissions when prompted. Check that no other app is using the camera. |
| Orange "Connection failed" banner | The LiveKit server may be temporarily unavailable. Refresh and try again. The game still works without LiveKit (single-player mode). |
| Terminal won't open | Walk your character closer to the terminal — you must be within 2 grid squares. |
| Chat messages not sending | Ensure you're signed in (not on the auth screen). Check your internet connection. |
| No other players visible | The prototype is live but not heavily trafficked. To test multiplayer, open a second browser window and sign in with a different account. |

---

## Contact

For technical issues accessing the prototype during assessment:

**Studio:** Enspyrco Pty Ltd
**Email:** [your email]
**Web:** [your website if applicable]
