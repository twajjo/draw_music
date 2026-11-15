defmodule DrawMusicWeb.ReadingAids do
  @moduledoc """
  The reading aids the editor draws on the score for a user who wants them
  (preferences on `DrawMusic.Accounts.User`), as `DrawMusicWeb.ReadingAid`
  labels added to each system's items.

  The editor alone calls this, on its own copy of the engraving. Exports
  draw the engraving as it is, so sheet music never carries the aids.

  - `letter_staves`: at the start of each line of music, the letters of each
    staff's lines (treble E G B D F, bass G B D F A) and spaces (treble F A C
    E, bass A C E G) in two small columns left of the staves, and middle C on
    its ledger line below the treble and above the bass.
  - `show_note_names`: each selected note's name beside its head: its letter and
    accidental (G♯, B♭), with ♮ only where the score writes a natural. Every
    note is named, but drawn only while it is selected (`ReadingAid` `shown:
    :when_selected`), so selecting needs no new aids. With
    `note_names_in_edit_only` off, every note's name is drawn at all times.
  """

  alias DrawMusic.Accounts.User
  alias DrawMusic.Engraving.{Engraved, Glyph, Staff, System}
  alias DrawMusicWeb.ReadingAid

  @letters ~w(C D E F G A B)
  @signs %{-2 => "𝄫", -1 => "♭", 1 => "♯", 2 => "𝄪"}
  # Middle C's step.
  @middle_c 28
  # The columns' x, left of the brace (at 0), within the editor's margin:
  # the lines' letters, the spaces' further right, middle C between them.
  @line_x -2.3
  @space_x -1.3
  @middle_c_x -1.8
  # A note's name is centred this far right of its head's left edge (staff
  # spaces), clear of the head.
  @name_x 1.9

  @doc "The engraving with the user's reading aids added to its systems."
  @spec add(Engraved.t(), User.t()) :: Engraved.t()
  def add(%Engraved{systems: systems} = engraved, %User{} = user) do
    %{engraved | systems: Enum.map(systems, &with_aids(&1, user))}
  end

  @doc """
  The names of the notes among a system's `items`, beside their heads, in the
  system's coordinates, each drawn when `shown` says.
  """
  @spec note_names([struct()], :always | :when_selected) :: [ReadingAid.t()]
  def note_names(items, shown) do
    for %Glyph{role: :notehead, staff: staff} = head <- items, staff != nil do
      step = Staff.top_step(staff) - round((head.y - Staff.top(staff)) * 2)

      %ReadingAid{
        x: head.x + @name_x,
        y: head.y,
        text: name(step, head),
        kind: :note,
        note_id: head.id,
        shown: shown
      }
    end
  end

  @doc "The staff letters for one line of music, in its system's coordinates."
  @spec staff_letters() :: [ReadingAid.t()]
  def staff_letters do
    Enum.flat_map([:treble, :bass], &letters_of/1) ++ middle_c()
  end

  defp aids(%System{items: items}, user) do
    letters(user.letter_staves) ++
      names(user.show_note_names, user.note_names_in_edit_only, items)
  end

  # Steps an even distance from the top line are lines; the others, spaces.
  defp column(0), do: {:line, @line_x}
  defp column(1), do: {:space, @space_x}

  defp letter(step), do: Enum.at(@letters, Integer.mod(step, 7))

  defp letters(true = _letter_staves?), do: staff_letters()
  defp letters(false), do: []

  # A staff's five lines and four spaces: from its top line down, a line on
  # every other step.
  defp letters_of(staff) do
    top = Staff.top_step(staff)

    for step <- top..(top - 2 * Staff.height())//-1 do
      {kind, x} = column(rem(top - step, 2))
      %ReadingAid{x: x, y: Staff.y(staff, step), text: letter(step), kind: kind}
    end
  end

  # Middle C as each staff writes it: a ledger line below the treble, one
  # above the bass.
  defp middle_c do
    for staff <- [:treble, :bass] do
      %ReadingAid{x: @middle_c_x, y: Staff.y(staff, @middle_c), text: "C", kind: :middle_c}
    end
  end

  # Sharp or flat as it sounds; a natural only where the score writes one.
  defp name(step, %Glyph{alter: 0, sign: 0}), do: letter(step) <> "♮"
  defp name(step, %Glyph{alter: alter}) when alter in [nil, 0], do: letter(step)
  defp name(step, %Glyph{alter: alter}), do: letter(step) <> Map.fetch!(@signs, alter)

  defp names(true = _show?, true = _edit_only?, items), do: note_names(items, :when_selected)
  defp names(true, false, items), do: note_names(items, :always)
  defp names(false, _edit_only?, _items), do: []

  defp with_aids(%System{items: items} = system, user) do
    %{system | items: items ++ aids(system, user)}
  end
end
