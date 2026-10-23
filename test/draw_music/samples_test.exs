defmodule DrawMusic.SamplesTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Samples

  describe "the GM table" do
    test "has 128 programs with unique stems and all 16 families" do
      instruments = Samples.instruments()

      assert Enum.map(instruments, & &1.program) == Enum.to_list(0..127)
      assert instruments |> Enum.map(& &1.stem) |> Enum.uniq() |> length() == 128
      assert instruments |> Enum.map(& &1.family) |> Enum.uniq() == Samples.families()
      assert length(Samples.families()) == 16
    end

    test "the default set is the 12 named stems" do
      assert Enum.map(Samples.default_set(), & &1.stem) ==
               ~w(acoustic_grand_piano electric_piano_1 harpsichord church_organ
                  acoustic_guitar_nylon violin cello flute clarinet trumpet choir_aahs marimba)
    end

    test "lookup by name, stem or number; unknown names suggest close matches" do
      assert {:ok, %{program: 73}} = Samples.lookup("Flute")
      assert {:ok, %{program: 73}} = Samples.lookup("flute")
      assert {:ok, %{program: 24}} = Samples.lookup("acoustic_guitar_nylon")
      assert {:ok, %{program: 40}} = Samples.lookup("40")
      assert {:error, {:unknown, suggestions}} = Samples.lookup("flut")
      assert "flute" in suggestions
    end
  end
end
