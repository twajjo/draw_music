defmodule DrawMusicWeb.HelpLive do
  @moduledoc """
  The cheat-sheet page: every key and mouse action in the editor, with
  diagrams of the gestures. Open to everyone, signed in or not.
  """

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.HelpComponents

  alias DrawMusicWeb.Shortcuts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-2xl font-semibold">Keys and mouse</h1>
      <p class="opacity-80">
        Everything you can do in the editor. Press <kbd class="kbd kbd-sm">?</kbd>
        while editing to see this without leaving the score.
      </p>
      <.cheat_sheet shortcuts={@shortcuts} />
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Keys and mouse", shortcuts: Shortcuts.all())}
  end
end
