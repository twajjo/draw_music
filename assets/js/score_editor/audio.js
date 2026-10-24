// Playback for the ScoreEditor hook: loads the playback instrument (smplr,
// from the server's /samples) and plays the timed events EditorLive sends.
// Pause, resume, rewind and loop happen here, on the audio clock. Notes
// light up (`.playing`) while they sound.
//
// Notes are handed to the player only a short way ahead (LOOKAHEAD), from
// the animation-frame tick, so pausing or stopping only has to silence the
// few notes already handed over; nothing is left queued to sound later.
//
// Instrument sources come from data-instrument (DrawMusicWeb.InstrumentSource):
// {kind: "splendid" | "soundfont" | "synth", url, name, program}.

import * as Tone from "tone"
import {Soundfont, SplendidGrandPiano} from "smplr"

// Scheduling starts this far ahead of "now" (seconds), so the first note isn't clipped.
const LEAD_IN = 0.05
// How far ahead of the clock notes are handed to the player (seconds).
const LOOKAHEAD = 0.25

// A sawtooth has the overtones small speakers need to make bass notes heard
// (a triangle's low notes are mostly fundamental, which they can't play).
const SYNTH_OPTIONS = {
  oscillator: {type: "sawtooth"},
  envelope: {attack: 0.01, decay: 0.2, sustain: 0.5, release: 0.4},
}
// The sawtooth is much louder than the triangle was (decibels).
const SYNTH_VOLUME = -12

function newSynth() {
  const synth = new Tone.PolySynth(Tone.Synth, SYNTH_OPTIONS).toDestination()
  synth.volume.value = SYNTH_VOLUME
  return synth
}

// The built-in fallback: a Tone.js synth. Stopping disposes it (that also
// cancels attacks it has scheduled) and starts a fresh one.
function synthPlayer() {
  let synth = newSynth()

  return {
    now: () => Tone.getContext().currentTime,
    unlock: () => Tone.start(),
    start: (midi, time, duration) => synth.triggerAttackRelease(Tone.Frequency(midi, "midi").toFrequency(), duration, time),
    stop: () => {
      synth.dispose()
      synth = newSynth()
    },
    dispose: () => synth.dispose(),
  }
}

// A smplr instrument. Each started note's stop function cancels it whether
// it is sounding or still waiting in smplr's own scheduler.
function smplrPlayer(context, instrument) {
  let stops = []

  return {
    now: () => context.currentTime,
    unlock: () => context.resume(),
    start: (midi, time, duration) => stops.push(instrument.start({note: midi, time, duration})),
    stop: () => {
      stops.forEach((stopNote) => stopNote())
      stops = []
    },
    dispose: () => instrument.dispose(),
  }
}

async function loadSmplr(context, source) {
  const instrument =
    source.kind === "splendid"
      ? new SplendidGrandPiano(context, {baseUrl: source.url})
      : new Soundfont(context, {instrumentUrl: source.url})
  await instrument.ready
  return smplrPlayer(context, instrument)
}

const sameSource = (a, b) => a && b && a.kind === b.kind && a.url === b.url && a.program === b.program

export class Audio {
  // onState(state, source): "loading" | "ready" | "fallback" | "playing" | "paused" | "idle".
  constructor({onState, onEnded}) {
    this.onState = onState
    this.onEnded = onEnded
    this.context = null
    this.source = null
    this.loaded = null // the player for `source`, once ready
    this.active = null // the player sounding the current span
    this.events = []
    this.loop = false
    this.state = "idle"
    this.frame = null
    this.generation = 0
  }

  // Browsers only allow audio after a user gesture: the hook calls this on
  // the first pointer press, so both clocks are running before Play.
  async unlock() {
    this.context = this.context || new AudioContext()
    await Promise.all([Tone.start(), this.context.resume()])
  }

