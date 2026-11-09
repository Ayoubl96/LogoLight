# Signals

A signal is a state that doesn't come from the menu: something outside LogoLight tells the logo what to
show. While it lasts, its pattern takes the place of the effect you chose, and when it ends the effect (or
the brightness) comes back. A Morse message in progress isn't cut off by a signal: the signal shows once
the message is done. Signals need direct control of the logo (the default on a MacBook Pro with PROLED XDR
Display) and play while the logo is on and the display is awake, like effects.

When several signals are active at once, the most important one shows: a call, then Claude Code waiting for
an answer, a reminder, a finished Pomodoro, a nearly empty battery, Claude Code working, a Pomodoro in
progress, a full battery, and last charging.

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

## Battery

With **Battery** switched on, the logo shows your charge as its brightness, and also the power state, so you
can read it from across the room:

- **Charging:** it pulses softly.
- **Full and still plugged in:** it stays lit, so you know you can unplug it.
- **Below 10% and not plugged in:** it blinks slowly.

Plugged in but holding below full (optimised charging) shows nothing extra. A nearly empty battery comes
before Claude Code working and a Pomodoro; a full battery and charging give way to every other signal.

## Calls

**Lit During Calls** (on by default; uncheck it in the menu) keeps the logo lit at full brightness while the
microphone or the camera is in use, so anyone behind the screen can tell you're in a call. It goes out a few
seconds after the call ends. It comes before every other signal, so what colleagues see doesn't change.

It uses the system's own "in use" flag on each microphone and camera: nothing is recorded and no permission is
asked. Anything that uses the microphone counts (dictation, Siri, a voice memo), not only calls.

## Reminders, when you're away

`logolight-signal remind` blinks the logo twice, then rests, but only if you have been away from the Mac
(no keyboard, mouse or trackpad) for 3 minutes. While you are using the Mac nothing happens, because the
screen already reaches you. It stops when you come back, or after 10 minutes. Anything can send it: a
`launchd` job, a shell script, or an alert from a server over SSH.

**Calendar Reminders** (off by default) does this for you five minutes before each event in the Calendar app,
including accounts like Google Calendar that you have added to it. macOS asks for access to your calendar the
first time. LogoLight reads only the start times.
