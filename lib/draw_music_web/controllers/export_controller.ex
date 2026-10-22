defmodule DrawMusicWeb.ExportController do
  use DrawMusicWeb, :controller

  alias DrawMusic.MidiCodec
  alias DrawMusicWeb.{ScoreExport, VersionLookup}

  @doc "Downloads a version's score as a print-ready SVG."
  def svg(conn, params) do
    version = VersionLookup.fetch!(conn.assigns.current_scope, params)

    download(
      conn,
      "image/svg+xml",
      ScoreExport.filename(version, "svg"),
      ScoreExport.svg(version)
    )
  end

  @doc "Downloads a version as a Standard MIDI File (it re-imports exactly)."
  def mid(conn, params) do
    version = VersionLookup.fetch!(conn.assigns.current_scope, params)
    {:ok, midi} = MidiCodec.export(version)
    download(conn, "audio/midi", ScoreExport.filename(version, "mid"), midi)
  end

  defp download(conn, content_type, filename, body) do
    conn
    |> put_resp_content_type(content_type, nil)
    |> put_resp_header("content-disposition", content_disposition(filename))
    |> send_resp(200, body)
  end

  # An ASCII fallback name, plus the real (UTF-8) name for browsers that
  # understand RFC 6266's `filename*`.
  defp content_disposition(filename) do
    ascii = String.replace(filename, ~r/[^\x20-\x7e]|["\\]/u, "_")

    ~s(attachment; filename="#{ascii}"; filename*=UTF-8''#{URI.encode(filename, &URI.char_unreserved?/1)})
  end
end
