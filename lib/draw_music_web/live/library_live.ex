defmodule DrawMusicWeb.LibraryLive do
  @moduledoc """
  The signed-in user's compositions, with their keys and versions, and
  importing a .mid file into them (with a choice to make when its name is
  taken).
  """

  use DrawMusicWeb, :live_view

  import DrawMusicWeb.LibraryComponents

  alias DrawMusic.{Library, MidiCodec}
  alias DrawMusic.Library.{Import, Key}

  @max_midi_bytes 1_000_000
  @resolutions %{"replace" => :replace, "new_version" => :new_version}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Compositions
        <:actions>
          <.button id="import-open" phx-click="open_import">
            <.icon name="hero-arrow-up-tray" class="size-4" /> Import .mid
          </.button>
          <.button id="new-composition" variant="primary" navigate={~p"/compositions/new"}>
            <.icon name="hero-plus" class="size-4" /> New composition
          </.button>
        </:actions>
      </.header>

      <div id="compositions" phx-update="stream" class="space-y-3">
        <p id="compositions-empty" class="hidden only:block py-10 text-center opacity-60">
          No compositions yet. Start one with “New composition”, or import a .mid file.
        </p>
        <.composition_row
          :for={{id, composition} <- @streams.compositions}
          id={id}
          composition={composition}
        />
      </div>

      <.import_dialog
        :if={@import_step}
        step={@import_step}
        upload={@uploads.midi}
        form={@import_form}
        error={@import_error}
        name={@import_form && @import_form[:name].value}
        key_name={@import_key_name}
      />
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    compositions = Library.list_compositions(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Compositions")
     |> reset_import()
     |> allow_upload(:midi,
       accept: ~w(.mid .midi),
       max_entries: 1,
       max_file_size: @max_midi_bytes
     )
     |> stream(:compositions, compositions)}
  end

  @impl true
  def handle_event("open_import", _params, socket) do
    {:noreply, assign(socket, import_step: :upload, import_error: nil)}
  end

  def handle_event("validate_import", _params, socket) do
    {:noreply, assign(socket, :import_error, nil)}
  end

  def handle_event("read_import", _params, socket) do
    results =
      consume_uploaded_entries(socket, :midi, fn %{path: path}, entry ->
        {:ok, MidiCodec.import(path, entry.client_name)}
      end)

    case results do
      [{:ok, %Import{} = import}] ->
        {:noreply,
         socket
         |> assign(pending_import: import, import_step: :name, import_error: nil)
         |> assign(:import_key_name, key_name(import))
         |> assign(:import_form, name_form(import.name))}

      [{:error, reason}] ->
        {:noreply, assign(socket, :import_error, message(reason))}

      [] ->
        {:noreply, socket}
    end
  end

  def handle_event("import_named", %{"import" => %{"name" => name}}, socket) do
    case String.trim(name) do
      "" ->
        {:noreply, assign(socket, :import_form, name_form(name, name: {"can't be blank", []}))}

      name ->
        {:noreply, import_as(socket, name, :new)}
    end
  end

  def handle_event("resolve_import", %{"how" => how}, socket) do
    case Map.fetch(@resolutions, how) do
      {:ok, resolution} ->
        {:noreply, import_as(socket, socket.assigns.import_form[:name].value, resolution)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("rename_import", _params, socket) do
    name = socket.assigns.import_form[:name].value

    {:noreply,
     socket
     |> assign(import_step: :name, import_error: nil)
     |> assign(:import_form, name_form(name, name: {"is already in your library", []}))}
  end

  # The browser asked first (data-confirm). The composition's only version
  # takes the composition with it.
  def handle_event("delete_version", %{"id" => id}, socket) when is_binary(id) do
    scope = socket.assigns.current_scope
    version = Library.get_version!(scope, id)
    composition = version.key.composition

    case Library.delete_version(scope, version) do
      {:ok, _version} ->
        {:noreply,
         socket
         |> stream_insert(:compositions, Library.get_composition!(scope, composition.id))
         |> put_flash(:info, "Version deleted.")}

      {:error, :last_version} ->
        {:ok, _composition} = Library.delete_composition(scope, composition)

        {:noreply,
         socket
         |> stream_delete(:compositions, composition)
         |> put_flash(:info, "#{composition.name} deleted.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "That version couldn't be deleted.")}
    end
  end

  def handle_event("close_import", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.midi.entries, socket, fn entry, socket ->
        cancel_upload(socket, :midi, entry.ref)
      end)

    {:noreply, reset_import(socket)}
  end

  defp import_as(socket, name, resolution) do
    %{current_scope: scope, pending_import: import} = socket.assigns

    case Library.import_score(scope, name, import, resolution) do
      {:ok, version} ->
        push_navigate(socket,
          to: version_path(version.key.composition_id, version.key, version.number)
        )

      {:error, :name_taken} ->
        assign(socket, import_step: :collision, import_form: name_form(name), import_error: nil)

      {:error, %Ecto.Changeset{errors: errors}} ->
        case Keyword.take(errors, [:name]) do
          [] ->
            assign(socket, :import_error, message(:unsaved))

          name_errors ->
            assign(socket, import_step: :name, import_form: name_form(name, name_errors))
        end

      {:error, reason} ->
        assign(socket, :import_error, message(reason))
    end
  end

  defp name_form(name, errors \\ []), do: to_form(%{"name" => name}, as: :import, errors: errors)

  defp reset_import(socket) do
    assign(socket,
      import_step: nil,
      pending_import: nil,
      import_key_name: nil,
      import_form: nil,
      import_error: nil
    )
  end

  # The import's key attrs come from the file, so they are cast like a form's.
  defp key_name(%Import{key: attrs}) do
    case Ecto.Changeset.apply_action(Key.changeset(%Key{}, attrs), :validate) do
      {:ok, key} -> Key.name(key)
      {:error, _changeset} -> "its key"
    end
  end

  defp message(:invalid_midi), do: "That file isn't a MIDI file this app can read."

  defp message(:smpte_unsupported),
    do: "That file times its notes in SMPTE frames, which isn't supported."

  defp message(:unrepresentable),
    do: "Some of the file's note lengths can't be written in the score."

  defp message(:before_start), do: "The file has notes before its first bar."
  defp message(:not_found), do: "That composition is no longer in your library."
  defp message(:unsaved), do: "The file's music couldn't be saved."
end
