defmodule DrawMusic.Samples.Manifest do
  @moduledoc """
  What has been downloaded into a samples directory (`manifest.json`):
  each MusyngKite soundfont by stem, and the Splendid Grand Piano set, with
  their sizes and when they were fetched. A missing or unreadable manifest
  reads as empty, so nothing counts as installed.
  """

  alias DrawMusic.Samples.ManifestEntry

  @file_name "manifest.json"

  defstruct soundfonts: %{}, splendid: nil

  @type entry :: ManifestEntry.t()
  @type t :: %__MODULE__{soundfonts: %{String.t() => entry()}, splendid: entry() | nil}

  @doc "Reads the manifest in `dir`; empty when it is missing or corrupt."
  @spec read(Path.t()) :: t()
  def read(dir) do
    with {:ok, json} <- File.read(Path.join(dir, @file_name)),
         {:ok, %{"soundfonts" => soundfonts, "splendid" => splendid}} when is_map(soundfonts) <-
           JSON.decode(json),
         {:ok, soundfonts} <- entries(soundfonts),
         {:ok, splendid} <- optional_entry(splendid) do
      %__MODULE__{soundfonts: soundfonts, splendid: splendid}
    else
      _unreadable -> %__MODULE__{}
    end
  end

  @doc "Writes `manifest` into `dir`, creating the directory if needed."
  @spec write(t(), Path.t()) :: :ok
  def write(%__MODULE__{} = manifest, dir) do
    File.mkdir_p!(dir)

    json =
      JSON.encode!(%{
        "soundfonts" => Map.new(manifest.soundfonts, fn {stem, entry} -> {stem, dump(entry)} end),
        "splendid" => manifest.splendid && dump(manifest.splendid)
      })

    File.write!(Path.join(dir, @file_name), json)
  end

  defp dump(%ManifestEntry{bytes: bytes, fetched_at: at}) do
    %{"bytes" => bytes, "fetched_at" => DateTime.to_iso8601(at)}
  end

  defp entries(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {stem, raw}, {:ok, acc} ->
      case entry(raw) do
        {:ok, entry} -> {:cont, {:ok, Map.put(acc, stem, entry)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp optional_entry(nil), do: {:ok, nil}
  defp optional_entry(raw), do: entry(raw)

  defp entry(%{"bytes" => bytes, "fetched_at" => at})
       when is_integer(bytes) and bytes >= 0 and is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, fetched_at, _offset} -> {:ok, %ManifestEntry{bytes: bytes, fetched_at: fetched_at}}
      _invalid -> :error
    end
  end

  defp entry(_raw), do: :error
end
