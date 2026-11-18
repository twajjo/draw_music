defmodule DrawMusicWeb.EditorLive.Edit do
  @moduledoc """
  How `DrawMusicWeb.EditorLive` takes a change, shared by its own handlers
  and its hook modules (`DrawMusicWeb.EditorLive.ViewChanges`,
  `DrawMusicWeb.EditorLive.Versions`): an edit through the session, and
  the score laid out and drawn again after it (`:drawing`; LiveView
  reserves the `layout` assign).
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [clear_flash: 1, put_flash: 3]

  alias DrawMusic.Music.{Score, Session}
  alias DrawMusicWeb.Editor.{Drawing, Messages}
  alias Phoenix.LiveView.Socket

  @doc """
  Runs `fun.(score, ctx)` through the session, then lays the score out
  again: `{:ok, socket, extra}` (what the edit returned beside the score).
  On error the score stays as it was and the reason is shown:
  `{:error, socket}`.
  """
  @spec apply_edit(Socket.t(), function()) :: {:ok, Socket.t(), term()} | {:error, Socket.t()}
  def apply_edit(%Socket{} = socket, fun) do
    case Session.edit(socket.assigns.session, fun) do
      {:ok, session, extra} ->
        {:ok,
         socket
         |> clear_flash()
         |> assign(:session, session)
         |> assign_layout(), extra}

      {:error, reason} ->
        {:error, put_flash(socket, :error, Messages.refused(reason))}
    end
  end

  @doc "Lays the session's score out again, in the view's layout."
  @spec assign_layout(Socket.t()) :: Socket.t()
  def assign_layout(%Socket{} = socket) do
    lay_out(socket, socket.assigns.session.score, false)
  end

  @doc "Draws the pieces again in the same layout, for new reading aids."
  @spec assign_pieces(Socket.t()) :: Socket.t()
  def assign_pieces(%Socket{} = socket) do
    %{drawing: drawing, current_scope: %{user: user}, view: view} = socket.assigns
    assign(socket, :drawing, Drawing.repaint(drawing, user, view))
  end

  @doc """
  Until the score is engraved (the static page, and the join), an empty
  bar stands in, with a note that the score is loading.
  """
  @spec assign_placeholder(Socket.t()) :: Socket.t()
  def assign_placeholder(%Socket{} = socket), do: lay_out(socket, Score.new(), true)

  @doc "`apply_edit/2` when the outcome doesn't matter beyond the socket."
  @spec edit(Socket.t(), function()) :: Socket.t()
  def edit(%Socket{} = socket, fun) do
    case apply_edit(socket, fun) do
      {:ok, socket, _extra} -> socket
      {:error, socket} -> socket
    end
  end

  @doc """
  For edits that give the ids of the notes they made or moved (a drop, a
  chord from the selection): those notes end up selected.
  """
  @spec edit_and_select(Socket.t(), function()) :: Socket.t()
  def edit_and_select(%Socket{} = socket, fun) do
    case apply_edit(socket, fun) do
      {:ok, socket, ids} ->
        assign(socket, :session, Session.select(socket.assigns.session, ids, false))

      {:error, socket} ->
        socket
    end
  end

  defp lay_out(socket, score, loading?) do
    %{session: %{ctx: ctx}, extras: extras, current_scope: %{user: user}, view: view} =
      socket.assigns

    drawing =
      Drawing.draw(score, ctx,
        user: user,
        view: view,
        marking: extras.tempo_text,
        loading?: loading?
      )

    assign(socket, :drawing, drawing)
  end
end
