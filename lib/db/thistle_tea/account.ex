defmodule ThistleTea.Account do
  use Memento.Table,
    attributes: [:id, :username, :password_hash, :password_salt, :password_verifier],
    index: [:username],
    type: :ordered_set,
    autoincrement: true

  import Binary, only: [reverse: 1]

  @g <<7>>
  @n <<137, 75, 100, 94, 137, 225, 83, 91, 189, 173, 91, 139, 41, 6, 80, 83, 8, 1, 177, 142, 191, 191, 94, 143, 171, 60,
       130, 135, 42, 62, 155, 183>>

  def register(username, password) do
    username = String.upcase(username)

    case user_exists?(username) do
      true -> {:error, "User already exists"}
      false -> create_account(username, password)
    end
  end

  def get_user(username) do
    username = String.upcase(username)

    case Memento.transaction!(fn ->
           Memento.Query.select(ThistleTea.Account, {:==, :username, username})
         end) do
      [] -> {:error, "User not found"}
      [account] -> {:ok, account}
    end
  end

  defp user_exists?(username) do
    case get_user(username) do
      {:error, _} -> false
      _ -> true
    end
  end

  defp create_account(username, password) do
    salt = :crypto.strong_rand_bytes(32)
    hash = :crypto.hash(:sha, String.upcase(username) <> ":" <> String.upcase(password))
    x = reverse(:crypto.hash(:sha, salt <> hash))
    verifier = :crypto.mod_pow(@g, x, @n)

    account =
      Memento.transaction!(fn ->
        Memento.Query.write(%ThistleTea.Account{
          username: username,
          # TODO: use something better than sha256 here
          password_hash: :crypto.hash(:sha256, password),
          password_salt: salt,
          password_verifier: verifier
        })
      end)

    {:ok, account}
  end
end
