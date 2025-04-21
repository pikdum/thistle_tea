defmodule ThistleTea.Test.Support.Util do
  def random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode64()
    |> binary_part(0, length)
  end
end
