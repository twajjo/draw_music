defmodule DrawMusic.Library.ValidationsTest do
  use ExUnit.Case, async: true

  import DrawMusic.DataCase, only: [errors_on: 1]

  alias DrawMusic.Accounts.{Scope, User}
  alias DrawMusic.Library.{Composition, Key, Version}

  @user_id Ecto.UUID.generate()
  @scope %Scope{user: %User{id: @user_id}}

  describe "Composition.changeset/3" do
    defp composition(attrs), do: Composition.changeset(%Composition{}, attrs, @scope)

    test "requires a non-blank name, trimmed, at most 120 characters" do
      assert %{name: ["can't be blank"]} = errors_on(composition(%{name: "   "}))
      assert %{name: [_]} = errors_on(composition(%{name: String.duplicate("x", 121)}))
      assert Ecto.Changeset.get_change(composition(%{name: "  Waltz "}), :name) == "Waltz"
    end

    test "limits credits to 255 characters and notes to 10,000" do
      long = String.duplicate("x", 256)

      errors =
        errors_on(
          composition(%{
            name: "A",
            subtitle: long,
            composer: long,
            arranger: long,
            lyricist: long,
            copyright: long,
            notes: String.duplicate("x", 10_001)
          })
        )

      assert Map.keys(errors) |> Enum.sort() ==
               [:arranger, :composer, :copyright, :lyricist, :notes, :subtitle]
    end

    test "owner comes from the scope, never from attrs" do
      changeset = composition(%{name: "A", user_id: Ecto.UUID.generate()})
      assert Ecto.Changeset.get_change(changeset, :user_id) == @user_id
    end
  end

  describe "Key.changeset/2" do
    defp key(attrs), do: Key.changeset(%Key{}, attrs)

    test "sf must be -7..7" do
      assert key(%{sf: -7, mode: :major}).valid?
      assert key(%{sf: 7, mode: :minor}).valid?
      assert %{sf: [_]} = errors_on(key(%{sf: -8, mode: :major}))
      assert %{sf: [_]} = errors_on(key(%{sf: 8, mode: :major}))
    end

    test "mode must be major or minor" do
      assert %{mode: ["is invalid"]} = errors_on(key(%{sf: 0, mode: "dorian"}))
      assert %{mode: ["can't be blank"]} = errors_on(key(%{sf: 0}))
    end
  end

  describe "Version.changeset/2" do
    defp version(attrs), do: Version.changeset(%Version{number: 1}, attrs)

    test "time signature: numerator 1..32, denominator a power of two up to 64" do
      assert version(%{time_num: 7, time_den: 8}).valid?
      assert %{time_num: [_]} = errors_on(version(%{time_num: 0}))
      assert %{time_num: [_]} = errors_on(version(%{time_num: 33}))
      assert %{time_den: [_]} = errors_on(version(%{time_den: 3}))
      assert %{time_den: [_]} = errors_on(version(%{time_den: 128}))
    end

    test "common time only for 4/4, cut time only for 2/2" do
      assert version(%{time_num: 4, time_den: 4, time_symbol: :common}).valid?
      assert version(%{time_num: 2, time_den: 2, time_symbol: :cut}).valid?

      assert %{time_symbol: ["common time is 4/4"]} =
               errors_on(version(%{time_num: 3, time_den: 4, time_symbol: :common}))

      assert %{time_symbol: ["cut time is 2/2"]} =
               errors_on(version(%{time_num: 4, time_den: 4, time_symbol: :cut}))
    end

    test "tempo 20..400 bpm, tempo text at most 60 characters" do
      assert %{tempo_bpm: [_]} = errors_on(version(%{tempo_bpm: 19}))
      assert %{tempo_bpm: [_]} = errors_on(version(%{tempo_bpm: 401}))
      assert %{tempo_text: [_]} = errors_on(version(%{tempo_text: String.duplicate("x", 61)}))
    end

    test "pickup is non-negative; instrument is a MIDI program 0..127" do
      assert %{pickup_ticks: [_]} = errors_on(version(%{pickup_ticks: -1}))
      assert %{instrument: [_]} = errors_on(version(%{instrument: -1}))
      assert %{instrument: [_]} = errors_on(version(%{instrument: 128}))
    end

    test "a pickup bar is shorter than a full measure" do
      assert version(%{time_num: 3, time_den: 4, pickup_ticks: 1920}).valid?

      assert %{pickup_ticks: ["must be shorter than a full measure"]} =
               errors_on(version(%{time_num: 3, time_den: 4, pickup_ticks: 2880}))
    end

    test "score params are validated down to each note" do
      note = %{"staff" => "treble", "offset" => 0, "value" => "quarter", "step" => 28}
      score = fn note -> %{score: %{"measures" => [%{"notes" => [note]}]}} end

      assert version(score.(note)).valid?

      assert %{score: %{measures: [%{notes: [%{step: [_]}]}]}} =
               errors_on(version(score.(%{note | "step" => 100})))

      assert %{score: %{measures: [%{notes: [%{voice: [_]}]}]}} =
               errors_on(version(score.(Map.put(note, "voice", 5))))
    end

    test "label at most 120 characters" do
      assert %{label: [_]} = errors_on(version(%{label: String.duplicate("x", 121)}))
    end

    test "number and key come from the context, never from attrs" do
      key_id = Ecto.UUID.generate()

      changeset =
        Version.changeset(%Version{number: 1, key_id: key_id}, %{
          number: 9,
          key_id: Ecto.UUID.generate()
        })

      assert Ecto.Changeset.get_field(changeset, :number) == 1
      assert Ecto.Changeset.get_field(changeset, :key_id) == key_id
    end
  end

  test "Key.slug/2 and Key.from_slug/1 round-trip every key" do
    for sf <- -7..7, mode <- [:major, :minor] do
      assert Key.from_slug(Key.slug(sf, mode)) == {:ok, {sf, mode}}
    end

    assert Key.slug(6, :major) == "f-sharp-major"
    assert Key.slug(-2, :minor) == "g-minor"
    assert Key.from_slug("h-major") == :error
  end

  test "Key.name/2 names keys from the key signature" do
    assert Key.name(0, :major) == "C major"
    assert Key.name(0, :minor) == "A minor"
    assert Key.name(-7, :major) == "C♭ major"
    assert Key.name(7, :major) == "C♯ major"
    assert Key.name(-7, :minor) == "A♭ minor"
    assert Key.name(7, :minor) == "A♯ minor"
  end
end
