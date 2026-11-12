defmodule DrawMusicWeb.PaletteComponents do
  @moduledoc """
  The editor's toolbar, two rows tall: the Edit/Play switch over the score
  layout on the left, help and save at the top right, and the current
  mode's controls between them: `DrawMusicWeb.Palette.EditTools` in Edit
  mode, `DrawMusicWeb.Palette.PlayControls` in Play mode. Their buttons
  are built on `DrawMusicWeb.Palette.Buttons`.
  """

  use Phoenix.Component

  import DrawMusicWeb.CoreComponents, only: [icon: 1]
  import DrawMusicWeb.Palette.{Buttons, EditTools, PlayControls}

  alias DrawMusicWeb.EditorComponents

  @modes [{:edit, "Edit", "hero-pencil"}, {:play, "Play", "hero-speaker-wave"}]

  @doc """
  The editor's toolbar: the Edit/Play switch, then the palette for the
  current mode (the edit palette, or the play controls), then help and
  `:trailing` (save) in both.
  """
  attr :armed, :map, default: nil
  attr :row_kind, :atom, default: :note, values: [:note, :rest]
  attr :insert?, :boolean, default: false
  attr :can_undo?, :boolean, default: false
  attr :can_redo?, :boolean, default: false
  attr :mode, :atom, default: :major, doc: "the key's mode, for chord numerals"
  attr :editor_mode, :atom, default: :edit, values: [:edit, :play]
  attr :playback, :atom, default: :idle, values: [:idle, :loading, :playing, :paused, :rewound]
  attr :loop?, :boolean, default: false
  attr :lines?, :boolean, default: true, doc: "whether the score has lines of music to skip by"
  attr :instrument_name, :string, default: "the instrument", doc: "named while it loads"
  attr :playback_instrument, :integer, default: 0, doc: "GM program playback uses"
  attr :version_instrument, :integer, default: 0, doc: "GM program saved with the version"
  attr :instrument_options, :list, default: [], doc: "grouped select options (LibraryComponents)"
  slot :trailing, doc: "extra controls at the right end (e.g. save)"
  slot :below_mode, doc: "controls under the Edit/Play switch (e.g. the score layout)"

  @spec palette(map()) :: Phoenix.LiveView.Rendered.t()
  def palette(assigns) do
    ~H"""
    <.palette_frame>
      <.mode_switch editor_mode={@editor_mode} />
      <div class="contents">
        {render_slot(@below_mode)}
      </div>
      <.edit_tools
        :if={@editor_mode == :edit}
        armed={@armed}
        row_kind={@row_kind}
        insert?={@insert?}
        can_undo?={@can_undo?}
        can_redo?={@can_redo?}
        mode={@mode}
      />
      <.play_controls
        :if={@editor_mode == :play}
        playback={@playback}
        loop?={@loop?}
        lines?={@lines?}
        instrument_name={@instrument_name}
        playback_instrument={@playback_instrument}
        version_instrument={@version_instrument}
        instrument_options={@instrument_options}
      />
      <div class="col-start-4 row-start-1 ml-3 flex items-stretch gap-1">
        <.help_button />
        {render_slot(@trailing)}
      </div>
    </.palette_frame>
    """
  end

  defp help_button(assigns) do
    ~H"""
    <.tool_button
      id="palette-help"
      title="Keys and mouse (?)"
      click={EditorComponents.show_help()}
      class="h-auto"
    >
      <.icon name="hero-question-mark-circle" class="size-4" />
    </.tool_button>
    """
  end

  # Edit and Play fill the grid's first two columns; Page and Strip
  # (the `:below_mode` slot) fall into the same columns below them.
  defp mode_column(:edit), do: "col-start-1"
  defp mode_column(:play), do: "col-start-2"

  attr :editor_mode, :atom, required: true

  defp mode_switch(assigns) do
    assigns = assign(assigns, :modes, @modes)

    ~H"""
    <div class="join contents" role="group" aria-label="Mode">
      <.tool_button
        :for={{mode, label, icon} <- @modes}
        id={"palette-mode-#{mode}"}
        title={"#{label} mode (P)"}
        click="toggle_mode"
        phx-value-mode={mode}
        pressed={@editor_mode == mode}
        square={false}
        class={["join-item row-start-1 h-auto w-full gap-1", mode_column(mode)]}
      >
        <.icon name={icon} class="size-4" />
        {label}
      </.tool_button>
    </div>
    """
  end

  slot :inner_block, required: true

  # A two-row grid: the Edit/Play switch top left, help and save top right,
  # and the current mode's two rows of controls between them. Each row is a
  # palette piece tall (h-10) in both modes, so switching modes doesn't
  # move the score.
  defp palette_frame(assigns) do
    ~H"""
    <div
      id="palette"
      role="toolbar"
      aria-label="Palette"
      class="sticky top-0 z-20 grid grid-cols-[auto_auto_1fr_auto] grid-rows-[2.5rem_2.5rem] items-stretch gap-y-1 border-b border-base-300 bg-base-100/95 px-1 py-2 backdrop-blur"
    >
      {render_slot(@inner_block)}
    </div>
    """
  end
end
