defmodule DrawMusicWeb.HealthCheck do
  @moduledoc """
  Answers `GET /health` with 200 "ok" for the hosting platform's health
  checks, before sessions, logging and the router.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "GET", path_info: ["health"]} = conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
    |> halt()
  end

  def call(conn, _opts), do: conn
end
