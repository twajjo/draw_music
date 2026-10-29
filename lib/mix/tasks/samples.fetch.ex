defmodule Mix.Tasks.Samples.Fetch do
  @shortdoc "Downloads instrument samples for playback"

  @moduledoc """
  Downloads instrument samples into the samples directory
  (`config :draw_music, :samples_dir`), which the app serves at `/samples`.

      mix samples.fetch                 # the Splendid Grand Piano + the default set
      mix samples.fetch flute cello 40  # GM names, soundfont stems or program numbers
      mix samples.fetch --list          # every GM instrument, marking installed ones

  Files already downloaded are skipped.
  """

  use Mix.Task

  alias DrawMusic.Samples

  @bytes_per_mb 1_000_000
  # Program numbers 0..127, right-aligned.
  @number_width 3

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, strict: [list: :boolean]) do
      {[list: true], _names, []} -> list()
      {[], names, []} -> fetch(names)
      {_opts, _names, invalid} -> Mix.raise("Unknown options: #{inspect(invalid)}")
    end
  end

  defp list do
    start()

    installed = Samples.installed()

    for instrument <- Samples.instruments() do
      marker = marker(MapSet.member?(installed, instrument.program))
      number = String.pad_leading(to_string(instrument.program), @number_width)
      Mix.shell().info("#{number}  #{instrument.name}#{marker}")
    end
  end

  defp marker(true = _installed?), do: "  [installed]"
  defp marker(false), do: ""

  defp fetch(names) do
    items = items(names)
    start()

    for {item, result} <- Samples.fetch_many(items) do
      Mix.shell().info("#{label(item)}  #{outcome(result)}")
    end
  end

  defp items([]), do: [:splendid | Samples.default_set()]
  defp items(names), do: Enum.map(names, &lookup!/1)

  defp lookup!(name) do
    case Samples.lookup(name) do
      {:ok, instrument} ->
        instrument

      {:error, {:unknown, []}} ->
        Mix.raise("Unknown instrument #{inspect(name)}.")

      {:error, {:unknown, close}} ->
        Mix.raise("Unknown instrument #{inspect(name)}. Did you mean: #{Enum.join(close, ", ")}?")
    end
  end

  # Compile-time config is all it needs (`:samples_dir`, `:samples_req`):
  # not runtime.exs, which in prod asks for a database and secrets that an
  # image build doesn't have.
  defp start do
    Mix.Task.run("compile")
    {:ok, _apps} = Application.ensure_all_started(:req)
  end

  defp label(:splendid), do: "splendid_grand_piano"
  defp label(instrument), do: instrument.stem

  defp outcome({:ok, bytes}), do: "#{Float.round(bytes / @bytes_per_mb, 1)} MB  ok"
  defp outcome({:error, reason}), do: "failed: #{inspect(reason)}"
end
