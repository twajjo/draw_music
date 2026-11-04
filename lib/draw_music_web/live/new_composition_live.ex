defmodule DrawMusicWeb.NewCompositionLive do
  @moduledoc """
  Starts a composition: its name and credits, key, meter, tempo and pickup.
  Version 1 is an empty score of four measures. The form's errors come from
  the `Composition` and `Version` changesets.
  """

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.LibraryComponents,
    only: [version_path: 3, score_settings_fields: 1, composition_fields: 1]

  alias DrawMusic.Library
  alias DrawMusic.Library.{Composition, Key, Version}
  alias DrawMusic.Music.{Context, Score}
  alias DrawMusicWeb.EditorSettings

  @measures 4
  @credit_fields ~w(subtitle composer arranger lyricist copyright notes)

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
          <.composition_fields form={@form} />
        </fieldset>

        <fieldset class="grid gap-x-4 sm:grid-cols-3">
          <.score_settings_fields form={@form} />
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
     |> assign(:form, to_form(defaults(), as: :composition))}
  end

  @impl true
  def handle_event("validate", %{"composition" => params}, socket) do
    {:noreply, assign(socket, :form, form(socket, params, :validate))}
  end

  def handle_event("save", %{"composition" => params}, socket) do
    case Key.from_slug(params["key"] || "") do
      {:ok, key} -> {:noreply, create(socket, params, key)}
      :error -> {:noreply, assign(socket, :form, form(socket, params, :insert))}
    end
  end

  defp create(socket, params, {sf, mode}) do
    scope = socket.assigns.current_scope
    key_attrs = %{sf: sf, mode: mode}

    case Library.create_composition(
           scope,
           composition_attrs(params),
           key_attrs,
           version_attrs(params)
         ) do
      {:ok, version} ->
        socket
        |> put_flash(:info, "Composition created.")
        |> push_navigate(
          to: version_path(version.key.composition.id, version.key, version.number)
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket, :form, form(socket, params, :insert, changeset.errors))
    end
  end

  defp form(socket, params, action, extra_errors \\ []) do
    errors = Enum.uniq(validation_errors(socket.assigns.current_scope, params) ++ extra_errors)
    to_form(params, as: :composition, errors: EditorSettings.form_errors(errors), action: action)
  end

  defp defaults do
    %Context{}
    |> EditorSettings.params(nil, %Version{}.instrument)
    |> Map.put("name", "")
  end

  defp validation_errors(scope, params) do
    composition = Composition.changeset(%Composition{}, composition_attrs(params), scope)
    version = Version.changeset(%Version{number: 1}, version_attrs(params))
    composition.errors ++ version.errors ++ key_errors(params["key"])
  end

  defp key_errors(slug) do
    case Key.from_slug(slug || "") do
      {:ok, _key} -> []
      :error -> [key: {"is invalid", []}]
    end
  end

  defp composition_attrs(params), do: Map.take(params, ["name" | @credit_fields])

  defp version_attrs(params) do
    params
    |> EditorSettings.form_attrs()
    |> Map.put("score", Score.new(@measures))
  end
end
