defmodule DrawMusic.Music.KeyDetection do
  @moduledoc """
  The key music is in, from its notes (Krumhansl–Schmuckler): how long
  each pitch class sounds is compared with how strongly each pitch class
  belongs to each of the 24 major and minor keys (Krumhansl and Kessler's
  profiles), and the best match wins. Given a piece's opening, it finds
  the key it starts in, even when the piece changes key later.
  """

  @major [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
  @minor [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
  @semitones 12
  # Fifths up from C: the key signature of a major key on each pitch class.
  @fifth 7
  @minor_to_relative_major 3

  @doc """
  The `{sf, mode}` key signature that best fits `notes` (`{midi, ticks}`
  pairs), or nil with no notes.
  """
  @spec detect([{0..127, pos_integer()}]) :: {-7..7, :major | :minor} | nil
  def detect([]), do: nil

  def detect(notes) do
    [{key, _fit} | _others] = ranked(notes)
    key
  end

  @doc """
  All 24 keys as `{{sf, mode}, fit}`, best fit first, for `notes` (`{midi,
  ticks}` pairs). `fit` is a correlation, -1.0 to 1.0. Six sharps or flats
  are written with sharps, so F♯ major and G♭ major are the one key.
  """
  @spec ranked([{0..127, pos_integer()}]) :: [{{-7..7, :major | :minor}, float()}]
  def ranked(notes) do
    weights = Enum.reduce(notes, List.duplicate(0, @semitones), &add_note/2)

    for tonic <- 0..(@semitones - 1), {mode, profile} <- [major: @major, minor: @minor] do
      {{signature(tonic, mode), mode}, correlation(weights, rotate(profile, tonic))}
    end
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  defp add_note({midi, ticks}, weights) do
    List.update_at(weights, rem(midi, @semitones), &(&1 + ticks))
  end

  defp correlation(xs, ys) do
    mean_x = Enum.sum(xs) / @semitones
    mean_y = Enum.sum(ys) / @semitones
    dx = Enum.map(xs, &(&1 - mean_x))
    dy = Enum.map(ys, &(&1 - mean_y))
    spread = :math.sqrt(sum_of_squares(dx) * sum_of_squares(dy))

    if spread == 0, do: 0.0, else: dot(dx, dy) / spread
  end

  defp dot(xs, ys), do: xs |> Enum.zip_with(ys, &(&1 * &2)) |> Enum.sum()

  # The profile with its tonic moved to `tonic`.
  defp rotate(profile, tonic) do
    {head, tail} = Enum.split(profile, @semitones - tonic)
    tail ++ head
  end

  # Sharps count up, flats down; six either way is written with sharps.
  defp signature(tonic, :minor),
    do: signature(rem(tonic + @minor_to_relative_major, @semitones), :major)

  defp signature(tonic, :major) do
    case rem(tonic * @fifth, @semitones) do
      sharps when sharps <= 6 -> sharps
      sharps -> sharps - @semitones
    end
  end

  defp sum_of_squares(xs), do: dot(xs, xs)
end
