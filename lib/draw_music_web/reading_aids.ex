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
  """

  alias DrawMusic.Accounts.User
  alias DrawMusic.Engraving.{Engraved, Staff, System}
  alias DrawMusicWeb.ReadingAid

  @letters ~w(C D E F G A B)
  # Middle C's step.
  @middle_c 28
  # The columns' x, left of the brace (at 0), within the editor's margin:
  # the lines' letters, the spaces' further right, middle C between them.
  @line_x -2.3
  @space_x -1.3
  @middle_c_x -1.8

  @doc "The engraving with the user's reading aids added to its systems."
  @spec add(Engraved.t(), User.t()) :: Engraved.t()
  def add(%Engraved{systems: systems} = engraved, %User{letter_staves: true}) do
    %{engraved | systems: Enum.map(systems, &with_staff_letters/1)}
  end

  def add(%Engraved{} = engraved, _user), do: engraved

  @doc "The staff letters for one line of music, in its system's coordinates."
  @spec staff_letters() :: [ReadingAid.t()]
  def staff_letters do
    Enum.flat_map([:treble, :bass], &letters_of/1) ++ middle_c()
  end

  # A staff's five lines and four spaces: from its top line down, a line on
  # every other step.
  defp letters_of(staff) do
    top = Staff.top_step(staff)

    for step <- top..(top - 2 * Staff.height())//-1 do
      {kind, x} = column(rem(top - step, 2))
      %ReadingAid{x: x, y: Staff.y(staff, step), text: letter(step), kind: kind}
    end
  end

  # Steps an even distance from the top line are lines; the others, spaces.
  defp column(0), do: {:line, @line_x}
  defp column(1), do: {:space, @space_x}

  # Middle C as each staff writes it: a ledger line below the treble, one
  # above the bass.
  defp middle_c do
    for staff <- [:treble, :bass] do
      %ReadingAid{x: @middle_c_x, y: Staff.y(staff, @middle_c), text: "C", kind: :middle_c}
    end
  end

  defp letter(step), do: Enum.at(@letters, Integer.mod(step, 7))

  defp with_staff_letters(%System{items: items} = system) do
    %{system | items: items ++ staff_letters()}
  end
end
