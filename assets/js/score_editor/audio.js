// Playback for the ScoreEditor hook: loads the version's instrument
// (smplr, from the server's /samples) and plays the timed events EditorLive
// sends, with pause, resume, rewind and loop handled here on the audio
// clock. Notes light up (`.playing`) while they sound.
//
// Instrument sources come from data-instrument (DrawMusicWeb.InstrumentSource):
// {kind: "splendid" | "soundfont" | "synth", url, name, program}.

import * as Tone from "tone"
import {Soundfont, SplendidGrandPiano} from "smplr"

// Scheduling starts this far ahead of "now" (seconds), so the first note isn't clipped.
const LEAD_IN = 0.05

// smplr builds sample URLs without encoding them, and the piano's sample
// names contain "#" ("PP D#0"), which would otherwise start a URL fragment.
const storage = {fetch: (url) => fetch(url.replace(/#/g, "%23"))}

// The built-in fallback: a Tone.js synth on Tone's own clock.
function synthPlayer() {
  const synth = new Tone.PolySynth(Tone.Synth, {
    oscillator: {type: "triangle"},
    envelope: {attack: 0.01, decay: 0.2, sustain: 0.5, release: 0.4},
  }).toDestination()

  return {
    now: () => Tone.now(),
    unlock: () => Tone.start(),
    start: (midi, time, duration) => synth.triggerAttackRelease(Tone.Frequency(midi, "midi"), duration, time),
    stop: () => synth.releaseAll(),
  }
}

function smplrPlayer(context, instrument) {
  return {
    now: () => context.currentTime,
    unlock: () => context.resume(),
    start: (midi, time, duration) => instrument.start({note: midi, time, duration}),
    stop: () => instrument.stop(),
  }
}

async function loadSmplr(context, source) {
  const instrument =
    source.kind === "splendid"
      ? new SplendidGrandPiano(context, {baseUrl: source.url, storage})
      : new Soundfont(context, {instrumentUrl: source.url, storage})
  await instrument.ready
  return smplrPlayer(context, instrument)
}

export class Audio {
  // onState(state, detail): "loading" | "ready" | "fallback" | "playing" | "paused" | "idle".
  constructor({onState, onEnded}) {
    this.onState = onState
    this.onEnded = onEnded
    this.source = null
    this.player = null
    this.events = []
    this.loop = false
    this.state = "idle"
    this.frame = null
  }

  // Loads `source` unless it is already the current one.
  async load(source) {
    if (this.source && this.source.kind === source.kind && this.source.url === source.url) return
    this.stop()
    this.source = source
    this.player = null

    if (source.kind === "synth") {
      this.player = synthPlayer()
      return this.onState("fallback", source)
    }

    this.onState("loading", source)
    this.context = this.context || new AudioContext()

    try {
      const player = await loadSmplr(this.context, source)
      if (this.source !== source) return
      this.player = player
      this.onState("ready", source)
    } catch (_error) {
      if (this.source !== source) return
      this.player = synthPlayer()
      this.onState("fallback", source)
    }
  }

  // Until the instrument has loaded, plays with the synth.
  ensurePlayer() {
    if (!this.player) this.player = synthPlayer()
    return this.player
  }

  async play(events, loop) {
    this.stop()
    this.events = events
    this.loop = loop
    this.duration = events.reduce((end, ev) => Math.max(end, ev.start + ev.duration), 0)
    await this.ensurePlayer().unlock()
    this.scheduleFrom(0)
  }

  pause() {
    if (this.state !== "playing") return
    this.elapsed = this.player.now() - this.t0
    this.silence()
    this.setState("paused")
  }

  async resume() {
    if (this.state !== "paused") return
    await this.player.unlock()
    this.scheduleFrom(this.elapsed)
  }

  rewind() {
    if (this.state === "playing") {
      this.silence()
      return this.scheduleFrom(0)
    }
    this.elapsed = 0
  }

  setLoop(on) {
    this.loop = on
  }

  stop() {
    this.silence()
    this.events = []
    this.elapsed = 0
    if (this.state !== "idle") this.setState("idle")
  }

  // Sounds a chord at once, with no highlighting or state change.
  async audition(events) {
    const player = this.ensurePlayer()
    await player.unlock()
    const at = player.now() + LEAD_IN
    for (const ev of events) player.start(ev.midi, at + ev.start, ev.duration)
  }

  // Schedules every event still sounding at `from` seconds into the span.
  // One already under way restarts now for what is left of it.
  scheduleFrom(from) {
    const player = this.player
    this.t0 = player.now() + LEAD_IN - from

    for (const ev of this.events) {
      const end = ev.start + ev.duration
      if (end <= from) continue
      const start = Math.max(ev.start, from)
      player.start(ev.midi, this.t0 + start, end - start)
    }

    this.setState("playing")
    this.frame = requestAnimationFrame(() => this.tick())
  }

  // Lights the notes sounding now; at the end of the span, loops or stops.
  tick() {
    const at = this.player.now() - this.t0

    if (at >= this.duration) {
      this.highlightAll(false)
      if (this.loop) return this.scheduleFrom(0)
      this.stop()
      return this.onEnded()
    }

    for (const ev of this.events) {
      const on = at >= ev.start && at < ev.start + ev.duration
      for (const id of ev.ids) document.getElementById(`note-${id}`)?.classList.toggle("playing", on)
    }
    this.frame = requestAnimationFrame(() => this.tick())
  }

  silence() {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
    if (this.player) this.player.stop()
    this.highlightAll(false)
  }

  highlightAll(on) {
    document.querySelectorAll(".playing").forEach((el) => el.classList.toggle("playing", on))
  }

  setState(state) {
    this.state = state
    this.onState(state, this.source)
  }
}
