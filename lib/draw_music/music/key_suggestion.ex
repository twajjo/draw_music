defmodule DrawMusic.Music.KeySuggestion do
  @moduledoc """
  Better keys for a score whose notes carry many accidentals in its own key,
  as when notes entered by ear into C major are really in E♭.

  `suggest/2` counts the accidentals the score would be written with in
  each key, once re-keyed (`DrawMusic.Music.Rekey`). The best fit is the key
  that leaves the fewest; where keys tie (a major key and its relative minor
  share a signature), the one that suits the notes better comes first (how
  long each pitch class sounds, `DrawMusic.Music.KeyDetection.ranked/1`).
  It offers the best keys that write fewer accidentals than the current
  one, on at most two different notes, and says whether any is worth
  offering: one must write clearly fewer, by count and by share.

  One key for the whole piece: music that changes key gets the best single
  key.
  """

  alias DrawMusic.Music.{Accidentals, Duration, KeyDetection, KeyFit, Pitch, Rekey, Score}

  # At most this many keys are offered.
  @offered 4
  # Worth offering: a key writing at least this many fewer accidentals, and
  # at most this share of the current key's. Few enough that a short piece,
  # a few bars with a handful of accidentals, gets its suggestion.
  @min_fewer 2
  @max_share 0.5
  # A key is offered only if its accidentals are at most this many different
  # notes (a key that suits the music still writes, say, a raised 7th in
  # every bar; one needing many different notes altered doesn't suit it).
  @max_notes 2
  @signs %{-2 => "𝄫", -1 => "♭", 0 => "♮", 1 => "♯", 2 => "𝄪"}

  @enforce_keys [:accidentals, :keys, :worth_it?]
  defstruct [:accidentals, :keys, :worth_it?]

  @typedoc """
  `accidentals`: those written in the current key; `keys`: the keys offered,
  best fit (fewest accidentals) first; `worth_it?`: whether one writes
  clearly fewer.
  """
  @type t :: %__MODULE__{
          accidentals: non_neg_integer(),
          keys: [KeyFit.t()],
          worth_it?: boolean()
        }

  @doc "The keys to offer for `score`, now in key `{sf, mode}`."
  @spec suggest(Score.t(), {-7..7, :major | :minor}) :: t()
  def suggest(%Score{} = score, {sf, _mode} = current) do
    now = length(written_accidentals(score, sf))
    ranked = KeyDetection.ranked(sounding(score))
    # Written once per key signature: a major and its relative minor share one.
    signatures = Enum.uniq(for {{key_sf, _mode}, _fit} <- ranked, do: key_sf)
    written = Map.new(signatures, &{&1, written_accidentals(Rekey.to_signature(score, &1), &1)})

    keys =
      for {{key_sf, mode} = key, fit} <- ranked, key != current do
        signs = Map.fetch!(written, key_sf)

        %KeyFit{
          sf: key_sf,
          mode: mode,
          fit: fit,
          accidentals: length(signs),
          accidental_notes: Enum.uniq(signs)
        }
      end
      |> Enum.filter(&(&1.accidentals < now and length(&1.accidental_notes) <= @max_notes))
      |> Enum.sort_by(&{&1.accidentals, -&1.fit})
      |> Enum.take(@offered)

    %__MODULE__{
      accidentals: now,
      keys: keys,
      worth_it?: Enum.any?(keys, &clearly_fewer?(&1, now))
    }
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

  # Each accidental written in key signature `sf`, in the order they come,
  # named without an octave (F♯, B♮).
  defp written_accidentals(%Score{measures: measures}, sf) do
    for measure <- measures,
        shown = Accidentals.displayed(measure, sf),
        note <- Enum.sort_by(measure.notes, &{&1.offset, &1.step}),
        Map.has_key?(shown, note.id) do
      Pitch.letter_name(note.step) <> Map.fetch!(@signs, note.alter)
    end
  end
end
