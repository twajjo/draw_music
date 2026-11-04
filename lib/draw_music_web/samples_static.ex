defmodule DrawMusicWeb.SamplesStatic do
  @moduledoc """
  Serves the instrument samples at `/samples` from
  `DrawMusic.Samples.samples_dir/0`. The directory is read when a request
  comes, not when the endpoint compiles, so a release can set it at runtime
  (`SAMPLES_DIR`, e.g. a mounted volume).
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{path_info: ["samples" | _]} = conn, opts) do
    static =
      Plug.Static.init([at: "/samples", from: DrawMusic.Samples.samples_dir()] ++ opts)

    Plug.Static.call(conn, static)
  end

  def call(conn, _opts), do: conn
end
