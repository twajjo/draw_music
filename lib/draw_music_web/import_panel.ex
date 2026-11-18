defmodule DrawMusicWeb.ImportPanel do
  @moduledoc """
  The top bar's **Import**: the .mid import dialog (`DrawMusicWeb.ImportDialog`)
  opened over whatever page you're on, so closing it leaves you where you
  were, unsaved work in the editor included.

  The dialog is part of the address, `?panel=import`, as the editor's
  Preferences panel is: the Import link patches the current page to it, and
  closing patches back. Each signed-in page gets this through `on_mount/4`
  (in the router's live sessions), which attaches two lifecycle hooks:

    * `handle_params`: assigns `:import_panel`, this struct, for the page to
      pass to `Layouts.app` (which draws the link and the dialog);
    * `handle_info`: the dialog's messages. Closed, the page is patched back.
      Imported, the new piece opens.

  In the editor, unsaved changes are asked about before the dialog opens
  (the link is marked `data-leaves-page` for its guard), since an import
  ends by leaving it.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias DrawMusicWeb.{ImportDialog, LibraryComponents}

  @enforce_keys [:open?, :open_path, :close_path]
  defstruct [:open?, :open_path, :close_path]

  @type t :: %__MODULE__{open?: boolean(), open_path: String.t(), close_path: String.t()}

  @doc "The panel at `uri`: whether it's open, and the address with and without it."
  @spec for_uri(String.t()) :: t()
  def for_uri(uri) do
    %URI{path: path, query: query} = URI.parse(uri)
    others = query |> Kernel.||("") |> URI.decode_query() |> Map.delete("panel")
    open? = URI.decode_query(query || "")["panel"] == "import"

    %__MODULE__{
      open?: open?,
      open_path: with_query(path, Map.put(others, "panel", "import")),
      close_path: with_query(path, others)
    }
  end

  @doc "Attaches the hooks; until the first `handle_params`, there's no panel."
  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:import_panel, nil)
     |> attach_hook(:import_panel, :handle_params, &params/3)
     |> attach_hook(:import_panel, :handle_info, &info/2)}
  end

  defp info({ImportDialog, :closed}, socket) do
    {:halt, push_patch(socket, to: socket.assigns.import_panel.close_path)}
  end

  # Unsaved changes were asked about before the dialog opened.
  defp info({ImportDialog, {:imported, version}}, socket) do
    to = LibraryComponents.version_path(version.key.composition_id, version.key, version.number)
    {:halt, push_navigate(socket, to: to)}
  end

  defp info(_message, socket), do: {:cont, socket}

  # A page without its own `handle_params/3` would be called anyway: the
  # hook stops there for it.
  defp params(_params, uri, socket) do
    socket = assign(socket, :import_panel, for_uri(uri))

    case function_exported?(socket.view, :handle_params, 3) do
      true -> {:cont, socket}
      false -> {:halt, socket}
    end
  end

  defp with_query(path, query) when map_size(query) == 0, do: path
  defp with_query(path, query), do: path <> "?" <> URI.encode_query(query)
end