  // Loads `source` unless it is already the current one. A span already
  // playing keeps its player; the new one is used from the next Play.
  async load(source) {
    if (sameSource(this.source, source)) return
    this.source = source
    this.loaded = null

    if (source.kind === "synth") {
      this.loaded = synthPlayer()
      return this.onState("fallback", source)
    }

    this.onState("loading", source)
    this.context = this.context || new AudioContext()

    try {
      const player = await loadSmplr(this.context, source)
      if (this.source !== source) return
      this.loaded = player
      this.onState("ready", source)
    } catch (_error) {
      if (this.source !== source) return
      this.loaded = synthPlayer()
      this.onState("fallback", source)
    }
  }

  // The player for a new span: the loaded instrument, or the synth meanwhile.
  nextPlayer() {
    if (!this.loaded) this.loaded = synthPlayer()
    return this.loaded
  }

  // `span` is the span's length in seconds (rests included), so a loop
  // comes round in time.
  async play(events, span, loop) {
    this.stop()
    const generation = ++this.generation
    this.events = [...events].sort((a, b) => a.start - b.start)
    this.span = span
    this.loop = loop
    const player = this.nextPlayer()
    await player.unlock()
    if (generation !== this.generation) return
    this.startSpan(player, 0)
  }

  pause() {
    if (this.state !== "playing") return
    this.elapsed = this.active.now() - this.t0
    this.silence()
    this.setState("paused")
  }

  async resume() {
    if (this.state !== "paused") return
    const generation = ++this.generation
    const player = this.nextPlayer()
    await player.unlock()
    if (generation !== this.generation) return
    this.startSpan(player, this.elapsed)
  }

  rewind() {
    if (this.state === "playing") {
      this.silence()
      return this.startSpan(this.nextPlayer(), 0)
    }
    this.elapsed = 0
  }

  setLoop(on) {
    this.loop = on
  }

  stop() {
    this.generation++
    this.silence()
    this.events = []
    this.elapsed = 0
    if (this.state !== "idle") this.setState("idle")
  }

  // Sounds a chord at once, with no highlighting or state change.
  async audition(events) {
    const player = this.nextPlayer()
    await player.unlock()
    const at = player.now() + LEAD_IN
    for (const ev of events) player.start(ev.midi, at + ev.start, ev.duration)
  }

  // A short tone (or chord) while placing or dragging, on the loaded
  // instrument; it doesn't touch playback.
  async preview(midis, duration) {
    const player = this.nextPlayer()
    await player.unlock()
    const at = player.now()
    for (const midi of midis) player.start(midi, at, duration)
  }

  // Starts (or restarts) the span `from` seconds in on `player`. A note
  // already under way at `from` sounds for what is left of it.
  startSpan(player, from) {
    this.active = player
    this.t0 = player.now() + LEAD_IN - from
    this.next = this.events.findIndex((ev) => ev.start + ev.duration > from)
    if (this.next === -1) this.next = this.events.length
    this.from = from
    this.setState("playing")
    this.tick()
  }

  // Each frame: hand over the notes due within LOOKAHEAD, light the ones
  // sounding, and at the end of the span loop or stop.
  tick() {
    const at = this.active.now() - this.t0

    if (at >= this.span && this.loop) {
      // The next time round starts exactly a span later, with no gap.
      this.t0 += this.span
      this.next = 0
      this.from = 0
      return this.tick()
    }

    if (at >= this.span) {
      this.stop()
      return this.onEnded()
    }

    while (this.next < this.events.length && this.events[this.next].start < at + LOOKAHEAD) {
      const ev = this.events[this.next++]
      const start = Math.max(ev.start, this.from)
      this.active.start(ev.midi, this.t0 + start, ev.start + ev.duration - start)
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
    if (this.active) this.active.stop()
    document.querySelectorAll(".playing").forEach((el) => el.classList.remove("playing"))
  }

  // Leaving the editor: stop, and free the audio objects.
  destroy() {
    this.silence()
    for (const player of new Set([this.active, this.loaded])) if (player) player.dispose()
    if (this.context) this.context.close()
  }

  setState(state) {
    this.state = state
    this.onState(state, this.source)
  }
}
