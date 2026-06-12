defmodule ThistleTea.Auth.SRP do
  @moduledoc """
  Shared SRP6 parameters and verifier derivation used by both account
  creation and the logon handshake.
  """
  import Binary, only: [reverse: 1]

  @g <<7>>
  @n <<137, 75, 100, 94, 137, 225, 83, 91, 189, 173, 91, 139, 41, 6, 80, 83, 8, 1, 177, 142, 191, 191, 94, 143, 171, 60,
       130, 135, 42, 62, 155, 183>>

  def g, do: @g
  def n, do: @n

  def verifier(username, password, salt) do
    hash = :crypto.hash(:sha, String.upcase(username) <> ":" <> String.upcase(password))
    x = reverse(:crypto.hash(:sha, salt <> hash))
    :crypto.mod_pow(@g, x, @n)
  end
end
