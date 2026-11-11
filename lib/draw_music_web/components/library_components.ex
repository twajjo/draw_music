defmodule DrawMusicWeb.LibraryComponents do
  @moduledoc """
  Pieces of the composition library: a composition's row with its keys and
  versions, and links to versions.
  """

  use DrawMusicWeb, :verified_routes
  use Phoenix.Component

  import DrawMusicWeb.CoreComponents, only: [icon: 1, input: 1]

  alias DrawMusic.Library.Key
  alias DrawMusic.Music.Context
  alias DrawMusic.Samples

  @doc "Every key as select options, grouped into major and minor, valued by slug."
  @spec key_options() :: [{String.t(), [{String.t(), String.t()}]}]
  def key_options do
    for {label, mode} <- [{"Major", :major}, {"Minor", :minor}] do
      {label, for(sf <- -7..7, do: {Key.name(sf, mode), Key.slug(sf, mode)})}
    end
  end

  @doc """
  A composition's details: its name, subtitle, credits and notes. They
  belong to the composition, so every key and version shares them.
  """
  attr :form, Phoenix.HTML.Form, required: true

  @spec composition_fields(map()) :: Phoenix.LiveView.Rendered.t()
  def composition_fields(assigns) do
    ~H"""
    <.input field={@form[:name]} label="Name" required phx-debounce="300" />
    <.input field={@form[:subtitle]} label="Subtitle" />
    <div class="grid gap-x-4 sm:grid-cols-2">
      <.input field={@form[:composer]} label="Composer" />
      <.input field={@form[:arranger]} label="Arranger" />
      <.input field={@form[:lyricist]} label="Lyricist" />
      <.input field={@form[:copyright]} label="Copyright" />
    </div>
    <.input field={@form[:notes]} type="textarea" label="Notes" rows="3" />
    """
  end

  @doc "The button that opens a composition's details (see `DrawMusicWeb.DetailsDialog`)."
  attr :id, :string, required: true
  attr :rest, :global

  @spec details_button(map()) :: Phoenix.LiveView.Rendered.t()
  def details_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="edit_details"
      class="btn btn-ghost btn-sm gap-1 transition-colors"
      title="Edit the name, credits and notes"
      {@rest}
    >
      <.icon name="hero-pencil-square" class="size-4" /> Details
    </button>
    """
  end

  @doc """
  A score's settings inputs: key, time signature, tempo and pickup. The
  caller's form lays them out; see `DrawMusicWeb.EditorSettings`.
  """
  attr :form, Phoenix.HTML.Form, required: true

  @spec score_settings_fields(map()) :: Phoenix.LiveView.Rendered.t()
  def score_settings_fields(assigns) do
    assigns =
      assign(assigns,
        key_options: key_options(),
        time_denominators: Context.time_denominators(),
        max_time_num: Context.max_time_num(),
        tempo_range: Context.tempo_range(),
        instrument_options: instrument_options()
      )

    ~H"""
    <.input field={@form[:key]} type="select" label="Key" options={@key_options} />
    <div class="flex items-end gap-2">
      <.input
        field={@form[:time_num]}
        type="number"
        label="Time"
        min="1"
        max={@max_time_num}
        class="input w-20"
      />
      <span class="pb-3 text-lg">/</span>
      <.input field={@form[:time_den]} type="select" options={@time_denominators} />
    </div>
    <.input
      field={@form[:time_symbol]}
      type="select"
      label="Written as"
      options={[{"Numbers", "none"}, {"Common time (4/4)", "common"}, {"Cut time (2/2)", "cut"}]}
    />
    <.input
      field={@form[:tempo_bpm]}
      type="number"
      label="Starting tempo (BPM)"
      min={@tempo_range.first}
      max={@tempo_range.last}
    />
    <.input field={@form[:tempo_text]} label="Tempo marking" placeholder="Allegro" />
    <.input field={@form[:pickup_beats]} type="number" label="Pickup beats" min="0" />
    <.input
      id="settings-instrument"
      field={@form[:instrument]}
      type="select"
      label="Instrument"
      options={@instrument_options}
    />
    """
  end

  @doc """
  The instrument picker's options: GM instruments grouped by family, with
  the ones not downloaded to this server marked "(not installed)" and drawn
  in the warning colour (yellow).
  """
  @spec instrument_options() :: [{String.t(), [{String.t(), 0..127} | keyword()]}]
  def instrument_options do
    installed = Samples.installed()

    for family <- Samples.families() do
      options =
        for %{family: ^family} = instrument <- Samples.instruments() do
          instrument_option(instrument, MapSet.member?(installed, instrument.program))
        end

      {family, options}
    end
  end

  defp instrument_option(instrument, true = _installed?),
    do: {instrument.name, instrument.program}

  defp instrument_option(instrument, false) do
    [
      key: "#{instrument.name} (not installed)",
      value: instrument.program,
      class: "text-warning"
    ]
  end

  @doc "Path of a version's score view."
  @spec version_path(Ecto.UUID.t(), Key.t(), pos_integer()) :: String.t()
  def version_path(composition_id, %Key{} = key, number) do
    ~p"/compositions/#{composition_id}/#{Key.slug(key)}/v/#{number}"
  end

  @doc """
  A composition with its credits and versions: each version an Edit button
  (its key and number) beside a Delete button that asks first. Deleting a
  composition's only version deletes the composition.
  """
  attr :id, :string, required: true
  attr :composition, :map, required: true

  @spec composition_row(map()) :: Phoenix.LiveView.Rendered.t()
  def composition_row(assigns) do
    assigns = assign(assigns, :only?, version_count(assigns.composition) == 1)

    ~H"""
    <article
      id={@id}
      class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm transition-shadow hover:shadow-md"
    >
      <header class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex flex-wrap items-baseline gap-x-3">
          <h2 class="text-lg font-semibold">{@composition.name}</h2>
          <p :if={credits(@composition) != ""} class="text-sm opacity-70">
            {credits(@composition)}
          </p>
        </div>
        <.details_button id={"details-#{@composition.id}"} phx-value-id={@composition.id} />
      </header>
      <ul class="mt-3 flex flex-wrap gap-2">
        <%= for key <- @composition.keys, version <- key.versions do %>
          <li class="join">
            <.link
              id={"version-#{version.id}"}
              navigate={version_path(@composition.id, key, version.number)}
              class="btn btn-sm join-item gap-1.5"
              title={"Edit #{Key.name(key)}, version #{version.number}"}
            >
              <.icon name="hero-pencil-square" class="size-4" />
              {Key.name(key)} · v{version.number}
              <span :if={version.label} class="opacity-60">· {version.label}</span>
            </.link>
            <button
              id={"delete-version-#{version.id}"}
              type="button"
              phx-click="delete_version"
              phx-value-id={version.id}
              data-confirm={delete_question(@composition, key, version, @only?)}
              class="btn btn-sm btn-square join-item text-error transition-colors hover:bg-error hover:text-error-content"
              title={"Delete #{Key.name(key)}, version #{version.number}"}
              aria-label={"Delete #{Key.name(key)}, version #{version.number}"}
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </li>
        <% end %>
      </ul>
    </article>
    """
  end

  defp version_count(composition) do
    Enum.reduce(composition.keys, 0, &(length(&1.versions) + &2))
  end

  defp delete_question(composition, _key, _version, true = _only?) do
    "Delete #{composition.name}? This is its only version, so the composition goes too."
  end

  defp delete_question(composition, key, version, false) do
    "Delete #{composition.name}, #{Key.name(key)} version #{version.number}? This can't be undone."
  end

  @doc "A menu of all versions of a composition, in every key, marking the current one."
  attr :id, :string, required: true
  attr :composition, :map, required: true
  attr :version, :map, required: true, doc: "the version being shown, with its key"

  @spec version_picker(map()) :: Phoenix.LiveView.Rendered.t()
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
  @spec credits(DrawMusic.Library.Composition.t()) :: String.t()
  def credits(composition) do
    [composition.composer, composition.arranger && "arr. #{composition.arranger}"]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end
end
