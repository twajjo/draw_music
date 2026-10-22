defmodule DrawMusicWeb.EditorCommands do
  @moduledoc """
  The edits behind the editor's gestures, menus and keys, each built as a
  function of `(score, ctx)` for `DrawMusic.Music.Session.edit/2`. Event
  params come from the browser: names are only looked up, never turned into
  atoms.
  """

  alias DrawMusic.Music.{Clipboard, Context, Duration, Editing, Note, Pitch, Score, Timeline}
  alias DrawMusicWeb.{ContextMenu, EditorPalette}

  @typedoc "An edit for `DrawMusic.Music.Session.edit/2`."
  @type edit ::
          (Score.t(), Context.t() ->
             {:ok, Score.t()} | {:ok, Score.t(), term()} | {:error, Editing.reason()})

  # {scale steps, semitones} of the intervals offered in the menu.
  @intervals %{
    "m2" => {1, 1},
    "M2" => {1, 2},
    "m3" => {2, 3},
    "M3" => {2, 4},
    "P4" => {3, 5},
    "A4" => {3, 6},
    "P5" => {4, 7},
    "m6" => {5, 8},
    "M6" => {5, 9},
    "m7" => {6, 10},
    "M7" => {6, 11},
    "P8" => {7, 12}
  }

  @doc "Drops picked-up notes `steps` scale steps away, with `alter` if a modifier was held."
  @spec drop([Ecto.UUID.t()], integer(), -2..2 | nil) :: edit()
  def drop(ids, steps, alter) do
    fn score, ctx ->
      with {:ok, score} <- Editing.move_steps(score, ctx, ids, steps),
           do: maybe_alter(score, ctx, ids, alter)
    end
  end

  defp maybe_alter(score, _ctx, _ids, nil), do: {:ok, score}
  defp maybe_alter(score, ctx, ids, alter), do: Editing.set_alter(score, ctx, ids, alter)

  @doc """
  Moves notes up or down (`dir`) by a scale `"step"`, `"semitone"`,
  `"octave"` or a named `"interval"` (m2 … P8).
  """
  @spec transpose([Ecto.UUID.t()], String.t(), String.t()) :: edit()
  @spec transpose([Ecto.UUID.t()], String.t(), String.t(), String.t() | nil) :: edit()
  def transpose(ids, by, dir, interval \\ nil) do
    sign = if dir == "down", do: -1, else: 1

    case {by, Map.get(@intervals, interval)} do
      {"step", _} ->
        &Editing.move_steps(&1, &2, ids, sign)

      # An exact octave keeps each note's accidental.
      {"octave", _} ->
        &Editing.transpose_interval(&1, &2, ids, 7 * sign, 12 * sign)

      {"semitone", _} ->
        &Editing.transpose_chromatic(&1, &2, ids, sign)

      {"interval", {steps, semis}} ->
        &Editing.transpose_interval(&1, &2, ids, steps * sign, semis * sign)

      _ ->
        refused(:not_found)
    end
  end

  @doc """
  The edit a context-menu item makes. `menu` holds the right-clicked `id`,
  the `ids` it acts on and the clicked `step`; `insert?` is Insert mode.
  """
  # Split, length, dot and make-rest act on the right-clicked note's whole
  # chord, which must stay one chord.
  @spec menu(String.t(), map(), ContextMenu.t(), boolean()) :: edit()
  def menu("split", _params, menu, _insert?),
    do: &Editing.split(&1, &2, Editing.chord_ids(&1, &2, menu.id))

  def menu("set_value", %{"value" => name}, menu, insert?) do
    case EditorPalette.value(name) do
      nil -> refused(:unrepresentable)
      value -> lengthen(menu.id, value, 0, insert?)
    end
  end

  def menu("toggle_menu_dot", _params, menu, insert?),
    do: lengthen(menu.id, nil, :toggle, insert?)

  def menu("to_rest", _params, menu, _insert?),
    do: &Editing.to_rest(&1, &2, Editing.chord_ids(&1, &2, menu.id))

  def menu("to_note", _params, %{step: step} = menu, _insert?) when is_integer(step),
    do: &Editing.to_note(&1, &2, menu.id, step, Pitch.key_alter(&2.sf, Pitch.letter(step)))

  def menu("tie_next", _params, menu, _insert?), do: &tie_next(&1, &2, menu.id)

  def menu("untie", _params, menu, _insert?),
    do: fn score, _ctx -> {:ok, Editing.untie(score, menu.id)} end

  def menu("menu_delete", _params, menu, _insert?), do: &Editing.delete(&1, &2, menu.ids)
  def menu("reverse", _params, menu, _insert?), do: &Editing.reverse(&1, &2, menu.ids)

  def menu("transpose", %{"by" => by, "dir" => dir} = params, menu, _insert?),
    do: transpose(menu.ids, by, dir, params["interval"])

  def menu(_event, _params, _menu, _insert?), do: refused(:not_found)

  # Sets a new length (or toggles the dot); in Insert mode a longer length
  # first moves later music on that staff right to make room.
  defp lengthen(id, value, dots, insert?) do
    fn score, ctx ->
      case Enum.find(Timeline.flatten(score, ctx), &(&1.event.id == id)) do
        nil ->
          {:error, :not_found}

        entry ->
          set_length(
            score,
            ctx,
            entry,
            value || entry.event.value,
            new_dots(entry, dots),
            insert?
          )
      end
    end
  end

  defp new_dots(entry, :toggle), do: if(entry.event.dots > 0, do: 0, else: 1)
  defp new_dots(_entry, dots), do: dots

  defp set_length(score, ctx, entry, value, dots, insert?) do
    extra = Duration.ticks(value, dots) - entry.ticks

    room =
      if insert? and extra > 0,
        do: Editing.insert_time(score, ctx, entry.start + entry.ticks, extra, entry.event.staff),
        else: {:ok, score}

    with {:ok, score} <- room do
      Editing.set_value(score, ctx, Editing.chord_ids(score, ctx, entry.event.id), value, dots)
    end
  end

  # Ties a note to the note of the same pitch that starts where it ends.
  defp tie_next(score, ctx, id) do
    notes = for %{kind: :note} = entry <- Timeline.flatten(score, ctx), do: entry

    with {:ok, from} <- find(notes, &(&1.event.id == id), :not_found),
         {:ok, to} <- find(notes, &follows?(&1, from), :not_tieable),
         do: Editing.tie(score, ctx, id, to.event.id)
  end

  defp follows?(entry, from) do
    entry.start == from.start + from.ticks and entry.event.staff == from.event.staff and
      Note.midi(entry.event) == Note.midi(from.event)
  end

  defp find(list, fun, reason) do
    case Enum.find(list, fun) do
      nil -> {:error, reason}
      found -> {:ok, found}
    end
  end

  @doc """
  Pastes a clipboard at absolute tick `at`. Paste always inserts: each staff
  the clipboard covers first makes room, so existing music from `at` on
  moves right.
  """
  @spec paste(Clipboard.t(), non_neg_integer()) :: edit()
  def paste(clipboard, at) do
    length = clipboard.entries |> Enum.map(&(&1.start + &1.ticks)) |> Enum.max(fn -> 0 end)
    staves = clipboard.entries |> Enum.map(& &1.event.staff) |> Enum.uniq()

    fn score, ctx ->
      with {:ok, score} <- insert_on(score, ctx, staves, at, length),
           do: Editing.paste(score, ctx, clipboard, at)
    end
  end

  defp insert_on(score, _ctx, [], _at, _length), do: {:ok, score}

  defp insert_on(score, ctx, [staff | rest], at, length) do
    with {:ok, score} <- Editing.insert_time(score, ctx, at, length, staff),
         do: insert_on(score, ctx, rest, at, length)
  end

  defp refused(reason), do: fn _score, _ctx -> {:error, reason} end
end
