# A save that a component reports moves to the new version a moment later;
# under a full, parallel run that can take longer than the 100 ms default.
ExUnit.start(assert_receive_timeout: 1_000)
Ecto.Adapters.SQL.Sandbox.mode(DrawMusic.Repo, :manual)
