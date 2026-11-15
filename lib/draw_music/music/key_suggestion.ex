defmodule DrawMusic.Music.KeySuggestion do
  @moduledoc """
  Better keys for a score whose notes carry many accidentals in its own key,
  as when notes entered by ear into C major are really in E♭.

  `suggest/2` ranks the keys by how well they suit the notes (how long each
  pitch class sounds, `DrawMusic.Music.KeyDetection.ranked/1`) and counts
  the accidentals the score would be written with in each, once re-keyed
  (`DrawMusic.Music.Rekey`). It offers the best-fitting keys that write
  fewer accidentals than the current one, and says whether any is worth
  offering: one must write clearly fewer, by count and by share.

  One key for the whole piece: music that changes key gets the best single
  key.
  """

  alias DrawMusic.Music.{Accidentals, Duration, KeyDetection, KeyFit, Pitch, Rekey, Score}

  # At most this many keys are offered.
  @offered 4
  # Worth offering: a key writing at least this many fewer accidentals, and
  # at most this share of the current key's.
  @min_fewer 6
  @max_share 0.5

  @enforce_keys [:accidentals, :keys, :worth_it?]
  defstruct [:accidentals, :keys, :worth_it?]

  @typedoc """
  `accidentals`: those written in the current key; `keys`: the keys offered,
  best fit first; `worth_it?`: whether one writes clearly fewer.
  """
  @type t :: %__MODULE__{
          accidentals: non_neg_integer(),
          keys: [KeyFit.t()],
          worth_it?: boolean()
        }

  @doc "The keys to offer for `score`, now in key `{sf, mode}`."
  @spec suggest(Score.t(), {-7..7, :major | :minor}) :: t()
  def suggest(%Score{} = score, {sf, _mode} = current) do
    now = accidentals(score, sf)

    keys =
      for {{key_sf, mode} = key, fit} <- KeyDetection.ranked(sounding(score)),
          key != current,
          count = accidentals(Rekey.to_signature(score, key_sf), key_sf),
          count < now do
        %KeyFit{sf: key_sf, mode: mode, fit: fit, accidentals: count}
      end
      |> Enum.take(@offered)

    %__MODULE__{
      accidentals: now,
      keys: keys,
      worth_it?: Enum.any?(keys, &clearly_fewer?(&1, now))
    }
  end

  # The accidentals written in key signature `sf`, every measure's.
  defp accidentals(%Score{measures: measures}, sf) do
    measures
    |> Enum.map(&map_size(Accidentals.displayed(&1, sf)))
    |> Enum.sum()
  end

  defp clearly_fewer?(%KeyFit{accidentals: count}, now) do
    now - count >= @min_fewer and count <= now * @max_share
  end

  # Each note's pitch and how long it sounds.
  defp sounding(%Score{measures: measures}) do
    for measure <- measures, note <- measure.notes do
      {Pitch.midi(note.step, note.alter), Duration.ticks(note.value, note.dots)}
    end
  end
end
