defmodule Mix.Tasks.Samples.FetchTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Samples.Fetch

  test "an unknown name exits with suggestions" do
    error = assert_raise Mix.Error, fn -> Fetch.run(["flut"]) end
    assert error.message =~ "flute"
  end
end
