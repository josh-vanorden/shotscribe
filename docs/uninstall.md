# Uninstalling ShotScribe

[← Back to the README](../README.md)

```bash
osascript -e 'tell application "ShotScribe" to quit'
rm -rf /Applications/ShotScribe.app
rm -rf ~/.shotscribe                       # the search index
defaults delete com.joshvanorden.shotscribe # settings
rm -f ~/Library/Logs/ShotScribe.log
```

Renamed files keep their names and tags; nothing else is left behind. If you
turned on launch at login, the entry under System Settings › General › Login
Items goes with the app.
