defmodule DrawMusicWeb.PaletteComponents do
  @moduledoc """
  The parts of the editor's toolbar (`DrawMusicWeb.Editor.Palette`) that
  are in both modes: the Edit/Play switch and the help button. Each mode's
  own controls are `DrawMusicWeb.Palette.EditTools` and
  `DrawMusicWeb.Palette.PlayControls`; all are built on
  `DrawMusicWeb.Palette.Buttons`.
  """

  use Phoenix.Component

  import DrawMusicWeb.CoreComponents, only: [icon: 1]
  import DrawMusicWeb.Palette.Buttons

  alias DrawMusicWeb.EditorComponents

  @modes [{:edit, "Edit", "hero-pencil"}, {:play, "Play", "hero-speaker-wave"}]

  @doc "Opens the cheat-sheet, in the browser (no server round trip)."
  @spec help_button(map()) :: Phoenix.LiveView.Rendered.t()
  def help_button(assigns) do
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

  @doc """
  The Edit and Play buttons, the toolbar's first two grid columns (Page
  and Strip fall into the same columns below them).
  """
  attr :editor_mode, :atom, required: true, values: [:edit, :play]
  attr :target, :any, default: nil, doc: "the component their clicks go to"

  @spec mode_switch(map()) :: Phoenix.LiveView.Rendered.t()
  def mode_switch(assigns) do
    assigns = assign(assigns, :modes, @modes)

    ~H"""
    <div class="join contents" role="group" aria-label="Mode">
      <.tool_button
        :for={{mode, label, icon} <- @modes}
        id={"palette-mode-#{mode}"}
        title={"#{label} mode (P)"}
        click="toggle_mode"
        target={@target}
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

  defp mode_column(:edit), do: "col-start-1"
  defp mode_column(:play), do: "col-start-2"
end
