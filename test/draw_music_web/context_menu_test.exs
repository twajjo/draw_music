defmodule DrawMusicWeb.ContextMenuTest do
  use ExUnit.Case, async: true

  alias DrawMusic.Music.{Note, Rest}
  alias DrawMusicWeb.ContextMenu

  @note %Note{id: Ecto.UUID.generate()}
  @rest %Rest{id: Ecto.UUID.generate()}
  @params %{"x" => 10, "y" => 20}

  describe "subject/2: the selection decides" do
    test "two or more selected: the selection, wherever the click lands" do
      selection = MapSet.new([@note.id, @rest.id])

      assert {:selection, ids} = ContextMenu.subject(selection, nil)
      assert Enum.sort(ids) == Enum.sort([@note.id, @rest.id])
      assert {:selection, _ids} = ContextMenu.subject(selection, Ecto.UUID.generate())
    end

    test "one selected: that one, even when another is right-clicked" do
      selection = MapSet.new([@note.id])

      assert ContextMenu.subject(selection, nil) == {:event, @note.id}
      assert ContextMenu.subject(selection, @rest.id) == {:event, @note.id}
    end

    test "nothing selected: what was right-clicked, or nothing" do
      assert ContextMenu.subject(MapSet.new(), @rest.id) == {:event, @rest.id}
      assert ContextMenu.subject(MapSet.new(), nil) == :none
    end
  end

  test "a note or rest gets a menu of its own" do
    assert %ContextMenu{kind: :note, id: id, ids: [id], x: 10, y: 20} =
             ContextMenu.for_event(@note, @params)

    assert id == @note.id
    assert %ContextMenu{kind: :rest} = ContextMenu.for_event(@rest, @params)
  end

  test "a selection's menu acts on all of it" do
    menu = ContextMenu.for_selection([@note.id, @rest.id], @params)

    assert %ContextMenu{kind: :selection, id: nil, x: 10, y: 20} = menu
    assert menu.ids == [@note.id, @rest.id]
  end

  test "the staff step under the pointer is kept; off the staves there is none" do
    over_staff = Map.merge(@params, %{"staff" => "treble", "step" => 3})

    assert ContextMenu.for_event(@rest, over_staff).step == 3
    assert ContextMenu.for_event(@rest, @params).step == nil
  end
end
