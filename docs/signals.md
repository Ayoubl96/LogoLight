# Signals

A signal is a state that doesn't come from the menu: something outside LogoLight tells the logo what to
show. While it lasts, its pattern takes the place of the effect you chose, and when it ends the effect (or
the brightness) comes back. A Morse message in progress isn't cut off by a signal: the signal shows once
the message is done. Signals need direct control of the logo (the default on a MacBook Pro with PROLED XDR
Display) and play while the logo is on and the display is awake, like effects.

When several signals are active at once, the most important one shows: waiting for an answer, then a
finished Pomodoro, then Claude Code working, then a Pomodoro in progress.

## Claude Code

The `logolight-signal` command tells the running app what Claude Code is doing:

| Command | The logo |
|---|---|
| `logolight-signal working` | breathes slowly while Claude Code works |
| `logolight-signal waiting` | blinks while Claude Code waits for an answer or a permission |
| `logolight-signal idle` | goes back to your effect |

It sits inside the app, at `/Applications/LogoLight.app/Contents/MacOS/logolight-signal`. It succeeds and
does nothing when LogoLight isn't running, so a hook never fails because of the logo.

Connect it to Claude Code's hooks in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "/Applications/LogoLight.app/Contents/MacOS/logolight-signal working" }] }],
    "PreToolUse":       [{ "hooks": [{ "type": "command", "command": "/Applications/LogoLight.app/Contents/MacOS/logolight-signal working" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "/Applications/LogoLight.app/Contents/MacOS/logolight-signal waiting" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "/Applications/LogoLight.app/Contents/MacOS/logolight-signal idle" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "/Applications/LogoLight.app/Contents/MacOS/logolight-signal idle" }] }]
  }
}
```

`PreToolUse` brings the breathing back once you have answered a permission prompt. There is one logo and
one signal from Claude Code: with several sessions open, the last one to speak wins. A signal that nothing
ends (Claude Code was killed before its `Stop` hook) is dropped after 30 minutes.

## Pomodoro

Choose **Start Pomodoro** in the menu, or run `logolight-signal pomodoro start [minutes]` (25 minutes by
default, from 1 to 180). The logo breathes very slowly for the length of the session, then blinks for about
20 seconds. **Stop Pomodoro** in the menu, or `logolight-signal pomodoro stop`, ends the session or the
blinking. Starting again replaces the session.
