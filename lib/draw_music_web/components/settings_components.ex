defmodule DrawMusicWeb.SettingsComponents do
  @moduledoc """
  Controls for the score display preferences, shared by the settings page
  and the score view. They send `"set_score_layout"` (`layout`) and
  `"set_score_ink"` (`color`) events; see `DrawMusicWeb.ScorePreferences`.
  """

  use Phoenix.Component

  @ink_presets [
    {"White", "#ffffff"},
    {"Cream", "#fff4d6"},
    {"Amber", "#ffbf47"},
    {"Light green", "#a6e8a6"},
    {"Light blue", "#a8d8ff"},
    {"Light pink", "#ffb8d9"}
  ]

  @doc "The preset dark-mode ink colors as `{name, \"#rrggbb\"}`."
  @spec ink_presets() :: [{String.t(), String.t()}]
  def ink_presets, do: @ink_presets

  @doc "Switches between one long staff and page-style systems."
  attr :id, :string, required: true
  attr :layout, :atom, required: true, values: [:strip, :page]

  @spec layout_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def layout_toggle(assigns) do
    ~H"""
    <div id={@id} class="join" role="group" aria-label="Score layout">
      <button
        :for={
          {layout, label, hint} <- [
            {:strip, "Strip", "One long staff"},
            {:page, "Page", "Rows, like sheet music"}
          ]
        }
        id={"#{@id}-#{layout}"}
        type="button"
        title={hint}
        aria-pressed={to_string(@layout == layout)}
        phx-click="set_score_layout"
        phx-value-layout={layout}
        class={[
          "join-item btn btn-sm transition-colors",
          if(@layout == layout, do: "btn-primary", else: "btn-ghost")
        ]}
      >
        {label}
      </button>
    </div>
    """
  end

  @doc """
  Picks the dark-mode notation color: preset swatches, or any color from
  the custom form (validated by the server).
  """
  attr :id, :string, required: true
  attr :color, :string, default: nil, doc: "the current color; nil means white"
  attr :form, Phoenix.HTML.Form, required: true, doc: "the preferences form, for errors"

  @spec ink_picker(map()) :: Phoenix.LiveView.Rendered.t()
  def ink_picker(assigns) do
    assigns = assign(assigns, presets: @ink_presets, current: assigns.color || "#ffffff")

    ~H"""
    <div id={@id} class="space-y-3">
      <div class="flex flex-wrap gap-2 rounded-box bg-black p-3">
        <button
          :for={{name, color} <- @presets}
          id={"#{@id}-#{String.trim_leading(color, "#")}"}
          type="button"
          title={name}
          aria-label={name}
          aria-pressed={to_string(@current == color)}
          phx-click="set_score_ink"
          phx-value-color={color}
          class={[
            "size-9 rounded-full border-2 transition-transform hover:scale-110 focus-visible:scale-110",
            if(@current == color, do: "border-primary ring-2 ring-primary", else: "border-white/20")
          ]}
          style={"background-color: #{color}"}
        />
      </div>
      <.form for={@form} id={"#{@id}-custom"} phx-submit="set_score_ink" class="flex items-end gap-2">
        <label class="flex flex-col gap-1 text-sm">
          Custom color
          <input
            type="color"
            name="color"
            value={@current}
            class="h-9 w-16 cursor-pointer rounded border border-base-300 bg-transparent"
          />
        </label>
        <button type="submit" class="btn btn-sm">Use color</button>
      </.form>
      <p
        :for={msg <- Enum.map(@form[:score_ink_dark].errors, &translate/1)}
        class="text-sm text-error"
      >
        {msg}
      </p>
    </div>
    """
  end

  defp translate({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
