defmodule DrawMusicWeb.ContextMenuTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Note, Rest}
  alias DrawMusicWeb.ContextMenu

  @note %Note{id: Ecto.UUID.generate()}
  @rest %Rest{id: Ecto.UUID.generate()}
  @params %{"x" => 10, "y" => 20}

  test "an unselected note or rest gets a menu of its own" do
    assert %ContextMenu{kind: :note, ids: [id], x: 10, y: 20} =
             ContextMenu.new(MapSet.new(), @note, @params)

    assert id == @note.id
    assert %ContextMenu{kind: :rest} = ContextMenu.new(MapSet.new(), @rest, @params)
  end

  test "a selected event opens the menu for the whole selection" do
    selection = MapSet.new([@note.id, @rest.id])
    menu = ContextMenu.new(selection, @note, @params)

    assert menu.kind == :selection
    assert menu.id == @note.id
    assert Enum.sort(menu.ids) == Enum.sort([@note.id, @rest.id])
  end

  test "the clicked staff step is kept; off the staves there is none" do
    over_staff = Map.merge(@params, %{"staff" => "treble", "step" => 3})

    assert ContextMenu.new(MapSet.new(), @rest, over_staff).step == 3
    assert ContextMenu.new(MapSet.new(), @rest, @params).step == nil
  end
end
