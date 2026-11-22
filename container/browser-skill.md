---
name: agent-browser
description: Use the installed agent-browser CLI to inspect websites, test a local web app, and interact with Chromium.
---

Open the URL with `agent-browser open URL`. Use `agent-browser snapshot -i` to list interactive elements and their references. Click a reference with `agent-browser click @e1` or fill it with `agent-browser fill @e2 "text"`. Take a fresh snapshot after navigation or a DOM change. Use `agent-browser screenshot /workspace/screenshot.png` when a visual check is needed. Close the session with `agent-browser close`. Run `agent-browser --help` for more commands.
