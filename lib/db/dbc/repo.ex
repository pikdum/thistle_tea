defmodule ThistleTea.DBC do
  @moduledoc false
  use Ecto.Repo, otp_app: :thistle_tea, adapter: Ecto.Adapters.SQLite3
end
