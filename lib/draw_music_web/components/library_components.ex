defmodule DrawMusicWeb.LibraryComponents do
  @moduledoc """
  Pieces of the composition library: a composition's row with its keys and
  versions, and links to versions.
  """

  use DrawMusicWeb, :verified_routes
  use Phoenix.Component

  import DrawMusicWeb.CoreComponents, only: [icon: 1]

  alias DrawMusic.Library.Key

  @doc "Every key as select options, grouped into major and minor, valued by slug."
  def key_options do
    for {label, mode} <- [{"Major", :major}, {"Minor", :minor}] do
      {label, for(sf <- -7..7, do: {Key.name(sf, mode), Key.slug(sf, mode)})}
    end
  end

  @doc "Path of a version's score view."
  def version_path(composition_id, %Key{} = key, number),
    do: ~p"/compositions/#{composition_id}/#{Key.slug(key)}/v/#{number}"

  @doc "A composition with its credits, keys and versions."
  attr :id, :string, required: true
  attr :composition, :map, required: true

  def composition_row(assigns) do
    ~H"""
    <article
      id={@id}
      class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm transition-shadow hover:shadow-md"
    >
      <header class="flex flex-wrap items-baseline justify-between gap-2">
        <h2 class="text-lg font-semibold">{@composition.name}</h2>
        <p :if={credits(@composition) != ""} class="text-sm opacity-70">{credits(@composition)}</p>
      </header>
      <ul class="mt-3 space-y-2">
        <li :for={key <- @composition.keys} class="flex flex-wrap items-center gap-2">
          <span class="badge badge-outline">{Key.name(key)}</span>
          <.link
            :for={version <- key.versions}
            id={"version-#{version.id}"}
            navigate={version_path(@composition.id, key, version.number)}
            class="btn btn-xs btn-ghost"
            title={version.label}
          >
            v{version.number}<span :if={version.label} class="opacity-60">· {version.label}</span>
          </.link>
        </li>
      </ul>
    </article>
    """
  end

  @doc "A menu of all versions of a composition, in every key, marking the current one."
  attr :id, :string, required: true
  attr :composition, :map, required: true
  attr :version, :map, required: true, doc: "the version being shown, with its key"

  def version_picker(assigns) do
    ~H"""
    <details id={@id} class="dropdown dropdown-end">
      <summary class="btn btn-sm">
        {Key.name(@version.key)} · v{@version.number}
        <.icon name="hero-chevron-down" class="size-4" />
      </summary>
      <ul class="dropdown-content z-20 mt-1 w-64 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg">
        <li :for={key <- @composition.keys} class="py-1">
          <p class="px-2 text-xs font-semibold uppercase opacity-60">{Key.name(key)}</p>
          <.link
            :for={version <- key.versions}
            id={"#{@id}-#{version.id}"}
            navigate={version_path(@composition.id, key, version.number)}
            aria-current={if(version.id == @version.id, do: "page")}
            class={[
              "block rounded px-2 py-1 text-sm transition-colors hover:bg-base-200",
              version.id == @version.id && "font-semibold text-primary"
            ]}
          >
            v{version.number}<span :if={version.label} class="opacity-60"> · {version.label}</span>
          </.link>
        </li>
      </ul>
    </details>
    """
  end

  @doc "The composition's credits on one line."
  def credits(composition) do
    [composition.composer, composition.arranger && "arr. #{composition.arranger}"]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end
end
