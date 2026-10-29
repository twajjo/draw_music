defmodule DrawMusicWeb.EditorCommands do
  @moduledoc """
  The edits behind the editor's gestures, menus and keys, each built as a
  function of `(score, ctx)` for `DrawMusic.Music.Session.edit/2`. Event
  params come from the browser: names are only looked up, never turned into
  atoms.
  """

  alias DrawMusic.Music.{
    Clipboard,
    Context,
    Duration,
    Editing,
    Note,
    Pitch,
    Score,
    TempoEditing,
    Timeline
  }

  alias DrawMusicWeb.{Armed, ContextMenu, EditorPalette, EditorPlacement}

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
  @octave Map.fetch!(@intervals, "P8")

  @doc """
  Drops dragged notes `steps` scale steps away, with `alter` if a modifier
  was held. Gives their ids.
  """
  @spec drop([Ecto.UUID.t()], integer(), -2..2 | nil) :: edit()
  def drop(ids, steps, alter) do
    fn score, ctx ->
      with {:ok, score} <- Editing.move_steps(score, ctx, ids, steps),
           {:ok, score} <- maybe_alter(score, ctx, ids, alter) do
        {:ok, score, ids}
      end
    end
  end

  @doc """
  Deletes the given notes, rests and tempo changes. In Overlay mode nothing
  else moves: the gap notes and rests leave shows as rests. In Insert mode
  later music on each staff moves left to close it. Tempo changes never
  move anything.
  """
  @spec delete([Ecto.UUID.t()], boolean()) :: edit()
  def delete(ids, insert?) do
    fn score, ctx ->
      tempo_ids = MapSet.new(TempoEditing.ids(score))
      {tempos, events} = Enum.split_with(ids, &(&1 in tempo_ids))
      delete_events(TempoEditing.remove(score, tempos), ctx, events, insert?)
    end
  end

  defp delete_events(score, _ctx, [], _insert?), do: {:ok, score}
  defp delete_events(score, ctx, ids, false = _insert?), do: Editing.remove(score, ctx, ids)
  defp delete_events(score, ctx, ids, true = _insert?), do: Editing.delete(score, ctx, ids)

  @doc """
  Turns the given notes into `chord`, each built on the lowest note of the
  chord it belongs to. Gives the new chords' ids.
  """
  @spec chordify([Ecto.UUID.t()], Armed.chord()) :: edit()
  def chordify(ids, chord) do
    fn score, ctx ->
      Editing.chordify(score, ctx, ids, &EditorPlacement.chord_pitches(ctx, chord, {&1, &2}))
    end
  end

  @doc """
  Drops one note on `step` of `staff`, which may be the other staff, with
  `alter` if a modifier was held. Gives the note's id (new if it changed staff).
  """
  @spec drop_on_staff(Ecto.UUID.t(), Note.staff(), integer(), -2..2 | nil) :: edit()
  def drop_on_staff(id, staff, step, alter) do
    fn score, ctx ->
      with {:ok, score, id} <- Editing.move_to_staff(score, ctx, id, staff, step),
           {:ok, score} <- maybe_alter(score, ctx, [id], alter) do
        {:ok, score, [id]}
      end
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
    sign = sign(dir)

    case {by, Map.get(@intervals, interval)} do
      {"step", _} -> &Editing.move_steps(&1, &2, ids, sign)
      # An exact octave keeps each note's accidental.
      {"octave", _} -> by_interval(ids, @octave, sign)
      {"semitone", _} -> &Editing.transpose_chromatic(&1, &2, ids, sign)
      {"interval", {_steps, _semitones} = interval} -> by_interval(ids, interval, sign)
      _ -> refused(:not_found)
    end
  end

  defp sign("down"), do: -1
  defp sign(_up), do: 1

  defp by_interval(ids, {steps, semitones}, sign) do
    &Editing.transpose_interval(&1, &2, ids, steps * sign, semitones * sign)
  end

  @doc """
  The edit a context-menu item makes. `menu` holds the right-clicked `id`,
  the `ids` it acts on and the clicked `step`; `insert?` is Insert mode.
  """
  # Split, length, dot and make-rest act on the right-clicked note's whole
  # chord, which must stay one chord.
  @spec menu(String.t(), map(), ContextMenu.t(), boolean()) :: edit()
  def menu("split", _params, menu, _insert?) do
    &Editing.split(&1, &2, Editing.chord_ids(&1, &2, menu.id))
  end

  def menu("set_value", %{"value" => name}, menu, insert?) do
    case EditorPalette.value(name) do
      nil -> refused(:unrepresentable)
      value -> lengthen(menu.id, value, 0, insert?)
    end
  end

  def menu("toggle_menu_dot", _params, menu, insert?) do
    lengthen(menu.id, nil, :toggle, insert?)
  end

  def menu("to_rest", _params, menu, _insert?) do
    &Editing.to_rest(&1, &2, Editing.chord_ids(&1, &2, menu.id))
  end

  def menu("to_note", _params, %{step: step} = menu, _insert?) when is_integer(step) do
    &Editing.to_note(&1, &2, menu.id, step, Pitch.key_alter(&2.sf, Pitch.letter(step)))
  end

  def menu("tie_next", _params, menu, _insert?), do: &tie_next(&1, &2, menu.id)

  # A diatonic third above the chord's top note or below its bottom one.
  def menu("add_third_above", _params, menu, _insert?) do
    &Editing.add_to_chord(&1, &2, menu.id, 2)
  end

  def menu("add_third_below", _params, menu, _insert?) do
    &Editing.add_to_chord(&1, &2, menu.id, -2)
  end

  def menu("untie", _params, menu, _insert?) do
    fn score, _ctx -> {:ok, Editing.untie(score, menu.id)} end
  end

  def menu("menu_delete", _params, menu, insert?), do: delete(menu.ids, insert?)
  def menu("reverse", _params, menu, _insert?), do: &Editing.reverse(&1, &2, menu.ids)

  def menu("transpose", %{"by" => by, "dir" => dir} = params, menu, _insert?) do
    transpose(menu.ids, by, dir, params["interval"])
  end

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

  defp new_dots(%{event: %{dots: 0}}, :toggle), do: 1
  defp new_dots(_entry, :toggle), do: 0
  defp new_dots(_entry, dots), do: dots

  # A 256th takes no dot, a 128th one more at most.
  defp set_length(score, ctx, entry, value, dots, insert?) do
    case Duration.dots_allowed?(value, dots) do
      true -> fit_length(score, ctx, entry, value, dots, insert?)
      false -> {:error, :unrepresentable}
    end
  end

  defp fit_length(score, ctx, entry, value, dots, insert?) do
    extra = Duration.ticks(value, dots) - entry.ticks

    with {:ok, score} <- make_room(score, ctx, entry, extra, insert?) do
      Editing.set_value(score, ctx, Editing.chord_ids(score, ctx, entry.event.id), value, dots)
    end
  end

  defp make_room(score, ctx, entry, extra, true = _insert?) when extra > 0 do
    Editing.insert_time(score, ctx, entry.start + entry.ticks, extra, entry.event.staff)
  end

  defp make_room(score, _ctx, _entry, _extra, _insert?), do: {:ok, score}

  # Ties a note to the note of the same pitch that starts where it ends.
  defp tie_next(score, ctx, id) do
    notes = for %{kind: :note} = entry <- Timeline.flatten(score, ctx), do: entry

    with {:ok, from} <- find(notes, &(&1.event.id == id), :not_found),
         {:ok, to} <- find(notes, &follows?(&1, from), :not_tieable) do
      Editing.tie(score, ctx, id, to.event.id)
    end
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
    length =
      clipboard.entries
      |> Enum.map(&(&1.start + &1.ticks))
      |> Enum.max(fn -> 0 end)

    staves =
      clipboard.entries
      |> Enum.map(& &1.event.staff)
      |> Enum.uniq()

    fn score, ctx ->
      with {:ok, score} <- insert_on(score, ctx, staves, at, length) do
        Editing.paste(score, ctx, clipboard, at)
      end
    end
  end

  defp insert_on(score, _ctx, [], _at, _length), do: {:ok, score}

  defp insert_on(score, ctx, [staff | rest], at, length) do
    with {:ok, score} <- Editing.insert_time(score, ctx, at, length, staff) do
      insert_on(score, ctx, rest, at, length)
    end
  end

  defp refused(reason), do: fn _score, _ctx -> {:error, reason} end
end
