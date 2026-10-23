defmodule DrawMusic.SamplesTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Samples
  alias DrawMusic.Samples.Manifest

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

  describe "storage and fetching" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      {:ok, requests} = Agent.start_link(fn -> [] end)

      %{
        dir: dir,
        requests: requests,
        flute: Samples.instrument!(73),
        cello: Samples.instrument!(42)
      }
    end

    defp stub(requests, respond) do
      Req.Test.stub(DrawMusic.Samples, fn conn ->
        Agent.update(requests, &[conn.request_path | &1])
        respond.(conn)
      end)
    end

    defp ok_body(conn), do: Plug.Conn.send_resp(conn, 200, "0123456789")

    test "an empty, missing or corrupt manifest means nothing is installed", %{dir: dir} do
      refute Samples.installed?(73, dir: Path.join(dir, "missing"))
      assert Manifest.read(dir) == %Manifest{soundfonts: %{}, splendid: nil}

      File.write!(Path.join(dir, "manifest.json"), "{not json")
      assert Manifest.read(dir) == %Manifest{soundfonts: %{}, splendid: nil}
      refute Samples.installed?(73, dir: dir)
    end

    test "fetch writes the file and records it; installed? reads the manifest",
         %{dir: dir, requests: requests, flute: flute} do
      stub(requests, &ok_body/1)

      assert [{^flute, {:ok, 10}}] = Samples.fetch_many([flute], dir: dir)
      assert File.read!(Path.join(dir, "musyngkite/flute-mp3.js")) == "0123456789"
      assert Samples.installed?(73, dir: dir)
      refute Samples.installed?(42, dir: dir)
      assert File.exists?(Path.join(dir, "musyngkite/LICENSE.txt"))
    end

    test "a complete file is skipped; a short one is replaced",
         %{dir: dir, requests: requests, flute: flute} do
      stub(requests, &ok_body/1)

      Samples.fetch_many([flute], dir: dir)
      Samples.fetch_many([flute], dir: dir)
      assert length(Agent.get(requests, & &1)) == 1

      File.write!(Path.join(dir, "musyngkite/flute-mp3.js"), "012")
      Samples.fetch_many([flute], dir: dir)
      assert length(Agent.get(requests, & &1)) == 2
      assert File.stat!(Path.join(dir, "musyngkite/flute-mp3.js")).size == 10
    end

    test "a failed instrument leaves no file or manifest entry, and the others still land",
         %{dir: dir, requests: requests, flute: flute, cello: cello} do
      stub(requests, fn conn ->
        case String.ends_with?(conn.request_path, "flute-mp3.js") do
          true -> Plug.Conn.send_resp(conn, 500, "")
          false -> ok_body(conn)
        end
      end)

      assert [{^flute, {:error, _}}, {^cello, {:ok, 10}}] =
               Samples.fetch_many([flute, cello], dir: dir)

      refute Samples.installed?(73, dir: dir)
      assert Samples.installed?(42, dir: dir)
      refute File.exists?(Path.join(dir, "musyngkite/flute-mp3.js"))
      assert Path.wildcard(Path.join(dir, "**/*.tmp")) == []
    end

    test "the piano is installed if either the Splendid set or its soundfont is", %{dir: dir} do
      refute Samples.installed?(0, dir: dir)

      Manifest.write(%Manifest{splendid: %{bytes: 1, fetched_at: DateTime.utc_now()}}, dir)
      assert Samples.installed?(0, dir: dir)
      assert Samples.splendid?(dir: dir)
    end
  end
end
