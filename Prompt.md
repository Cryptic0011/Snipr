# Prompt

# Project Blueprint: Open Source Screen Utility (Project [[Snipr]])

## Mission Statement

## Create a lightweight,  local-first macOS screen utility Called Snipr. It should match the power of **CleanShot X** but and the aesthetic and command-driven UI of **Raycast**. The goal is to be a free local version of cleanshot x. I would like to take its key features that can be done locally and create an app.

  
---

  

## Tech Stack

- **Native macOS:** Swift 6.0+ / SwiftUI

- **Screen Engine:** ScreenCaptureKit & Vision Framework

- **Design Inspiration:** Raycast (Minimalist, high-density, dark mode, keyboard-first)

  
---


## Architecture Requirements (For AI Agent)


### 1. The Global Overlay Controller

- Maintain a lifecycle-managed list of all displays.

- When triggered, show a transparent `NSPanel` for area selection.

- **Constraints:** Must handle multi-monitor setups without latency.

  
### 2. The Command Palette (Raycast UI)

- **Shortcut:** `Cmd + Shift + Space`.

- **View:** A search bar with a results list.

- **Actions:** - `Capture Area` (Hotkey: `Cmd+Shift+4`)

- `Capture Window` (Hotkey: `Cmd+Shift+W`)

- `Record Screen` (Hotkey: `Cmd+Shift+R`)

- `OCR Text Recognition` (Hotkey: `Cmd+Shift+O`)

- `Open Recent History`

  
### 3. The Quick Access Overlay

- When a capture is taken, display a 160x100px thumbnail in the bottom-right.
- Thumbnail should support **Drag-and-Drop** into other applications.
- Thumbnails stack like in cleanshot c
- **Double Click:** Open the Annotation Editor.

### 4. Annotation Canvas

- Tools: Arrow, Rect, Circle, Text, Blur, Pixelate, Step (Numbers).

- **Style:** Use a Linear-style color palette (Slate, Sky, Ruby, Emerald).

- High-priority: **Blur and Pixelate** for sensitive data protection.

  

---


## Rules of the "Vibe"

1. **Performance is King:** No Electron. No heavy frameworks. Pure Swift.

2. **Minimalist UI:** No rounded buttons with large shadows. Sharp corners (4px-8px radius), high contrast, SF Symbols only.


**1. The Stack: "Collector Mode" Workflow**  
The goal is to move away from "one shot, one save" and toward a "batching" mentality.  

- **Vertical Offset Stacking:** When multiple captures are taken, they should stack in the corner with a slight offset (3-5 pixels) to show depth. This mimics a physical pile of photos.  
    
- **Hover Expansion:** Hovering over the stack should expand it into a vertical or grid list. In a Raycast-inspired UI, this should look like a sleek sidebar with thin borders and heavy background blur.  
    
- **Batch Actions:** From the stack, you should be able to trigger commands like:  
    • **"Save All to Folder"**: Silently dumps everything into your local directory.  
    • **"Combine into PDF/Stitch"**: Great for documentation or bug reports.  
    • **"Clear Stack"**: Immediate wipe for privacy.  
    
- **Drag-and-Drop Batching:** You should be able to click and drag the _entire stack_ into an app (like Discord or a code editor) to upload all files at once.  
    

**2. Elaborating on Core Feature Enhancements**  
To make this an "amazing utility," we need to push the existing features into power-user territory.  
**Advanced Scrolling Capture**  
CleanShot’s scrolling capture is industry-leading because it handles stitching perfectly.  

- **Implementation:** Use a vision-based stitching algorithm. As the user scrolls, the app takes rapid-fire screenshots and compares pixel rows to find overlaps.  
    
- **Raycast Twist:** Instead of a complex UI, trigger "Start Scrolling Capture" from the command bar. Use a minimalist progress bar at the top of the screen to show how much vertical real estate has been captured.  
    

**The "Pin" Feature (Reference Overlays)**  
This is a game-changer for developers and designers.  

- **Functionality:** Right-click a thumbnail in the stack and select "Pin." This moves the screenshot out of the stack and creates a floating, borderless, semi-transparent window that stays on top of all other apps.  
    
- **The Shine:** Allow the user to adjust the opacity of the pinned window with the scroll wheel. This lets you "trace" or reference code/UI from one window while working in another.  
    

**Instant OCR (Text Recognition)**  
Since you are building for a local-first environment, this is where you beat the competition on speed.  

- **Workflow:** Press the OCR shortcut, select an area, and the text is immediately in your clipboard. No popup, no notification, just a subtle haptic or sound cue.  
    
- **Raycast Integration:** A command like "Show OCR History" could list the last 10 text captures in a Raycast-style list for easy re-copying.  
    


**4. Visual Layout Inspiration**  
The interface should feel "invisible" until it is needed. Use sharp corners (4px radius max) and a color palette that favors deep grays (`#1c1c1f`) and high-contrast accents like emerald or sky blue for the active selection.