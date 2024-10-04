defmodule ThistleTea.DBC do
  use Ecto.Repo, otp_app: :thistle_tea, adapter: Ecto.Adapters.SQLite3
end
