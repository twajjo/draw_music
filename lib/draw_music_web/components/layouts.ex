defmodule DrawMusicWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DrawMusicWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  The signed-in user's menu: the display theme, Preferences and Log out,
  behind a button showing the user's email. Clicking elsewhere closes it.
  """
  attr :user, :map, required: true

  attr :preferences_patch, :string,
    default: nil,
    doc: "patch to this for Preferences (the page stays); otherwise go to the Preferences page"

  @spec account_menu(map()) :: Phoenix.LiveView.Rendered.t()
  def account_menu(assigns) do
    ~H"""
    <div class="relative">
      <button
        id="account-menu-button"
        type="button"
        class="btn btn-ghost btn-sm gap-1 font-normal"
        aria-haspopup="menu"
        phx-click={
          JS.toggle(
            to: "#account-menu",
            in: {"transition ease-out duration-150", "opacity-0 scale-95", "opacity-100 scale-100"},
            out: {"transition ease-in duration-100", "opacity-100 scale-100", "opacity-0 scale-95"}
          )
        }
      >
        <.icon name="hero-user-circle" class="size-5" />
        <span class="hidden max-w-56 truncate md:inline">{@user.email}</span>
        <.icon name="hero-chevron-down-micro" class="size-4 opacity-60" />
      </button>
      <div
        id="account-menu"
        role="menu"
        class="absolute right-0 z-30 mt-2 hidden w-64 space-y-1 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
        phx-click-away={
          JS.hide(
            to: "#account-menu",
            transition:
              {"transition ease-in duration-100", "opacity-100 scale-100", "opacity-0 scale-95"}
          )
        }
      >
        <p class="truncate px-2 pb-1 text-xs opacity-60 md:hidden">{@user.email}</p>
        <button
          :if={@preferences_patch}
          id="account-menu-settings"
          type="button"
          phx-click={JS.hide(to: "#account-menu") |> JS.patch(@preferences_patch, replace: true)}
          role="menuitem"
          class="flex w-full items-center gap-2 rounded px-2 py-1.5 text-sm transition-colors hover:bg-base-200"
        >
          <.icon name="hero-cog-6-tooth" class="size-4" /> Preferences
        </button>
        <.link
          :if={!@preferences_patch}
          id="account-menu-settings"
          href={~p"/users/preferences"}
          role="menuitem"
          class="flex items-center gap-2 rounded px-2 py-1.5 text-sm transition-colors hover:bg-base-200"
        >
          <.icon name="hero-cog-6-tooth" class="size-4" /> Preferences
        </.link>
        <%!-- Email and password: always the account's own page, which leaves
             the editor (whose unsaved-changes guard asks first). --%>
        <.link
          id="account-menu-account"
          href={~p"/users/settings"}
          role="menuitem"
          class="flex items-center gap-2 rounded px-2 py-1.5 text-sm transition-colors hover:bg-base-200"
        >
          <.icon name="hero-user-circle" class="size-4" /> Manage account
        </.link>
        <.link
          id="account-menu-log-out"
          href={~p"/users/log-out"}
          method="delete"
          role="menuitem"
          class="flex items-center gap-2 rounded px-2 py-1.5 text-sm transition-colors hover:bg-base-200"
        >
          <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Log out
        </.link>
      </div>
    </div>
    """
  end

  @doc """
  The app layout: the header (wordmark, navigation, theme toggle and
  account links) above the page content.

  ## Examples

      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :wide, :boolean, default: false, doc: "use the full window width (e.g. for a score)"

  attr :preferences_patch, :string,
    default: nil,
    doc:
      "where the account menu's Preferences patches to, in a page with its own panel (the editor)"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true
  @spec app(map()) :: Phoenix.LiveView.Rendered.t()
  def app(assigns) do
    ~H"""
    <header
      id="app-header"
      class="flex flex-nowrap items-center gap-4 whitespace-nowrap border-b border-base-300 px-4 py-2 sm:px-6 lg:px-8"
    >
      <.link
        navigate={~p"/"}
        class="flex shrink-0 items-center gap-2 text-lg font-semibold tracking-tight transition-opacity hover:opacity-80"
      >
        <.icon name="hero-musical-note" class="size-6 text-primary" />
        <span class="hidden sm:inline">DrawMusic</span>
      </.link>

      <nav :if={@current_scope} class="flex items-center gap-1 text-sm">
        <.link id="nav-new" navigate={~p"/"} class="btn btn-ghost btn-sm">New</.link>
        <.link id="nav-compositions" navigate={~p"/compositions"} class="btn btn-ghost btn-sm">
          Compositions
        </.link>
      </nav>

      <div class="ml-auto flex items-center gap-2 text-sm">
        <%= if @current_scope do %>
          <.account_menu user={@current_scope.user} preferences_patch={@preferences_patch} />
        <% else %>
          <.link href={~p"/users/log-in"} class="btn btn-ghost btn-sm">Log in</.link>
          <.link href={~p"/users/register"} class="btn btn-primary btn-sm">Register</.link>
        <% end %>
      </div>
    </header>

    <main
      class={["score-colors px-4 sm:px-6 lg:px-8", if(@wide, do: "py-6", else: "py-20")]}
      style={score_ink_style(@current_scope)}
    >
      <div class={["mx-auto space-y-4", if(@wide, do: "max-w-none", else: "max-w-2xl")]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <footer class="flex items-center justify-center gap-4 border-t border-base-300 px-4 py-4 text-sm opacity-70">
      <.link id="footer-help" navigate={~p"/help"} class="link link-hover">Keys and mouse</.link>
      <.link id="footer-credits" navigate={~p"/credits"} class="link link-hover">Credits</.link>
    </footer>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"
  @spec flash_group(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  The `style` carrying the user's dark-mode score ink (see `.score-colors`
  in `app.css`); nil when signed out or unset. The value is validated as
  `#rrggbb` when saved.
  """
  @spec score_ink_style(DrawMusic.Accounts.Scope.t() | nil) :: String.t() | nil
  def score_ink_style(%{user: %{score_ink_dark: "#" <> _ = color}}) do
    "--score-ink-dark: #{color}"
  end

  def score_ink_style(_scope), do: nil
end
