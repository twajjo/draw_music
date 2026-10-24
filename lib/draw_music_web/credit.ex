defmodule DrawMusicWeb.Credit do
  @moduledoc """
  A third-party work DrawMusic uses, as listed on the Credits page: who
  made it, its license (with a link when there is one), where it comes
  from, and what we use it for.
  """

  @enforce_keys [:work, :holder, :license, :license_url, :source_url, :use]
  defstruct [:work, :holder, :license, :license_url, :source_url, :use]

  @type t :: %__MODULE__{
          work: String.t(),
          holder: String.t(),
          license: String.t(),
          license_url: String.t() | nil,
          source_url: String.t(),
          use: String.t()
        }
end
