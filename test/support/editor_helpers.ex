defmodule DrawMusicWeb.EditorHelpers do
  @moduledoc """
  Helpers for editor LiveView tests: reading the editing session (to check
  where notes landed in time, which the DOM doesn't show) and counting
  elements.
  """

  import Phoenix.LiveViewTest

  alias DrawMusic.MusicHelpers

  @doc "The editor's `DrawMusic.Music.Session`."
  def session_of(view), do: :sys.get_state(view.pid).socket.assigns.session

  @doc "All notes as `MusicHelpers.notes/1` tuples."
  def notes_of(view), do: MusicHelpers.notes(session_of(view).score)

  @doc "How many elements in the rendered view match `selector`."
  def count(view, selector) do
    view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
  end

  @doc "Places with the `place` hook event; `spn` like \"C4\"."
  def place(view, measure, offset, spn, opts \\ []) do
    {step, alter} = MusicHelpers.pitch!(spn)

    params =
      %{
        "measure" => measure,
        "offset" => offset,
        "staff" => Keyword.get(opts, :staff, "treble"),
        "step" => step
      }
      |> then(&if(Keyword.get(opts, :alter, false), do: Map.put(&1, "alter", alter), else: &1))

    render_hook(view, "place", params)
  end
end
