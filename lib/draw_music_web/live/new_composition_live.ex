defmodule DrawMusicWeb.NewCompositionLive do
  @moduledoc """
  Starts a composition: its name and credits, key, meter, tempo and pickup.
  Version 1 is an empty score of four measures. The form's errors come from
  the `Composition` and `Version` changesets.
  """

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.LibraryComponents, only: [version_path: 3, key_options: 0]

  alias DrawMusic.Library
  alias DrawMusic.Library.{Composition, Key, Version}
  alias DrawMusic.Music.{Context, Score}

  @measures 4
  @credit_fields ~w(subtitle composer arranger lyricist copyright)
  @time_denominators ~w(1 2 4 8 16 32 64)
  @defaults %{
    "name" => "",
    "key" => "c-major",
    "time_num" => "4",
    "time_den" => "4",
    "time_symbol" => "none",
    "tempo_bpm" => "100",
    "tempo_text" => "",
    "pickup_beats" => "0"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        New composition
        <:subtitle>You can change all of this later.</:subtitle>
      </.header>

      <.form
        for={@form}
        id="composition-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <fieldset class="space-y-2">
          <.input field={@form[:name]} label="Name" required phx-debounce="300" />
          <.input field={@form[:subtitle]} label="Subtitle" />
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@form[:composer]} label="Composer" />
            <.input field={@form[:arranger]} label="Arranger" />
            <.input field={@form[:lyricist]} label="Lyricist" />
            <.input field={@form[:copyright]} label="Copyright" />
          </div>
        </fieldset>

        <fieldset class="grid gap-x-4 sm:grid-cols-3">
          <.input field={@form[:key]} type="select" label="Key" options={key_options()} />
          <div class="flex items-end gap-2">
            <.input
              field={@form[:time_num]}
              type="number"
              label="Time"
              min="1"
              max="32"
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
          <.input field={@form[:tempo_bpm]} type="number" label="Tempo (BPM)" min="20" max="400" />
          <.input field={@form[:tempo_text]} label="Tempo marking" placeholder="Allegro" />
          <.input field={@form[:pickup_beats]} type="number" label="Pickup beats" min="0" />
        </fieldset>

        <div class="flex gap-2">
          <.button variant="primary" phx-disable-with="Creating...">Create</.button>
          <.button navigate={~p"/compositions"}>Cancel</.button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New composition")
     |> assign(:time_denominators, @time_denominators)
     |> assign(:form, to_form(@defaults, as: :composition))}
  end

  @impl true
  def handle_event("validate", %{"composition" => params}, socket) do
    {:noreply, assign(socket, :form, form(socket, params, :validate))}
  end

  def handle_event("save", %{"composition" => params}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, {sf, mode}} <- Key.from_slug(params["key"] || ""),
         {:ok, version} <-
           Library.create_composition(
             scope,
             composition_attrs(params),
             %{sf: sf, mode: mode},
             version_attrs(params)
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Composition created.")
       |> push_navigate(to: version_path(version.key.composition.id, version.key, version.number))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, form(socket, params, :insert, changeset.errors))}

      :error ->
        {:noreply, assign(socket, :form, form(socket, params, :insert))}
    end
  end

  defp form(socket, params, action, extra_errors \\ []) do
    errors = Enum.uniq(validation_errors(socket.assigns.current_scope, params) ++ extra_errors)
    to_form(params, as: :composition, errors: rename_pickup(errors), action: action)
  end

  defp validation_errors(scope, params) do
    composition = Composition.changeset(%Composition{}, composition_attrs(params), scope)
    version = Version.changeset(%Version{number: 1}, version_attrs(params))
    key = if Key.from_slug(params["key"] || "") == :error, do: [key: {"is invalid", []}], else: []
    composition.errors ++ version.errors ++ key
  end

  # The form asks for pickup beats; the version stores ticks.
  defp rename_pickup(errors) do
    Enum.map(errors, fn
      {:pickup_ticks, error} -> {:pickup_beats, error}
      error -> error
    end)
  end

  defp composition_attrs(params), do: Map.take(params, ["name" | @credit_fields])

  defp version_attrs(params) do
    %{
      time_num: params["time_num"],
      time_den: params["time_den"],
      time_symbol: params["time_symbol"],
      tempo_bpm: params["tempo_bpm"],
      tempo_text: params["tempo_text"],
      pickup_ticks: pickup_ticks(params),
      score: Score.new(@measures)
    }
  end

  defp pickup_ticks(params) do
    with {beats, ""} <- Integer.parse(params["pickup_beats"] || ""),
         den when den in @time_denominators <- params["time_den"] do
      beats * Context.beat_ticks(%Context{time_den: String.to_integer(den)})
    else
      _ -> 0
    end
  end
end
