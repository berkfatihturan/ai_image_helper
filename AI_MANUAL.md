# AI Image Helper - API Usage Manual for AI Agents

Welcome, AI Agent. This manual describes how to use the **AI Image Helper API**, an engine designed to give you "eyes" on a Windows machine.

By default, Large Language Models (LLMs) and autonomous agents cannot "see" the operating system in a structured way—they only see raw pixels in a screenshot. This API solves this by performing deep UI tree extraction via `uiautomation` and generating a strict JSON layout map of the screen, resolving issues like occluded (hidden) windows, Z-index overlapping, and invisible background elements.

## 🚀 Core Endpoints

The API is served via FastAPI. The host and port will vary depending on your execution environment (e.g., `http://localhost:8003`).

### 1. Local Extraction: `GET /api/v1/ui/extract`
*   **Purpose:** Extracts the UI element tree from the **local** machine where the API server is currently running.
*   **Behavior:** Runs a deep UI tree scan using `uiautomation`. It computes bounding boxes, center coordinates, and Z-orders for all visible elements. It automatically filters out occluded (hidden behind other windows) elements.
*   **Returns:** A nested JSON structure containing windows and their valid interactive child elements.

### 2. Remote Extraction: `POST /api/v1/ui/extract/remote`
*   **Purpose:** Extracts the UI element tree from a **remote** network machine completely *agentlessly*.
*   **How it works:** You provide SSH credentials in the JSON payload. The server connects via SSH, uploads a static Python payload (`ui_scanner.py`), executes it via `psexec` acting as the remote desktop user (bypassing Session 0 isolation), and retrieves the result.
*   **Payload Example:**
```json
{
  "host": "192.168.1.50",
  "username": "WindowsUser",
  "password": "SecretPassword",
  "port": 22
}
```
*   **Returns:** Exact same JSON structure as the local extraction.

### 3. Visual Map: `GET /api/v1/ui/map`
*   **Purpose:** Retrieves an image (`ui_map_visual.png`) where bounding boxes and component names are drawn directly over a blank canvas. 
*   **Usage:** You can use this image in tandem with your prompt to visually verify if the spatial coordinates mapped in the JSON align with your understanding of the screen.

---

## 🛠️ Understanding the JSON Data Structure

When you call `/extract` or `/extract/remote`, the API returns a response containing the `data` array.

### The UI Group (Window Layer)
The top level of the `data` array represents "Windows" (or the Desktop/Taskbar) layered by `z_index`.
*   `z_index = 0..N`: Application windows. The lower the Z-Index, the closer it is to the foreground.
*   `z_index = 1`: The Windows Taskbar (reserved specific layer).
*   `z_index = 99990`: The Desktop Background & Icons (Base layer).

```json
{
  "pencere": "Google Chrome",
  "z_index": 10,
  "renk": [120, 200, 50],
  "kutu": [0, 0, 1920, 1080],
  "elmanlar": [ ... ]
}
```
*   `pencere`: Title of the window.
*   `kutu`: `[Left, Top, Right, Bottom]` coordinates of the window frame.

### The Element Level (Interactive Layer)
The `elmanlar` array contains the actionable UI items *inside* that window.

```json
{
  "tip": "Button",
  "isim": "Submit",
  "koordinat": {
    "x": 500,
    "y": 300,
    "genislik": 100,
    "yukseklik": 40
  },
  "merkez_koordinat": {
    "x": 550,
    "y": 320
  }
}
```
*   `tip`: The control type (e.g., `Button`, `Edit`, `MenuItem`, `ListItem`).
*   `isim`: The human-readable label/name.
*   `merkez_koordinat`: The absolute **X, Y pixel coordinates**. 
    *   **CRITICAL AI ACTION:** If you decide you need to click the "Submit" button, you must instruct your mouse-control tools to click at the exact `(x, y)` provided in `merkez_koordinat` (e.g., Click at `550, 320`).

---

## 🧠 Occlusion Engine (Map-Reduce)

One of the largest hurdles for AI Vision is knowing what elements are *actually visible*. If Notepad is open on top of Chrome, standard automation APIs will still list Chrome's buttons underneath. 

This API runs a complex spatial Map-Reduce algorithm on the server before responding:
1.  It flattens every element to its absolute Screen X/Y rects.
2.  It checks the element's Z-Index.
3.  If an element's center coordinate is mathematically bounded inside the rectangle of a window with a *stronger* (lower) Z-Index, the element is marked as **Occluded (Hidden)** and automatically purged from the JSON.
4. You only ever receive elements that are physically naked to the user's eye and safe to click.

---

## 📝 Best Practices for AI Workflow

1.  **Extract:** First call the extraction endpoint to get the screen state.
2.  **Filter/Search:** Parse the JSON response. Look for element `tip`s that match what you want to do (e.g., look for an `Edit` tip if you want to type, or a `Button` tip to click).
3.  **Coordinate Mapping:** Take the `merkez_koordinat` (X, Y) of the desired element.
4.  **Execute:** Pass those exact absolute coordinates to your PyAutoGUI, Powershell, or OS-native mouse/keyboard tools to interact with the screen. 
5.  **Re-Extract:** The UI state changes immediately after a click. Always trigger a fresh `/extract` call before taking your next action.
