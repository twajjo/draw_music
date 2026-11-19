defmodule DrawMusic.Music.MovingRestsTest do
  use ExUnit.Case, async: true

  import DrawMusic.MusicHelpers

  alias DrawMusic.Music.{Context, Editing, Score, Timeline}

  @ctx %Context{}

  test "a rest moves past the note beside it, and the bar's rests come out whole" do
    {score, _half} = bass_note(two_bars(), 0, "C3", :half, 0)

    {:ok, score, [selected]} = Editing.step_rest(score, @ctx, rest_at(score, 1920), :earlier)
    assert bass(score) == [{0, 1920, :rest}, {1920, 1920, :note}, {3840, 3840, :rest}]
    assert selected == rest_at(score, 0)

    {:ok, score, _ids} = Editing.step_rest(score, @ctx, selected, :later)
    assert bass(score) == [{0, 1920, :note}, {1920, 1920, :rest}, {3840, 3840, :rest}]
  end

  test "a rest moved over a bar line rewrites both bars: the note is split and tied" do
    {score, _quarter} = bass_note(two_bars(), 0, "C3", :quarter, 2880)
    {score, half} = bass_note(score, 1, "E3", :half, 0)

    {:ok, score, _ids} = Editing.step_rest(score, @ctx, rest_at(score, 1920), :later)
    {:ok, score, _ids} = Editing.step_rest(score, @ctx, rest_at(score, 2880), :later)

    assert bass(score) == [
             {0, 1920, :rest},
             {1920, 960, :note},
             {2880, 960, :note},
             {3840, 960, :note},
             {4800, 960, :rest},
             {5760, 1920, :rest}
           ]

    assert length(tie_chain(score, half)) == 2
  end

  test "with nothing beside it, or for a note, nothing moves" do
    score = two_bars()
    last = rest_at(score, 3840)
    assert {:ok, ^score, [^last]} = Editing.step_rest(score, @ctx, last, :later)

    {score, note} = bass_note(score, 0, "C3", :quarter, 0)
    assert Editing.step_rest(score, @ctx, note, :later) == {:error, :not_found}
  end

  # The bass staff as {start, ticks, kind}, in time order.
  defp bass(score) do
    for entry <- Timeline.flatten(score, @ctx), entry.event.staff == :bass do
      {entry.start, entry.ticks, entry.kind}
    end
    |> Enum.sort()
  end

  defp bass_note(score, measure, spn, value, offset) do
    note!(score, @ctx, measure, spn, %{staff: :bass, value: value, offset: offset})
  end

  defp rest_at(score, start) do
    Enum.find_value(Timeline.flatten(score, @ctx), fn entry ->
      entry.event.staff == :bass and entry.kind == :rest and entry.start == start and
        entry.event.id
    end)
  end

  defp two_bars, do: Editing.fill_rests(Score.new(2), @ctx)
end
