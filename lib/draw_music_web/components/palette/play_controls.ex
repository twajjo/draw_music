defmodule DrawMusicWeb.Palette.PlayControls do
  @moduledoc """
  The palette's two rows in Play mode: the transport (rewind, skip back
  and forward by a line of music or a measure, stop, play/pause, loop),
  then the playback instrument and a button to save it with the version.
  """

  use Phoenix.Component

  import DrawMusicWeb.CoreComponents, only: [icon: 1, input: 1]
  import DrawMusicWeb.Palette.Buttons

  @doc "Play mode's two rows: the transport, then the instrument."
  attr :playback, :atom, default: :idle, values: [:idle, :loading, :playing, :paused, :rewound]
  attr :loop?, :boolean, default: false
  attr :lines?, :boolean, default: true, doc: "whether the score has lines of music to skip by"
  attr :instrument_name, :string, default: "the instrument", doc: "named while it loads"
  attr :playback_instrument, :integer, default: 0, doc: "GM program playback uses"
  attr :version_instrument, :integer, default: 0, doc: "GM program saved with the version"
  attr :instrument_options, :list, default: [], doc: "grouped select options (LibraryComponents)"
  attr :target, :any, default: nil, doc: "the component the controls' events go to"

  @spec play_controls(map()) :: Phoenix.LiveView.Rendered.t()
  def play_controls(assigns) do
    ~H"""
    <div id="palette-play-controls" class="contents">
      <.transport
        playback={@playback}
        loop?={@loop?}
        lines?={@lines?}
        instrument_name={@instrument_name}
        target={@target}
      />
      <.instrument_picker
        instrument_name={@instrument_name}
        playback_instrument={@playback_instrument}
        version_instrument={@version_instrument}
        instrument_options={@instrument_options}
        target={@target}
      />
    </div>
    """
  end

  # A fast-forward icon of `count` arrowheads, like a tape deck's; `back`
  # points them left, and `bar` puts a bar in front (|<, to the start).
  attr :count, :integer, required: true
  attr :back, :boolean, default: false
  attr :bar, :boolean, default: false

  defp arrows(assigns) do
    assigns = assign(assigns, :width, 6 * assigns.count + 2 + if(assigns.bar, do: 3, else: 0))

    ~H"""
    <svg
      viewBox={"0 0 #{@width} 12"}
      class="h-3.5 w-auto"
      fill="currentColor"
      aria-hidden="true"
    >
      <g transform={@back && "translate(#{@width} 0) scale(-1 1)"}>
        <path :for={i <- 0..(@count - 1)} d={"M#{1 + 6 * i} 1 L#{7 + 6 * i} 6 L#{1 + 6 * i} 11Z"} />
        <rect :if={@bar} x={6 * @count + 2} y="1" width="2" height="10" />
      </g>
    </svg>
    """
  end

  attr :instrument_name, :string, required: true
  attr :playback_instrument, :integer, required: true
  attr :version_instrument, :integer, required: true
  attr :instrument_options, :list, required: true
  attr :target, :any, required: true

  # The picker and its button stay together on one line, the same height.
  defp instrument_picker(assigns) do
    ~H"""
    <div class="col-start-3 row-start-2 ml-3 flex min-w-0 flex-nowrap items-center gap-2">
      <form
        id="playback-instrument-form"
        phx-change="set_playback_instrument"
        phx-target={@target}
        class="w-60 [&_.fieldset]:m-0 [&_.fieldset]:p-0"
      >
        <.input
          id="playback-instrument"
          type="select"
          name="instrument"
          value={@playback_instrument}
          options={@instrument_options}
          aria-label="Playback instrument"
          class="select select-sm w-full"
        />
      </form>
      <.tool_button
        id="use-playback-instrument"
        title="Save this instrument with the version"
        click="use_playback_instrument"
        target={@target}
        data-confirm={"Use #{@instrument_name} for this version? It's saved with the version when you save."}
        disabled={@playback_instrument == @version_instrument}
        off="btn-outline"
        square={false}
        class="h-8 min-h-8 px-3 py-0 text-xs leading-tight whitespace-nowrap"
      >
        <span class="flex flex-col items-start">
          <span>Set selection to</span>
          <span>version Instrument</span>
        </span>
      </.tool_button>
    </div>
    """
  end

  defp play_icon(:playing), do: "hero-pause-solid"
  defp play_icon(_state), do: "hero-play-solid"

  defp play_label(:playing, _instrument), do: "Pause"
  defp play_label(:paused, _instrument), do: "Resume"
  defp play_label(:rewound, _instrument), do: "Play"
  defp play_label(:loading, instrument), do: "Loading #{instrument}…"
  defp play_label(:idle, _instrument), do: "Play"

  defp play_title(:playing), do: "Pause (Space)"
  defp play_title(:paused), do: "Resume (Space)"
  defp play_title(:rewound), do: "Play from the start point (Space)"

  defp play_title(_state) do
    "Play the selection, from the selected note, or from the start (Space)"
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :label, :string, required: true, doc: "what a screen reader says"
  attr :by, :string, required: true, values: ["measure", "line"]
  attr :back, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :target, :any, required: true

  # Skips back or forward by a measure (two arrowheads) or a line of
  # music (three).
  defp skip_button(assigns) do
    ~H"""
    <.tool_button
      id={@id}
      title={@title}
      aria-label={@label}
      click="skip"
      target={@target}
      phx-value-by={@by}
      phx-value-dir={@back && "back"}
      disabled={@disabled}
      class="join-item"
    >
      <.arrows count={if @by == "line", do: 3, else: 2} back={@back} />
    </.tool_button>
    """
  end

  attr :playback, :atom, required: true
  attr :loop?, :boolean, required: true
  attr :lines?, :boolean, required: true
  attr :instrument_name, :string, required: true
  attr :target, :any, required: true

  defp transport(assigns) do
    ~H"""
    <div
      class="join col-start-3 row-start-1 ml-3 self-center justify-self-start"
      role="group"
      aria-label="Playback"
    >
      <.tool_button
        id="palette-rewind"
        title="Back to the start point; before playing, to the beginning (Home)"
        click="rewind"
        target={@target}
        class="join-item"
      >
        <.arrows count={1} back bar />
      </.tool_button>
      <.skip_button
        id="palette-back-line"
        title="Back to the start of this line of music, or the one before"
        label="Back a line of music"
        by="line"
        back
        disabled={!@lines?}
        target={@target}
      />
      <.skip_button
        id="palette-back-measure"
        title="Back to the start of this measure, or the one before"
        label="Back a measure"
        by="measure"
        back
        target={@target}
      />
      <.tool_button
        id="palette-stop"
        title="Stop, back to the start point; before playing, to the beginning (Esc)"
        click="stop"
        target={@target}
        class="join-item"
      >
        <.icon name="hero-stop-solid" class="size-4" />
      </.tool_button>
      <.tool_button
        id="palette-play"
        title={play_title(@playback)}
        click="play"
        target={@target}
        pressed={@playback == :playing}
        on="btn-warning"
        square={false}
        class="join-item gap-1"
      >
        <.icon name={play_icon(@playback)} class="size-4" />
        {play_label(@playback, @instrument_name)}
      </.tool_button>
      <.skip_button
        id="palette-skip-measure"
        title="Skip to the next measure"
        label="Skip to the next measure"
        by="measure"
        target={@target}
      />
      <.skip_button
        id="palette-skip-line"
        title="Skip to the next line of music"
        label="Skip to the next line of music"
        by="line"
        disabled={!@lines?}
        target={@target}
      />
      <.tool_button
        id="palette-loop"
        title="Repeat the selection, or the whole piece (L)"
        click="toggle_loop"
        target={@target}
        pressed={@loop?}
        class="join-item"
      >
        <.icon name="hero-arrow-path" class="size-4" />
      </.tool_button>
    </div>
    """
  end
end
