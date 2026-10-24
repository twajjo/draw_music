defmodule DrawMusic.Samples.ManifestEntry do
  @moduledoc "One downloaded set in the samples manifest: its size and when it was fetched."

  @enforce_keys [:bytes, :fetched_at]
  defstruct [:bytes, :fetched_at]

  @type t :: %__MODULE__{bytes: non_neg_integer(), fetched_at: DateTime.t()}
end
