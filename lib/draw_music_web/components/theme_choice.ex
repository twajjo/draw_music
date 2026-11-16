defmodule DrawMusicWeb.ThemeChoice do
  @moduledoc """
  The application's theme (system, light or dark) as a field of the
  Preferences form.

  The theme lives in this browser (localStorage `"phx:theme"`, read by the
  root layout before the page draws), never on the server, so the field is
  the browser's own: its colocated hook checks the stored theme when it
  mounts, previews a pick at once without storing it, and puts the stored
  theme back when it goes (Cancel, Back, leaving the page). The form tells it
  the rest with `push_event/3`:

    * `"theme:save"`: store the picked theme (on Save).
    * `"theme:default"`: pick "system" and preview it (on Defaults).

  The UI theme is the application's look, not the score's: the score's paper
  is a separate preference.
  """

  use DrawMusicWeb, :html

  @themes [
    {"system", "System", "hero-computer-desktop-micro"},
    {"light", "Light", "hero-sun-micro"},
    {"dark", "Dark", "hero-moon-micro"}
  ]

  @doc "The theme's section: three choices, the stored one checked by the hook."
  attr :id, :string, required: true
  @spec theme_choice(map()) :: Phoenix.LiveView.Rendered.t()
  def theme_choice(assigns) do
    assigns = assign(assigns, :themes, @themes)

    ~H"""
    <section id="appearance" class="space-y-4">
      <.header>
        Appearance
        <:subtitle>Follow your system, or always use light or dark (kept in this browser)</:subtitle>
      </.header>
      <div
        id={@id}
        class="join"
        role="radiogroup"
        aria-label="Theme"
        phx-hook=".ThemeChoice"
        phx-update="ignore"
      >
        <.theme_option
          :for={{theme, label, icon} <- @themes}
          id={"#{@id}-#{theme}"}
          theme={theme}
          label={label}
          icon={icon}
        />
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ThemeChoice">
        const KEY = "phx:theme"

        const stored = () => {
          return localStorage.getItem(KEY) || "system"
        }

        const systemTheme = () => {
          return matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
        }

        // Shows a theme without storing it (as the root layout does).
        const show = (theme) => {
          const root = document.documentElement
          root.setAttribute("data-theme", theme === "system" ? systemTheme() : theme)
          root.setAttribute("data-theme-source", theme === "system" ? "system" : "user")
        }

        const store = (theme) => {
          if (theme === "system") {
            localStorage.removeItem(KEY)
          } else {
            localStorage.setItem(KEY, theme)
          }
          show(theme)
        }

        export default {
          mounted() {
            this.pick(stored())
            this.el.addEventListener("change", (e) => show(e.target.value))
            this.handleEvent("theme:default", () => {
              this.pick("system")
              show("system")
            })
            this.handleEvent("theme:save", () => store(this.picked()))
          },
          // Whatever was previewed, the stored theme is back (unchanged after Save).
          destroyed() {
            show(stored())
          },
          pick(theme) {
            const input = this.el.querySelector(`input[value="${theme}"]`)
            if (input) input.checked = true
          },
          picked() {
            const input = this.el.querySelector("input:checked")
            return input ? input.value : stored()
          }
        }
      </script>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :theme, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  # One choice; drawn as chosen by CSS alone, since the server never knows
  # which one is checked.
  defp theme_option(assigns) do
    ~H"""
    <label
      id={@id}
      class="join-item btn btn-sm btn-ghost transition-colors has-[:checked]:bg-primary has-[:checked]:text-primary-content"
    >
      <input type="radio" name="theme" value={@theme} class="sr-only" />
      <.icon name={@icon} class="size-4" />
      {@label}
    </label>
    """
  end
end
