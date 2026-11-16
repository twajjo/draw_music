defmodule DrawMusicWeb.PreferencesComponents do
  @moduledoc """
  The user's preferences (appearance, the score display and the reading
  aids, all in `DrawMusicWeb.PreferencesForm`), drawn on the Preferences page and
  in the editor's Preferences panel alike.

  The form previews its changes and stores them only on Save; it tells the
  LiveView with `{PreferencesForm, message}`. The panel is opened by a URL
  patch, so the editor behind it stays as it was, unsaved changes included,
  and it can only be left by the form's Save or Cancel.
  """

  use DrawMusicWeb, :html

  alias DrawMusicWeb.PreferencesForm

  @doc "All the preference sections, one under the other, as one form."
  attr :scope, :map, required: true
  @spec preference_sections(map()) :: Phoenix.LiveView.Rendered.t()
  def preference_sections(assigns) do
    ~H"""
    <.live_component module={PreferencesForm} id="preferences-form" scope={@scope} />
    """
  end

  @doc """
  The preferences over the editor. It has no close button and ignores Esc
  and clicks outside: the form's Save or Cancel closes it.
  """
  attr :scope, :map, required: true
  @spec preferences_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def preferences_panel(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div
        id="preferences-panel"
        role="dialog"
        aria-label="Preferences"
        class="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
      >
        <h2 class="text-lg font-semibold">Preferences</h2>
        <div class="mt-4">
          <.preference_sections scope={@scope} />
        </div>
      </div>
    </div>
    """
  end
end
