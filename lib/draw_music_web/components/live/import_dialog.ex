defmodule DrawMusicWeb.ImportDialog do
  @moduledoc """
  Imports a .mid file into the library, one step at a time: `:upload` picks
  the file, `:name` confirms the name read from it, and `:collision` asks what
  to do when that name is already in the library (replace that key's
  versions, add a new version, or choose another name).

  A standalone LiveComponent: it owns the upload, the steps, their errors and
  the import itself, and works in any LiveView.

  ## Inputs
    * `:id` — the component's id (required by LiveView).
    * `:scope` — the signed-in user's `DrawMusic.Accounts.Scope` (required).

  ## Messages to the parent
  Sent as `{DrawMusicWeb.ImportDialog, message}`:
    * `{:imported, version}` — the piece is stored; `version` has its key
      loaded. The parent closes the dialog and usually opens the version.
    * `:closed` — Cancel, Esc or a click outside; nothing was imported.
  """

  use DrawMusicWeb, :live_component

  alias DrawMusic.Accounts.Scope
  alias DrawMusic.{Library, MidiCodec}
  alias DrawMusic.Library.{Import, Key}

  @max_midi_bytes 1_000_000
  @resolutions %{"replace" => :replace, "new_version" => :new_version}

  @type message :: {:imported, DrawMusic.Library.Version.t()} | :closed

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("close", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.midi.entries, socket, fn entry, socket ->
        cancel_upload(socket, :midi, entry.ref)
      end)

    send(self(), {__MODULE__, :closed})
    {:noreply, socket}
  end

  def handle_event("name", %{"import" => %{"name" => name}}, socket) do
    case String.trim(name) do
      "" -> {:noreply, assign(socket, :form, name_form(name, name: {"can't be blank", []}))}
      name -> {:noreply, import_as(socket, name, :new)}
    end
  end

  def handle_event("read", _params, socket) do
    results =
      consume_uploaded_entries(socket, :midi, fn %{path: path}, entry ->
        {:ok, MidiCodec.import(path, entry.client_name)}
      end)

    case results do
      [{:ok, %Import{} = import}] ->
        {:noreply,
         socket
         |> assign(pending: import, step: :name, error: nil)
         |> assign(key_name: key_name(import), form: name_form(import.name))}

      [{:error, reason}] ->
        {:noreply, assign(socket, :error, message(reason))}

      [] ->
        {:noreply, socket}
    end
  end

  def handle_event("rename", _params, socket) do
    name = socket.assigns.form[:name].value

    {:noreply,
     socket
     |> assign(step: :name, error: nil)
     |> assign(:form, name_form(name, name: {"is already in your library", []}))}
  end

  def handle_event("resolve", %{"how" => how}, socket) do
    case Map.fetch(@resolutions, how) do
      {:ok, resolution} ->
        {:noreply, import_as(socket, socket.assigns.form[:name].value, resolution)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("validate", _params, socket), do: {:noreply, assign(socket, :error, nil)}

  @impl true
  @spec mount(Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(socket) do
    {:ok,
     socket
     |> assign(step: :upload, pending: nil, key_name: nil, form: nil, error: nil)
     |> allow_upload(:midi,
       accept: ~w(.mid .midi),
       max_entries: 1,
       max_file_size: @max_midi_bytes
     )}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id="import-dialog" class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4">
      <div
        role="dialog"
        aria-label="Import a MIDI file"
        class="w-full max-w-md rounded-box border border-base-300 bg-base-100 p-6 shadow-2xl"
        phx-click-away="close"
        phx-window-keydown="close"
        phx-key="Escape"
        phx-target={@myself}
      >
        <.import_step
          step={@step}
          upload={@uploads.midi}
          form={@form}
          error={@error}
          key_name={@key_name}
          target={@myself}
        />
      </div>
    </div>
    """
  end

  @impl true
  @spec update(map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def update(%{scope: %Scope{}} = assigns, socket) do
    {:ok, assign(socket, Map.take(assigns, [:id, :scope]))}
  end

  def update(_assigns, _socket), do: raise(ArgumentError, "ImportDialog needs a :scope")

  # One way out of a name collision.
  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :how, :string, default: nil, doc: "the resolution, for `resolve`"
  attr :target, :any, required: true
  slot :inner_block, required: true

  defp choice(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click={@event}
      phx-value-how={@how}
      phx-target={@target}
      class="btn btn-block justify-start"
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp import_as(socket, name, resolution) do
    %{scope: scope, pending: import} = socket.assigns

    case Library.import_score(scope, name, import, resolution) do
      {:ok, version} ->
        send(self(), {__MODULE__, {:imported, version}})
        socket

      {:error, :name_taken} ->
        assign(socket, step: :collision, form: name_form(name), error: nil)

      {:error, %Ecto.Changeset{errors: errors}} ->
        case Keyword.take(errors, [:name]) do
          [] -> assign(socket, :error, message(:unsaved))
          name_errors -> assign(socket, step: :name, form: name_form(name, name_errors))
        end

      {:error, reason} ->
        assign(socket, :error, message(reason))
    end
  end

  attr :step, :atom, required: true, values: [:upload, :name, :collision]
  attr :upload, Phoenix.LiveView.UploadConfig, required: true
  attr :form, Phoenix.HTML.Form, default: nil, doc: "the name form (`:name` and `:collision`)"
  attr :error, :string, default: nil
  attr :key_name, :string, default: nil, doc: "the imported piece's key, e.g. \"G major\""
  attr :target, :any, required: true

  defp import_step(%{step: :upload} = assigns) do
    ~H"""
    <h2 class="text-lg font-semibold">Import a MIDI file</h2>
    <p class="mt-1 text-sm opacity-70">A .mid file, up to 1 MB.</p>
    <.form
      for={%{}}
      id="import-form"
      phx-change="validate"
      phx-submit="read"
      phx-target={@target}
      class="mt-4 space-y-3"
    >
      <.live_file_input upload={@upload} class="file-input w-full" />
      <p :for={entry <- @upload.entries} class="text-sm">
        {entry.client_name}
        <span :for={err <- upload_errors(@upload, entry)} class="text-error">
          · {upload_error(err)}
        </span>
      </p>
      <p :for={err <- upload_errors(@upload)} class="text-sm text-error">{upload_error(err)}</p>
      <p :if={@error} id="import-error" class="text-sm text-error">{@error}</p>
      <div class="flex justify-end gap-2 pt-2">
        <button type="button" phx-click="close" phx-target={@target} class="btn btn-ghost">
          Cancel
        </button>
        <button
          type="submit"
          class="btn btn-primary"
          disabled={@upload.entries == []}
          phx-disable-with="Reading..."
        >
          Next
        </button>
      </div>
    </.form>
    """
  end

  defp import_step(%{step: :name} = assigns) do
    ~H"""
    <h2 class="text-lg font-semibold">Name the piece</h2>
    <.form
      for={@form}
      id="import-name-form"
      phx-submit="name"
      phx-target={@target}
      class="mt-4 space-y-2"
    >
      <.input field={@form[:name]} label="Name" required autofocus />
      <p :if={@error} id="import-error" class="text-sm text-error">{@error}</p>
      <div class="flex justify-end gap-2 pt-2">
        <button type="button" phx-click="close" phx-target={@target} class="btn btn-ghost">
          Cancel
        </button>
        <button type="submit" class="btn btn-primary" phx-disable-with="Importing...">
          Import
        </button>
      </div>
    </.form>
    """
  end

  defp import_step(%{step: :collision} = assigns) do
    ~H"""
    <div id="import-collision">
      <h2 class="text-lg font-semibold">“{@form[:name].value}” is already in your library</h2>
      <p class="mt-1 text-sm opacity-70">The file is in {@key_name}.</p>
      <ul class="mt-4 space-y-2">
        <li>
          <.choice id="import-replace" event="resolve" how="replace" target={@target}>
            Replace
            <span class="font-normal opacity-70">
              the versions in {@key_name} with this one, as v1; other keys stay
            </span>
          </.choice>
        </li>
        <li>
          <.choice id="import-new-version" event="resolve" how="new_version" target={@target}>
            New version <span class="font-normal opacity-70">in {@key_name}</span>
          </.choice>
        </li>
        <li>
          <.choice id="import-rename" event="rename" target={@target}>
            New composition <span class="font-normal opacity-70">with a different name</span>
          </.choice>
        </li>
      </ul>
      <p :if={@error} id="import-error" class="mt-2 text-sm text-error">{@error}</p>
      <div class="flex justify-end pt-4">
        <button
          id="import-cancel"
          type="button"
          phx-click="close"
          phx-target={@target}
          class="btn btn-ghost"
        >
          Cancel
        </button>
      </div>
    </div>
    """
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

  defp name_form(name, errors \\ []), do: to_form(%{"name" => name}, as: :import, errors: errors)

  defp upload_error(:too_large), do: "larger than 1 MB"
  defp upload_error(:not_accepted), do: "not a .mid file"
  defp upload_error(:too_many_files), do: "pick one file"
  defp upload_error(_other), do: "can't be uploaded"
end
