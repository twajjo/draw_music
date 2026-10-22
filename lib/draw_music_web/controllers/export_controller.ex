defmodule DrawMusicWeb.ExportController do
  use DrawMusicWeb, :controller

  alias DrawMusicWeb.{ScoreExport, VersionLookup}

  @doc "Downloads a version's score as a print-ready SVG."
  def svg(conn, params) do
    version = VersionLookup.fetch!(conn.assigns.current_scope, params)

    conn
    |> put_resp_content_type("image/svg+xml")
    |> put_resp_header("content-disposition", content_disposition(ScoreExport.filename(version)))
    |> send_resp(200, ScoreExport.svg(version))
  end

  # An ASCII fallback name, plus the real (UTF-8) name for browsers that
  # understand RFC 6266's `filename*`.
  defp content_disposition(filename) do
    ascii = String.replace(filename, ~r/[^\x20-\x7e]|["\\]/u, "_")

    ~s(attachment; filename="#{ascii}"; filename*=UTF-8''#{URI.encode(filename, &URI.char_unreserved?/1)})
  end
end
