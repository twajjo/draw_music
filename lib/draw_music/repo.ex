defmodule DrawMusic.Repo do
  use Ecto.Repo,
    otp_app: :draw_music,
    adapter: Ecto.Adapters.Postgres
end
