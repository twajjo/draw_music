defmodule DrawMusicWeb.Router do
  use DrawMusicWeb, :router

  import DrawMusicWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DrawMusicWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", DrawMusicWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:draw_music, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DrawMusicWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", DrawMusicWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{DrawMusicWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      # The signed-in user's own compositions. The main page is a blank,
      # unsaved composition.
      live "/", EditorLive, :new
      live "/compositions", LibraryLive, :index
      live "/compositions/new", NewCompositionLive, :new
      live "/compositions/:id/:key/v/:number", EditorLive, :show
    end

    post "/users/update-password", UserSessionController, :update_password
    get "/compositions/:id/:key/v/:number/score.svg", ExportController, :svg
    get "/compositions/:id/:key/v/:number/score.mid", ExportController, :mid
  end

  scope "/", DrawMusicWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{DrawMusicWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
