defmodule DrawMusicWeb.Editor.Transport do
  @moduledoc """
  Playback, as a standalone LiveComponent: Play mode's controls
  (`DrawMusicWeb.Palette.PlayControls`), their keys, and the browser side
  of playing (the colocated `.Transport` hook, on the shared audio engine
  of `audio.js`).

  It owns the playback state (idle, loading, playing, paused, rewound),
  Loop and the playback instrument. It stays mounted in Edit mode, with
  nothing shown, so Loop and the playback instrument last until the
  editor is closed, and the drag tones sound on that instrument.

  ## When playback stops
  The component compares each new set of inputs with the last one:
    * a new score or context (an edit, undo, settings, a new key): stop,
      as the browser's events are stale;
    * Edit mode: stop;
    * a new selection while paused or rewound: stop, so Play starts the
      new span instead of resuming the old one;
    * a new version instrument: playback uses it from the next Play.

  ## Inputs
    * `:id`: the component's id (required by LiveView).
    * `:score`, `:ctx`: what to play.
    * `:selection`: the selected ids (a `MapSet`), which set the span.
    * `:engraved`: the laid-out score, for where measures and lines start.
    * `:editor_mode`: `:edit` or `:play`.
    * `:instrument`: the version's instrument (a GM program).
    * `:lines?`: whether the layout has lines of music to skip by.

  ## Intents
    * `{:session, fun}`: a skip before playing moves the start point (it
      selects where it lands); Stop, Rewind or Esc before playing clear the
      selection, so the start point is the beginning of the score.
    * `{:instrument, program}`: "Set selection to version Instrument".
    * `{:flash, kind, message}`: nothing to play; the instrument fell back
      to the synth.
  """

  use DrawMusicWeb, :live_component

  import DrawMusicWeb.Palette.PlayControls

  alias DrawMusic.Engraving.Engraved
  alias DrawMusic.Music.{Playback, Session, TempoMap}
  alias DrawMusicWeb.Editor.Intent
  alias DrawMusicWeb.{InstrumentSource, LibraryComponents, PlaybackPayload}

  # The controls' events; Edit mode (the controls gone, their keys off)
  # ignores a stray one. The hook's reports (`playback_state`,
  # `playback_ended`) count in both modes: the instrument loads in Edit too.
  @play_events ~w(play rewind skip stop toggle_loop set_playback_instrument
                  use_playback_instrument)

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

  # Paused (or paused and rewound to the start point): carry on from there.
  def handle_event("play", _params, %{assigns: %{playback: state}} = socket)
      when state in [:paused, :rewound] do
    {:noreply,
     socket
     |> assign(:playback, :playing)
     |> push_event("resume", %{})}
  end

  def handle_event("play", _params, socket), do: {:noreply, start_playback(socket)}

  def handle_event("playback_ended", _params, socket) do
    {:noreply, assign(socket, :playback, :idle)}
  end

  def handle_event("playback_state", %{"state" => state}, socket) when is_binary(state) do
    {:noreply, playback_state(socket, state)}
  end

  # Before playing, Rewind (like Stop) goes back to the beginning of the score.
  def handle_event("rewind", _params, %{assigns: %{playback: state}} = socket)
      when state in [:idle, :loading] do
    back_to_beginning()
    {:noreply, socket}
  end

  # Paused, Rewind goes back to the start point and waits there: the button
  # offers Play again, not Resume.
  def handle_event("rewind", _params, %{assigns: %{playback: :paused}} = socket) do
    {:noreply,
     socket
     |> assign(:playback, :rewound)
     |> push_event("rewind", %{})}
  end

  def handle_event("rewind", _params, socket), do: {:noreply, push_event(socket, "rewind", %{})}

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
  # dir "back", ⏪ and ⏪⏪ the start of this or the previous one. Playing or
  # paused, the hook knows where it is and jumps (it gets the starts);
  # before playing, the start point moves there.
  def handle_event("skip", %{"by" => by} = params, socket) when by in ~w(measure line) do
    back? = match?(%{"dir" => "back"}, params)
    starts = skip_points(socket.assigns.engraved, by)

    case socket.assigns.playback do
      state when state in [:idle, :loading] ->
        skip_start(socket.assigns, starts, back?)
        {:noreply, socket}

      _sounding ->
        {:noreply, push_event(socket, "skip", %{by: by, back: back?, starts: starts})}
    end
  end

  # Before playing, Stop (and Esc) go back to the beginning of the score;
  # playing or paused, they stop, back to the start point.
  def handle_event("stop", _params, %{assigns: %{playback: state}} = socket)
      when state in [:idle, :loading] do
    back_to_beginning()
    {:noreply, socket}
  end

  def handle_event("stop", _params, socket) do
    {:noreply,
     socket
     |> assign(:playback, :idle)
     |> push_event("stop", %{})}
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
       lines?: true
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
        target={@myself}
      />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Transport">
        // Playback in the browser: the server's play events on the shared
        // audio engine, the play keys (Play mode), and the instrument
        // (data-instrument), loaded in both modes since the score's drag
        // tones use it too. Where playback is goes out as "score:playhead"
        // window events ({tick, jump}; tick null once it stops): the score
        // draws the playhead.
        import {releaseSharedAudio, sharedAudio} from "@/js/score_editor/audio"
        import {dialogOpen, typing} from "@/js/score_editor/keyboard"
        import {tickAt} from "@/js/score_editor/playhead"
        import {skipTarget} from "@/js/score_editor/transport"

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

            this.handleEvent("play", ({events, span, loop, anchors}) => {
              this.anchors = anchors
              this.audio.play(events, span, Boolean(loop))
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
          // Play mode's keys: Space plays or pauses, Home rewinds, L loops,
          // Esc stops (as the ⏹ button).
          key(e) {
            if (typing(e) || dialogOpen() || e.ctrlKey || e.metaKey || e.altKey) return
            if (this.el.dataset.mode !== "play") return
            if (e.key === " ") {
              this.actNow({id: "palette-play"})
              return this.send("play", {}, e)
            }
            if (e.key === "Home") return this.send("rewind", {}, e)
            if (e.key.toLowerCase() === "l") return this.send("toggle_loop", {}, e)
            if (e.key === "Escape") {
              this.actNow({id: "palette-stop"})
              return this.send("stop", {}, e)
            }
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

    {:ok,
     socket
     |> stop_if(stale?(old, socket.assigns))
     |> drop_paused(reselected?(old, socket.assigns))
     |> follow_version_instrument(old)}
  end

  # With nothing selected, Play starts at the beginning of the score, and
  # the idle playhead waits there.
  defp back_to_beginning, do: Intent.notify({:session, &Session.clear_selection/1})

  defp assign_playback_instrument(%{assigns: %{playback_instrument: program}} = socket, program) do
    socket
  end

  defp assign_playback_instrument(socket, program) do
    assign(socket,
      playback_instrument: program,
      instrument_source: InstrumentSource.for_program(program)
    )
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

  # Where Play would start: the selection's start, or the beginning.
  defp play_start(%{score: score, ctx: ctx, selection: selection}) do
    {from, _to} = Playback.span(score, ctx, selection)
    from
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

  # Only a change of selection counts, not the first inputs.
  defp reselected?(%{selection: old}, %{selection: new}), do: old != new
  defp reselected?(_first, _new), do: false

  # Before playing, a skip moves the start point: the first note or rest
  # from where it lands is selected.
  defp skip_start(%{score: score, ctx: ctx} = assigns, starts, back?) do
    with tick when is_integer(tick) <- Playback.skip_target(starts, play_start(assigns), back?),
         id when is_binary(id) <- Playback.first_event_from(score, ctx, tick) do
      Intent.notify({:session, &Session.select(&1, [id], false)})
    end
  end

  defp skip_points(engraved, "measure"), do: Engraved.measure_starts(engraved)
  defp skip_points(engraved, "line"), do: Engraved.line_starts(engraved)

  # The browser's events are stale once the score or its context changes,
  # and Edit mode doesn't play. (The first inputs have nothing to compare.)
  defp stale?(%{score: score, ctx: ctx}, %{score: score, ctx: ctx, editor_mode: mode}) do
    mode == :edit
  end

  defp stale?(%{score: _score}, _new), do: true
  defp stale?(_first, %{editor_mode: mode}), do: mode == :edit

  defp start_playback(socket) do
    %{score: score, ctx: ctx, selection: selection, loop?: loop?} = socket.assigns
    {from, to} = Playback.span(score, ctx, selection)

    case Playback.events(score, ctx, from: from, to: to) do
      [] ->
        Intent.notify({:flash, :error, "Nothing to play here."})
        socket

      events ->
        map = TempoMap.new(score, ctx)

        payload = %PlaybackPayload{
          events: events,
          span: TempoMap.seconds(map, from, to),
          loop: loop?,
          anchors: TempoMap.anchors(map, from, to)
        }

        socket
        |> assign(:playback, :playing)
        |> push_event("play", payload)
    end
  end

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
