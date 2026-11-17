defmodule DrawMusicWeb.Palette.KeyMenu do
  @moduledoc """
  The palette's Suggest key button: a drop list of keys that would write the
  score with clearly fewer accidentals (`DrawMusic.Music.KeySuggestion`),
  fewest accidentals first. It is enabled only when one is worth suggesting, as when
  notes entered by ear into C major are really in E♭.

  Choosing a key sends `"rekey"` (`sf`, `mode`) to `target`, which re-keys
  the score without changing how it sounds.
  """

  use Phoenix.Component

  import DrawMusicWeb.CoreComponents, only: [icon: 1]

  alias DrawMusic.Library.Key
  alias DrawMusic.Music.{KeyFit, KeySuggestion}
  alias DrawMusicWeb.Dropdown
  alias Phoenix.LiveView.JS

  @doc "The Suggest key button and its drop list of keys."
  attr :suggestion, KeySuggestion, required: true
  attr :target, :any, required: true
  @spec key_menu(map()) :: Phoenix.LiveView.Rendered.t()
  def key_menu(assigns) do
    ~H"""
    <Dropdown.dropdown id="palette-key-menu">
      <:summary
        id="palette-suggest-key"
        aria-disabled={to_string(not @suggestion.worth_it?)}
        title={title(@suggestion)}
        class={[
          "btn btn-sm btn-outline h-auto gap-1 px-3 text-sm",
          not @suggestion.worth_it? && "pointer-events-none opacity-40"
        ]}
      >
        Suggest key <.icon name="hero-chevron-down-micro" class="size-4 opacity-60" />
      </:summary>
      <div
        :if={@suggestion.worth_it?}
        class="dropdown-content z-30 mt-1 w-72 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
      >
        <p class="mb-1 px-2 text-xs opacity-60">
          Same sounds, new key signature: {count(@suggestion.accidentals)} now. Fewest first
        </p>
        <.key_choice :for={fit <- @suggestion.keys} fit={fit} target={@target} />
      </div>
    </Dropdown.dropdown>
    """
  end

  defp count(1), do: "1 accidental"
  defp count(n), do: "#{n} accidentals"

  attr :fit, KeyFit, required: true
  attr :target, :any, required: true
  # One key to re-key the score in, with the accidentals it would leave.
  defp key_choice(assigns) do
    ~H"""
    <button
      id={"palette-key-#{@fit.sf}-#{@fit.mode}"}
      type="button"
      phx-click={
        Dropdown.close("palette-key-menu")
        |> JS.push("rekey", value: %{sf: @fit.sf, mode: @fit.mode}, target: @target)
      }
      class="flex w-full items-baseline justify-between rounded px-2 py-1 text-sm transition-colors hover:bg-base-200"
    >
      <span>{Key.name(@fit.sf, @fit.mode)}</span>
      <span class="text-xs opacity-60">{leaves(@fit)}</span>
    </button>
    """
  end

  # The accidentals a key would leave, and which notes they are.
  defp leaves(%KeyFit{accidentals: 0}), do: count(0)

  defp leaves(%KeyFit{accidentals: n, accidental_notes: notes}) do
    "#{count(n)}: #{Enum.join(notes, ", ")}"
  end

  defp title(%KeySuggestion{worth_it?: true, accidentals: now}) do
    "These notes carry #{count(now)} in this key; another key writes them with far fewer"
  end

  defp title(%KeySuggestion{accidentals: now}) do
    "The notes suit their key (#{count(now)}); no other key writes them with far fewer"
  end
end
