defmodule DrawMusicWeb.Dropdown do
  @moduledoc """
  A dropdown menu: a `<details>` whose `<summary>` opens it, closed again
  by a click anywhere outside it, by Escape, or by picking an item (an item
  chains `close/2` before its own action).

  A native `<details>` only closes when its summary is clicked, so this
  closes it by removing its `open` attribute. Escape is caught first (its
  colocated hook listens before anything else on the page): with a menu
  open, Escape only closes the menu, and doesn't also stop playback or
  clear the selection.
  """

  use DrawMusicWeb, :html

  @doc """
  The menu. The `:summary` slot is the button that opens it, its attributes
  (id, class, title, aria-*) passed on to the `<summary>`; the inner block
  is the menu's content (its `dropdown-content` element).
  """
  attr :id, :string, required: true
  attr :class, :any, default: nil, doc: "classes for the `<details>`"

  slot :summary, required: true do
    attr :id, :string
    attr :class, :any
    attr :title, :string
    attr :"aria-label", :string
    attr :"aria-pressed", :string
    attr :"aria-disabled", :string
  end

  slot :inner_block, required: true
  @spec dropdown(map()) :: Phoenix.LiveView.Rendered.t()
  def dropdown(assigns) do
    ~H"""
    <details
      id={@id}
      class={["dropdown", @class]}
      phx-hook=".Dropdown"
      phx-click-away={JS.remove_attribute("open")}
    >
      <summary :for={summary <- @summary} {summary_attributes(summary)}>
        {render_slot(summary)}
      </summary>
      {render_slot(@inner_block)}
    </details>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Dropdown">
      // Escape closes an open menu and goes no further.
      export default {
        mounted() {
          this.onKey = (e) => {
            if (e.key !== "Escape" || !this.el.open) return
            this.el.open = false
            e.preventDefault()
            e.stopImmediatePropagation()
          }
          window.addEventListener("keydown", this.onKey, true)
        },
        destroyed() {
          window.removeEventListener("keydown", this.onKey, true)
        }
      }
    </script>
    """
  end

  @doc "Closes the dropdown `id` (then runs the rest of `js`): for its items."
  @spec close(JS.t(), String.t()) :: JS.t()
  def close(js \\ %JS{}, id), do: JS.remove_attribute(js, "open", to: "##{id}")

  defp summary_attributes(summary), do: Map.drop(summary, [:__slot__, :inner_block])
end
