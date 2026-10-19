defmodule DrawMusicWeb.PageController do
  use DrawMusicWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
