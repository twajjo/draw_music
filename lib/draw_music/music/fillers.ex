defmodule DrawMusic.Music.Fillers do
  @moduledoc """
  Filler rests: the rests written into every gap (see
  `DrawMusic.Music.Gaps`), stored with `filler: true` so every rest drawn
  has an id. Filler gives way to whatever is placed or pushed into it, and
  is written afresh after each edit (`DrawMusic.Music.Editing.Rebuild`);
  rests the user placed or edited are kept like notes.
  """

  alias DrawMusic.Music.{Context, Entry, Gaps, Measure, Note, Rest, Score, Timeline}

  @typedoc "Where a filler rest sits, and how long it is: what keeps its id."
  @type key ::
          {Ecto.UUID.t(), Note.staff(), Note.voice(), non_neg_integer(), atom(), 0..2}

  @doc """
  The ids of each silent bar's filler rests (see `silent_bar?/2`), one list
  per measure and staff, in time order. Each list is drawn as one whole-bar
  rest, so it is selected as one item.
  """
  @spec bar_silences(Score.t()) :: [[Ecto.UUID.t()]]
  def bar_silences(%Score{} = score) do
    for measure <- score.measures, staff <- [:treble, :bass], silent_bar?(measure, staff) do
      for rest <- Enum.sort_by(measure.rests, & &1.offset), rest.staff == staff, do: rest.id
    end
  end

  @doc "An edited rest is the user's: it is no longer rewritten as filler."
  @spec claim(Note.t() | Rest.t()) :: Note.t() | Rest.t()
  def claim(%Rest{} = rest), do: %{rest | filler: false}
  def claim(event), do: event

  @doc """
  Rewrites the filler rests: every gap in voice 1 of each staff, and in any
  other voice that has notes in the measure, is filled with rests on the
  beats. A filler rest that comes out the same as before keeps its id.
  """
  @spec fill(Score.t(), Context.t()) :: Score.t()
  def fill(%Score{} = score, %Context{} = ctx), do: refill(score, ctx, ids(score))

  @doc "Whether an entry is a filler rest."
  @spec filler?(Entry.t()) :: boolean()
  def filler?(%{event: %Rest{filler: true}}), do: true
  def filler?(_entry), do: false

  @doc "The score's filler rests' ids, by where they sit (`t:key/0`)."
  @spec ids(Score.t()) :: %{key() => Ecto.UUID.t()}
  def ids(%Score{} = score) do
    for measure <- score.measures, %Rest{filler: true} = rest <- measure.rests, into: %{} do
      {key(measure, rest), rest.id}
    end
  end

  @doc """
  Like `fill/2`, keeping the ids in `old_ids` (from `ids/1` of the score
  before an edit) for filler rests that come out the same.
  """
  @spec refill(Score.t(), Context.t(), %{key() => Ecto.UUID.t()}) :: Score.t()
  def refill(%Score{measures: measures} = score, ctx, old_ids) do
    filled =
      measures
      |> Enum.zip(Timeline.bars(score, ctx))
      |> Enum.map(fn {measure, {_start, capacity}} ->
        kept = Enum.reject(measure.rests, & &1.filler)

        fillers =
          %{measure | rests: kept}
          |> Gaps.rests(capacity, ctx)
          |> Enum.map(fn rest ->
            %{rest | id: Map.get_lazy(old_ids, key(measure, rest), &Ecto.UUID.generate/0)}
          end)

        %{measure | rests: Enum.sort_by(kept ++ fillers, &{&1.offset, &1.staff, &1.voice})}
      end)

    %{score | measures: filled}
  end

  @doc """
  Whether `staff` of `measure` is a silent bar: no notes, and only filler
  rests, in one voice. However many rests the meter needs to fill it (a
  whole and a quarter in 5/4), it is drawn as one whole-bar rest. A rest
  the user placed keeps the bar from being silent: it is drawn as written.
  """
  @spec silent_bar?(Measure.t(), Note.staff()) :: boolean()
  def silent_bar?(%Measure{} = measure, staff) do
    rests = Enum.filter(measure.rests, &(&1.staff == staff))

    rests != [] and Enum.all?(rests, & &1.filler) and
      not Enum.any?(measure.notes, &(&1.staff == staff)) and
      match?([_one], Enum.uniq_by(rests, & &1.voice))
  end

  defp key(measure, rest) do
    {measure.id, rest.staff, rest.voice, rest.offset, rest.value, rest.dots}
  end
end
