defmodule DrawMusic.LibraryTest do
  use DrawMusic.DataCase, async: true

  import DrawMusic.AccountsFixtures, only: [user_scope_fixture: 0]
  import DrawMusic.LibraryFixtures

  alias DrawMusic.Library
  alias DrawMusic.Library.{Key, Version}

  defp numbers_by_key(scope, composition_id) do
    for key <- Library.get_composition!(scope, composition_id).keys do
      {Key.name(key), Enum.map(key.versions, & &1.number)}
    end
  end

  describe "create_composition/4" do
    test "sets the owner from the scope and starts at version 1" do
      scope = user_scope_fixture()

      assert {:ok, %Version{number: 1} = version} =
               Library.create_composition(scope, %{name: "Minuet"}, key_attrs(), version_attrs())

      assert version.key.composition.user_id == scope.user.id
    end

    test "creates nothing when any part is invalid" do
      scope = user_scope_fixture()

      assert {:error, _} =
               Library.create_composition(
                 scope,
                 %{name: "A"},
                 %{sf: 9, mode: :major},
                 version_attrs()
               )

      assert {:error, _} =
               Library.create_composition(
                 scope,
                 %{name: "B"},
                 key_attrs(),
                 version_attrs(%{time_den: 3})
               )

      assert Library.list_compositions(scope) == []
    end

    test "names are unique per user, ignoring case" do
      scope = user_scope_fixture()
      composition_fixture(scope, composition: %{name: "Etude"})

      assert {:error, cs} =
               Library.create_composition(scope, %{name: "ETUDE"}, key_attrs(), version_attrs())

      assert %{name: ["you already have a composition with this name"]} = errors_on(cs)

      assert {:ok, _} =
               Library.create_composition(
                 user_scope_fixture(),
                 %{name: "Etude"},
                 key_attrs(),
                 version_attrs()
               )
    end
  end

  describe "reads are scoped to the user" do
    test "list_compositions/1 returns only the user's compositions, by name" do
      scope = user_scope_fixture()
      composition_fixture(scope, composition: %{name: "b"})
      composition_fixture(scope, composition: %{name: "A"})
      composition_fixture(user_scope_fixture())

      assert Enum.map(Library.list_compositions(scope), & &1.name) == ["A", "b"]
    end

    test "get_composition!/2 and get_version!/2 raise for another user's records" do
      version = version_fixture(user_scope_fixture())
      other = user_scope_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Library.get_composition!(other, version.key.composition_id)
      end

      assert_raise Ecto.NoResultsError, fn -> Library.get_version!(other, version.id) end
    end

    test "get_composition_by_name/2 ignores case and surrounding spaces" do
      scope = user_scope_fixture()
      composition = composition_fixture(scope, composition: %{name: "Clair de Lune"})

      assert Library.get_composition_by_name(scope, "  clair DE lune ").id == composition.id
      assert Library.get_composition_by_name(user_scope_fixture(), "Clair de Lune") == nil
    end
  end

  test "writes refuse another user's records" do
    version = version_fixture(user_scope_fixture())
    composition = version.key.composition
    other = user_scope_fixture()

    for write <- [
          fn -> Library.update_composition(other, composition, %{name: "x"}) end,
          fn -> Library.delete_composition(other, composition) end,
          fn -> Library.save_version(other, version, %{}) end,
          fn -> Library.save_new_version(other, version.key, version_attrs()) end,
          fn -> Library.save_in_key(other, composition, key_attrs(), version_attrs()) end,
          fn -> Library.delete_version(other, version) end,
          fn -> Library.delete_key(other, version.key) end
        ] do
      assert_raise MatchError, write
    end
  end

  describe "version numbering" do
    test "save_new_version/3 takes the key's next number" do
      scope = user_scope_fixture()
      version = version_fixture(scope)

      assert {:ok, %Version{number: 2}} =
               Library.save_new_version(scope, version.key, version_attrs())

      assert {:ok, %Version{number: 3} = v3} =
               Library.save_new_version(scope, version.key, version_attrs())

      assert Library.get_latest_version!(scope, version.key_id).id == v3.id
    end

    test "save_in_key/4 numbers per key and creates a missing key" do
      scope = user_scope_fixture()
      composition = composition_fixture(scope, key: %{sf: 0, mode: :major})
      d_minor = %{sf: -1, mode: :minor}

      assert {:ok, %Version{number: 1}} =
               Library.save_in_key(scope, composition, d_minor, version_attrs())

      assert {:ok, %Version{number: 2}} =
               Library.save_in_key(scope, composition, d_minor, version_attrs())

      assert {:ok, %Version{number: 2}} =
               Library.save_in_key(scope, composition, key_attrs(), version_attrs())

      assert numbers_by_key(scope, composition.id) == [{"C major", [1, 2]}, {"D minor", [1, 2]}]
    end

    test "numbering continues past deleted versions" do
      scope = user_scope_fixture()
      v1 = version_fixture(scope)
      {:ok, v2} = Library.save_new_version(scope, v1.key, version_attrs())
      {:ok, _} = Library.delete_version(scope, v2)
      {:ok, _v2_again} = Library.save_new_version(scope, v1.key, version_attrs())
      {:ok, _v3} = Library.save_new_version(scope, v1.key, version_attrs())

      assert numbers_by_key(scope, v1.key.composition_id) == [{"C major", [1, 2, 3]}]
    end
  end

  describe "deleting versions and keys" do
    setup do
      scope = user_scope_fixture()
      c1 = version_fixture(scope, key: %{sf: 0, mode: :major})
      {:ok, c2} = Library.save_new_version(scope, c1.key, version_attrs())

      {:ok, g1} =
        Library.save_in_key(scope, c1.key.composition, %{sf: 1, mode: :major}, version_attrs())

      %{scope: scope, c1: c1, c2: c2, g1: g1, composition_id: c1.key.composition_id}
    end

    test "deleting a key's only version removes the key", %{scope: scope} = ctx do
      assert {:ok, _} = Library.delete_version(scope, ctx.g1)
      assert numbers_by_key(scope, ctx.composition_id) == [{"C major", [1, 2]}]
    end

    test "the composition's last version cannot be deleted", %{scope: scope} = ctx do
      {:ok, _} = Library.delete_version(scope, ctx.g1)
      {:ok, _} = Library.delete_version(scope, ctx.c2)

      assert {:error, :last_version} = Library.delete_version(scope, ctx.c1)
    end

    test "delete_key/2 removes a key with its versions, but not the last key",
         %{scope: scope} = ctx do
      assert {:ok, _} = Library.delete_key(scope, ctx.c1.key)
      assert numbers_by_key(scope, ctx.composition_id) == [{"G major", [1]}]
      assert {:error, :last_key} = Library.delete_key(scope, ctx.g1.key)
    end
  end

  describe "import_score/4" do
    setup do
      scope = user_scope_fixture()
      c1 = version_fixture(scope, composition: %{name: "Sonatina"}, key: %{sf: 0, mode: :major})
      {:ok, _c2} = Library.save_new_version(scope, c1.key, version_attrs())

      {:ok, _g1} =
        Library.save_in_key(scope, c1.key.composition, %{sf: 1, mode: :major}, version_attrs())

      %{scope: scope, composition_id: c1.key.composition_id}
    end

    test ":new creates a composition under the given name and the file's key", %{scope: scope} do
      import = import_fixture(composition: %{name: "ignored"}, key: %{sf: -3, mode: :minor})

      assert {:ok, %Version{number: 1} = version} =
               Library.import_score(scope, "Fresh", import, :new)

      assert version.key.composition.name == "Fresh"
      assert Key.name(version.key) == "C minor"
    end

    test ":new reports a name collision, ignoring case", %{scope: scope} do
      assert {:error, :name_taken} =
               Library.import_score(scope, "sonatina", import_fixture(), :new)
    end

    test ":replace resets only the imported key's versions", %{scope: scope} = ctx do
      assert {:ok, %Version{number: 1}} =
               Library.import_score(
                 scope,
                 "Sonatina",
                 import_fixture(key: %{sf: 0, mode: :major}),
                 :replace
               )

      assert numbers_by_key(scope, ctx.composition_id) == [{"C major", [1]}, {"G major", [1]}]
    end

    test ":replace into a key the composition lacks adds that key", %{scope: scope} = ctx do
      assert {:ok, %Version{number: 1}} =
               Library.import_score(
                 scope,
                 "Sonatina",
                 import_fixture(key: %{sf: 2, mode: :major}),
                 :replace
               )

      assert numbers_by_key(scope, ctx.composition_id) ==
               [{"C major", [1, 2]}, {"G major", [1]}, {"D major", [1]}]
    end

    test ":new_version adds the next version under the imported key", %{scope: scope} = ctx do
      assert {:ok, %Version{number: 2}} =
               Library.import_score(
                 scope,
                 "Sonatina",
                 import_fixture(key: %{sf: 1, mode: :major}),
                 :new_version
               )

      assert numbers_by_key(scope, ctx.composition_id) == [
               {"C major", [1, 2]},
               {"G major", [1, 2]}
             ]
    end

    test ":replace and :new_version need an existing name", %{scope: scope} do
      assert {:error, :not_found} =
               Library.import_score(scope, "Nope", import_fixture(), :replace)

      assert {:error, :not_found} =
               Library.import_score(scope, "Nope", import_fixture(), :new_version)
    end

    test "never resolves against another user's composition of the same name", ctx do
      other = user_scope_fixture()

      assert {:error, :not_found} =
               Library.import_score(other, "Sonatina", import_fixture(), :replace)

      assert {:ok, version} = Library.import_score(other, "Sonatina", import_fixture(), :new)
      refute version.key.composition_id == ctx.composition_id
    end
  end
end
