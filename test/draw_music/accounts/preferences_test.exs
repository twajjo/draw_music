defmodule DrawMusic.Accounts.PreferencesTest do
  use ExUnit.Case, async: true

  import DrawMusic.DataCase, only: [errors_on: 1]

  alias DrawMusic.Accounts.User
  alias DrawMusicWeb.SettingsComponents

  defp prefs(attrs), do: User.preferences_changeset(%User{}, attrs)

  test "the dark-mode ink is a #rrggbb color, stored lowercase" do
    changeset = prefs(%{score_ink_dark: "#FFCC66"})
    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :score_ink_dark) == "#ffcc66"

    assert %{score_ink_dark: ["must be a color like #ffcc66"]} =
             errors_on(prefs(%{score_ink_dark: "ffcc66"}))

    assert %{score_ink_dark: [_]} = errors_on(prefs(%{score_ink_dark: "#fc6"}))
  end

  test "the dark-mode ink must be readable on black" do
    assert %{score_ink_dark: ["is too dark to read on black"]} =
             errors_on(prefs(%{score_ink_dark: "#333333"}))

    assert %{score_ink_dark: [_]} = errors_on(prefs(%{score_ink_dark: "#0000ff"}))
  end

  test "every preset swatch is accepted" do
    for {_name, color} <- SettingsComponents.ink_presets() do
      assert prefs(%{score_ink_dark: color}).valid?, "#{color} should be readable on black"
    end
  end

  test "the layout is strip or page" do
    assert prefs(%{score_layout: "page"}).valid?
    assert %{score_layout: [_]} = errors_on(prefs(%{score_layout: "scroll"}))
  end
end
