# Known limitations

[← Back to the README](../README.md)

- `{app}` on a browser window names the tab, not the browser: it reads what
  the window's chrome says.
- Screen recordings are recognised by their English default name only; macOS
  puts no capture flag on a recording, so other languages are not detected.
- The offline titler picks salient words, which can include OCR noise; any
  assistant in the AI tab gives titles that read like titles, and
  `shotscribe eval` measures the difference.
- The Claude Code, Ollama, custom-command and endpoint titlers have been run
  end to end; the Codex, Gemini CLI and Cursor Agent presets are shipped as
  their documented invocations and are editable — the "Try it" button is the
  check. Keep a CLI's tool-denying flags, and keep the CLI itself current and
  signed: macOS will refuse a binary it recognises as malware, and ShotScribe
  then reports the failure rather than working around it.
- The window and the menu bar item are one process; a copy of the pane hosted
  in another app stands down while ShotScribe.app runs.
