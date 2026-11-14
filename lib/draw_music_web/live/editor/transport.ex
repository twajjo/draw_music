defmodule DrawMusicWeb.Editor.Transport do
  @moduledoc """
  Playback, as a standalone LiveComponent: Play mode's controls
  (`DrawMusicWeb.Palette.PlayControls`), their keys, and the browser side
  of playing (the colocated `.Transport` hook, on the shared audio engine
  of `audio.js`).

  It owns the playback state (idle, loading, playing, paused, rewound),
  Loop, the playback instrument, the bounds Play plays and the play cursor.
  It stays mounted in Edit mode, with nothing shown, so Loop and the
  playback instrument last until the editor is closed, and the drag tones
  sound on that instrument.

  ## Bounds and cursor
  The bounds (`DrawMusic.Music.PlayRange`) are the part of the piece Play,
  Loop, Rewind, Stop, the skips and ⏭ work in: the measures chosen in the
  From/To lists (which select them), else the selection's span, else the
  whole piece. The cursor is where in them Play starts; skips and ⏭ move
  it without touching the selection. A new selection, Stop, Rewind and the
  end of a span take it back to the start of the bounds.

  ## When playback stops
  The component compares each new set of inputs with the last one:
    * a new score or context (an edit, undo, settings, a new key): stop,
      as the browser's events are stale;
    * Edit mode: stop;
    * a new selection while paused or rewound: stop, so Play starts the
      new bounds instead of resuming the old ones;
    * a new version instrument: playback uses it from the next Play.

  ## Inputs
    * `:id`: the component's id (required by LiveView).
    * `:score`, `:ctx`: what to play.
    * `:selection`: the selected ids (a `MapSet`), which set the bounds.
    * `:engraved`: the laid-out score, for where measures and lines start.
    * `:editor_mode`: `:edit` or `:play`.
    * `:instrument`: the version's instrument (a GM program).
    * `:lines?`: whether the layout has lines of music to skip by.

  ## Intents
    * `{:session, fun}`: choosing measures selects them; Whole piece
      clears the selection.
    * `{:instrument, program}`: "Set as version Instrument".
    * `{:flash, kind, message}`: nothing to play; the instrument fell back
      to the synth.
  """

  use DrawMusicWeb, :live_component

  import DrawMusicWeb.Palette.PlayControls

  alias DrawMusic.Engraving.Engraved
  alias DrawMusic.Music.{Playback, PlayRange, Session, TempoMap}
  alias DrawMusicWeb.Editor.Intent
  alias DrawMusicWeb.{InstrumentSource, LibraryComponents, PlaybackPayload}

  # The controls' events; Edit mode (the controls gone, their keys off)
  # ignores a stray one. The hook's reports (`playback_state`,
  # `playback_ended`) count in both modes: the instrument loads in Edit too.
  @play_events ~w(play rewind skip stop to_end toggle_loop set_measures whole_piece
                  set_playback_instrument use_playback_instrument)

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event(event, _params, %{assigns: %{editor_mode: :edit}} = socket)
      when event in @play_events do
    {:noreply, socket}
  end

  # The browser plays the events (smplr, see audio.js) and highlights each
  # note as it sounds; pause, resume, rewind and loop happen there too.
  def handle_event("play", _params, %{assigns: %{playback: :playing}} = socket) do
    {:noreply,
     socket
     |> assign(:playback, :paused)
     |> push_event("pause", %{})}
  end

  # Paused (or paused and rewound to the start): carry on from there.
  def handle_event("play", _params, %{assigns: %{playback: state}} = socket)
      when state in [:paused, :rewound] do
    {:noreply,
     socket
     |> assign(:playback, :playing)
     |> push_event("resume", %{})}
  end

  def handle_event("play", _params, socket), do: {:noreply, start_playback(socket)}

  # A span played to its end (not looped): the cursor goes back to the start.
  def handle_event("playback_ended", _params, socket) do
    {:noreply, assign(socket, playback: :idle, cursor: nil)}
  end

  def handle_event("playback_state", %{"state" => state}, socket) when is_binary(state) do
    {:noreply, playback_state(socket, state)}
  end

  # Paused, Rewind goes back to the start and waits there: the button
  # offers Play again, not Resume. Playing, it starts again from there.
  def handle_event("rewind", _params, %{assigns: %{playback: :paused}} = socket) do
    {:noreply,
     socket
     |> assign(:playback, :rewound)
     |> push_event("rewind", %{})}
  end

  def handle_event("rewind", _params, %{assigns: %{playback: :playing}} = socket) do
    {:noreply, push_event(socket, "rewind", %{})}
  end

  def handle_event("rewind", _params, socket), do: {:noreply, assign(socket, :cursor, nil)}

  # From/To: measures `first` to `last` become the bounds, selected. Not
  # while playing; paused, the new selection drops the paused span.
  def handle_event("set_measures", _params, %{assigns: %{playback: :playing}} = socket) do
    {:noreply, socket}
  end

  def handle_event("set_measures", %{"first" => first, "last" => last}, socket) do
    case {parse_measure(first), parse_measure(last)} do
      {{:ok, first}, {:ok, last}} -> {:noreply, choose_measures(socket, first, last)}
      _invalid -> {:noreply, socket}
    end
  end

  # The playback instrument is for listening only; it starts as the
  # version's and lasts until the editor is closed.
  def handle_event("set_playback_instrument", %{"instrument" => value}, socket) do
    case Integer.parse(to_string(value)) do
      {program, ""} when program in 0..127 ->
        {:noreply,
         socket
         |> stop_playback()
         |> assign_playback_instrument(program)}

      _invalid ->
        {:noreply, socket}
    end
  end

  # ⏩ the start of the next measure, ⏩⏩ of the next line of music; with
  # dir "back", ⏪ and ⏪⏪ the start of this or the previous one, all inside
  # the bounds. Playing or paused, the hook knows where it is and jumps (it
  # gets the starts); before playing, the cursor moves there.
  def handle_event("skip", %{"by" => by} = params, socket) when by in ~w(measure line) do
    back? = match?(%{"dir" => "back"}, params)
    starts = skip_points(socket.assigns.engraved, by)

    case socket.assigns.playback do
      state when state in [:idle, :loading] ->
        {:noreply, skip_cursor(socket, starts, back?)}

      _sounding ->
        {:noreply, push_event(socket, "skip", %{by: by, back: back?, starts: starts})}
    end
  end

  # Stop (and Esc): back to the start of the bounds.
  def handle_event("stop", _params, socket) do
    {:noreply,
     socket
     |> stop_playback()
     |> assign(:cursor, nil)}
  end

  # ⏭: playing with Loop on, the same as Rewind; otherwise playback stops
  # and the cursor waits at the end of the bounds.
  def handle_event("to_end", _params, %{assigns: %{playback: :playing, loop?: true}} = socket) do
    {:noreply, push_event(socket, "rewind", %{})}
  end

  def handle_event("to_end", _params, %{assigns: %{range: %PlayRange{to: to}}} = socket) do
    {:noreply,
     socket
     |> stop_playback()
     |> assign(:cursor, to)}
  end

  def handle_event("toggle_loop", _params, socket) do
    loop? = !socket.assigns.loop?

    {:noreply,
     socket
     |> assign(:loop?, loop?)
     |> push_event("loop", %{on: loop?})}
  end

  def handle_event("use_playback_instrument", _params, socket) do
    Intent.notify({:instrument, socket.assigns.playback_instrument})
    {:noreply, socket}
  end

  # Whole piece: the selection cleared, the bounds are measures 1 to N.
  def handle_event("whole_piece", _params, %{assigns: %{playback: :playing}} = socket) do
    {:noreply, socket}
  end

  def handle_event("whole_piece", _params, socket) do
    Intent.notify({:session, &Session.clear_selection/1})
    {:noreply, assign(socket, measures: nil, cursor: nil)}
  end

  # Anything else from the browser (malformed params) is ignored.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  @spec mount(Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(socket) do
    {:ok,
     assign(socket,
       playback: :idle,
       loop?: false,
       playback_instrument: nil,
       instrument_source: nil,
       instrument_options: LibraryComponents.instrument_options(),
       lines?: true,
       measures: nil,
       cursor: nil,
       range: nil
     )}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  # `contents`: the controls are cells of the palette's grid. In Edit mode
  # the root stays, empty, for the hook (the instrument, the drag tones).
  def render(assigns) do
    ~H"""
    <div
      id="transport"
      class="contents"
      phx-hook=".Transport"
      phx-target={@myself}
      data-mode={@editor_mode}
      data-instrument={Jason.encode!(@instrument_source)}
      data-play-start={@range && PlayRange.start(@range, @cursor)}
    >
      <.play_controls
        :if={@editor_mode == :play}
        playback={@playback}
        loop?={@loop?}
        lines?={@lines?}
        instrument_name={@instrument_source.name}
        playback_instrument={@playback_instrument}
        version_instrument={@instrument}
        instrument_options={@instrument_options}
        range={@range}
        target={@myself}
      />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Transport">
        // Playback in the browser: the server's play events on the shared
        // audio engine, the play keys (Play mode), and the instrument
        // (data-instrument), loaded in both modes since the score's drag
        // tones use it too. Window events tell the score where to draw the
        // playhead: "score:playhead" ({tick, jump}; tick null once it stops)
        // while playing, "score:play-start" ({tick}: data-play-start, null in
        // Edit mode) where it waits before playing. The editor opens in Edit
        // mode, so the score is listening by the first one that matters.
        import {releaseSharedAudio, sharedAudio} from "@/js/score_editor/audio"
        import {dialogOpen, typing} from "@/js/score_editor/keyboard"
        import {tickAt} from "@/js/score_editor/playhead"
        import {skipTarget} from "@/js/score_editor/transport"

        const KEYS = {"Home": "rewind", "End": "to_end", "l": "toggle_loop", "L": "toggle_loop"}

        export default {
          mounted() {
            this.audio = sharedAudio()
            this.audio.listen({
              onState: (state) => {
                this.send("playback_state", {state})
              },
              onEnded: () => {
                this.send("playback_ended")
              },
              onTick: (seconds) => {
                this.announce(seconds)
              }
            })
            this.loadInstrument()
            this.announceStart()

            this.handleEvent("play", ({events, span, loop, anchors, at}) => {
              this.anchors = anchors
              this.audio.play(events, span, Boolean(loop), at || 0)
            })
            this.handleEvent("pause", () => this.audio.pause())
            this.handleEvent("resume", () => this.audio.resume())
            this.handleEvent("rewind", () => this.audio.rewind())
            this.handleEvent("skip", ({starts, back}) => this.skip(starts, back))
            this.handleEvent("loop", ({on}) => this.audio.setLoop(on))
            this.handleEvent("stop", () => this.audio.stop())
            this.handleEvent("audition", ({events}) => this.audio.audition(events))

            this.onKey = (e) => {
              this.key(e)
            }
            // Pause and Stop act at once, before their click reaches the server.
            this.onClick = (e) => {
              this.actNow(e.target.closest && e.target.closest("button"))
            }
            // Browsers allow audio only after a gesture: the first press, of a
            // pointer or a key, starts the audio clocks.
            this.onFirstGesture = () => {
              window.removeEventListener("pointerdown", this.onFirstGesture)
              window.removeEventListener("keydown", this.onFirstGesture)
              this.audio.unlock()
            }
            window.addEventListener("keydown", this.onKey)
            this.el.addEventListener("click", this.onClick, true)
            window.addEventListener("pointerdown", this.onFirstGesture)
            window.addEventListener("keydown", this.onFirstGesture)
          },
          updated() {
            this.loadInstrument()
            this.announceStart()
          },
          destroyed() {
            window.removeEventListener("keydown", this.onKey)
            window.removeEventListener("pointerdown", this.onFirstGesture)
            window.removeEventListener("keydown", this.onFirstGesture)
            releaseSharedAudio()
          },
          loadInstrument() {
            this.audio.load(JSON.parse(this.el.dataset.instrument))
          },
          // Pausing and stopping happen here at once, not after the round
          // trip; the server, told by the same key or click, then updates the
          // controls (and its own "pause" or "stop" finds nothing to do).
          actNow(button) {
            if (button?.id === "palette-play" && this.audio.state === "playing") this.audio.pause(true)
            if (button?.id === "palette-stop" && this.audio.state !== "idle") this.audio.stop(true)
          },
          // Play mode's keys: Space plays or pauses, Home rewinds, End goes
          // to the end, L loops, Esc stops (as the ⏹ button).
          key(e) {
            if (typing(e) || dialogOpen() || e.ctrlKey || e.metaKey || e.altKey) return
            if (this.el.dataset.mode !== "play") return
            if (e.key === " ") {
              this.actNow({id: "palette-play"})
              return this.send("play", {}, e)
            }
            if (e.key === "Escape") {
              this.actNow({id: "palette-stop"})
              return this.send("stop", {}, e)
            }
            if (KEYS[e.key]) return this.send(KEYS[e.key], {}, e)
          },
          // Playing or paused: on to where the server's skip lands (`starts`:
          // the measures' or lines' starts, in ticks).
          skip(starts, back) {
            const state = this.audio.state
            if ((state !== "playing" && state !== "paused") || !this.anchors?.length) return
            const seconds = skipTarget(starts, this.anchors, this.audio.position(), back)
            if (seconds === null) return
            this.jumped = true
            this.audio.seek(seconds)
          },
          // Where playback is, for the score's playhead; a skip jumps to it.
          announce(seconds) {
            if (seconds !== null && !this.anchors?.length) return
            const tick = seconds === null ? null : tickAt(this.anchors, seconds)
            window.dispatchEvent(new CustomEvent("score:playhead", {detail: {tick, jump: Boolean(this.jumped)}}))
            this.jumped = false
          },
          // Where Play would start, for the playhead waiting there.
          announceStart() {
            const start = this.el.dataset.playStart
            const tick = start === undefined ? null : Number(start)
            window.dispatchEvent(new CustomEvent("score:play-start", {detail: {tick}}))
          },
          send(event, payload = {}, e = null) {
            if (e) e.preventDefault()
            this.pushEventTo(this.el, event, payload)
          }
        }
      </script>
    </div>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(assigns, socket) do
    old = socket.assigns
    socket = assign(socket, assigns)
    stale? = stale?(old, socket.assigns)
    reselected? = reselected?(old, socket.assigns)

    {:ok,
     socket
     |> stop_if(stale?)
     |> drop_paused(reselected?)
     |> reset_cursor(stale? or reselected?)
     |> follow_version_instrument(old)
     |> assign_range()}
  end

  defp assign_playback_instrument(%{assigns: %{playback_instrument: program}} = socket, program) do
    socket
  end

  defp assign_playback_instrument(socket, program) do
    assign(socket,
      playback_instrument: program,
      instrument_source: InstrumentSource.for_program(program)
    )
  end

  # The bounds, worked out in Play mode only (the controls and the playhead
  # are Play mode's): a long score takes a moment to walk through.
  defp assign_range(%{assigns: %{editor_mode: :play} = assigns} = socket) do
    assign(socket, :range, range(assigns))
  end

  defp assign_range(socket), do: assign(socket, :range, nil)

  defp choose_measures(socket, first, last) do
    %{score: score, ctx: ctx} = socket.assigns
    range = PlayRange.measures(score, ctx, first, last)
    ids = PlayRange.ids(range, score, ctx)
    Intent.notify({:session, &Session.select(&1, ids, false)})

    socket
    |> assign(measures: %{first: range.first, last: range.last, ids: MapSet.new(ids)})
    |> assign(:cursor, nil)
  end

  # A new selection is what the next Play plays: a paused span is dropped,
  # so Play starts the new one instead of resuming the old.
  defp drop_paused(%{assigns: %{playback: state}} = socket, true = _reselected?)
       when state in [:paused, :rewound] do
    stop_playback(socket)
  end

  defp drop_paused(socket, _reselected?), do: socket

  # A new version instrument (from the settings, or this component's "Set"
  # button) is also what playback uses next; so is the first one.
  defp follow_version_instrument(%{assigns: %{instrument: program}} = socket, %{
         instrument: program
       }) do
    socket
  end

  defp follow_version_instrument(socket, _old) do
    assign_playback_instrument(socket, socket.assigns.instrument)
  end

  defp loaded(%{assigns: %{playback: :loading}} = socket), do: assign(socket, :playback, :idle)
  defp loaded(socket), do: socket

  defp nothing_to_play(socket) do
    Intent.notify({:flash, :error, "Nothing to play here."})
    socket
  end

  defp parse_measure(value) do
    case Integer.parse(to_string(value)) do
      {number, ""} when number > 0 -> {:ok, number}
      _invalid -> :error
    end
  end

  # The whole of the bounds goes to the browser, `at` seconds in to start.
  defp play_from(socket, %PlayRange{from: from, to: to}, start) do
    %{score: score, ctx: ctx, loop?: loop?} = socket.assigns

    case Playback.events(score, ctx, from: from, to: to) do
      [] ->
        nothing_to_play(socket)

      events ->
        map = TempoMap.new(score, ctx)

        payload = %PlaybackPayload{
          events: events,
          span: TempoMap.seconds(map, from, to),
          loop: loop?,
          anchors: TempoMap.anchors(map, from, to),
          at: TempoMap.seconds(map, from, start)
        }

        socket
        |> assign(:playback, :playing)
        |> push_event("play", payload)
    end
  end

  # What the hook reports; names are only matched, never made atoms.
  defp playback_state(socket, "loading"), do: assign(socket, :playback, :loading)
  defp playback_state(socket, "playing"), do: assign(socket, :playback, :playing)
  defp playback_state(%{assigns: %{playback: :rewound}} = socket, "paused"), do: socket
  defp playback_state(socket, "paused"), do: assign(socket, :playback, :paused)
  defp playback_state(socket, "idle"), do: assign(socket, :playback, :idle)
  defp playback_state(socket, "ready"), do: loaded(socket)

  defp playback_state(socket, "fallback") do
    name = socket.assigns.instrument_source.name
    Intent.notify({:flash, :info, "#{name} isn't available; playing with the built-in synth."})
    loaded(socket)
  end

  defp playback_state(socket, _unknown), do: socket

  # The chosen measures while they are still what is selected; otherwise
  # the selection's span (the whole piece with nothing selected).
  defp range(%{measures: %{ids: ids} = measures, selection: ids, score: score, ctx: ctx}) do
    PlayRange.measures(score, ctx, measures.first, measures.last)
  end

  defp range(%{score: score, ctx: ctx, selection: selection}) do
    PlayRange.of_selection(score, ctx, selection)
  end

  # Only a change of selection counts, not the first inputs.
  defp reselected?(%{selection: old}, %{selection: new}), do: old != new
  defp reselected?(_first, _new), do: false

  defp reset_cursor(socket, true = _bounds_changed?), do: assign(socket, :cursor, nil)
  defp reset_cursor(socket, false), do: socket

  # Before playing, a skip moves the cursor, inside the bounds.
  defp skip_cursor(
         %{assigns: %{range: %PlayRange{} = range, cursor: cursor}} = socket,
         starts,
         back?
       ) do
    case PlayRange.skip(range, starts, PlayRange.start(range, cursor), back?) do
      nil -> socket
      tick -> assign(socket, :cursor, tick)
    end
  end

  defp skip_cursor(socket, _starts, _back?), do: socket

  defp skip_points(engraved, "measure"), do: Engraved.measure_starts(engraved)
  defp skip_points(engraved, "line"), do: Engraved.line_starts(engraved)

  # The browser's events are stale once the score or its context changes,
  # and Edit mode doesn't play. (The first inputs have nothing to compare.)
  defp stale?(%{score: score, ctx: ctx}, %{score: score, ctx: ctx, editor_mode: mode}) do
    mode == :edit
  end

  defp stale?(%{score: _score}, _new), do: true
  defp stale?(_first, %{editor_mode: mode}), do: mode == :edit

  # Plays the bounds from the cursor; Loop goes round the whole of them. At
  # their end there is nothing left to play, unless Loop starts them again.
  defp start_playback(%{assigns: %{range: %PlayRange{} = range}} = socket) do
    %{cursor: cursor, loop?: loop?} = socket.assigns

    case {PlayRange.start(range, cursor), loop?} do
      {start, false} when start >= range.to -> nothing_to_play(socket)
      {start, true} when start >= range.to -> play_from(socket, range, range.from)
      {start, _loop?} -> play_from(socket, range, start)
    end
  end

  defp start_playback(socket), do: socket

  defp stop_if(socket, true = _stale?), do: stop_playback(socket)
  defp stop_if(socket, false), do: socket

  # Nothing sounding (or only loading): nothing to stop.
  defp stop_playback(%{assigns: %{playback: state}} = socket) when state in [:idle, :loading] do
    socket
  end

  defp stop_playback(socket) do
    socket
    |> assign(:playback, :idle)
    |> push_event("stop", %{})
  end
end
