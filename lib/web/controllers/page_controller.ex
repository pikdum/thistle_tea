defmodule ThistleTeaWeb.PageController do
  use ThistleTeaWeb, :controller

  @username_regex ~r/^[A-Za-z0-9_]{2,16}$/

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    game_server = Application.fetch_env!(:thistle_tea, :game_server)
    render(conn, :home, layout: false, game_server: game_server)
  end

  def register(conn, params) do
    username = params |> Map.get("username", "") |> to_string() |> String.trim()
    password = params |> Map.get("password", "") |> to_string()

    cond do
      not Regex.match?(@username_regex, username) ->
        conn
        |> put_flash(:error, "username must be 2–16 characters, letters/numbers/underscore only")
        |> redirect(to: ~p"/")

      String.length(password) < 1 or String.length(password) > 16 ->
        conn
        |> put_flash(:error, "password must be 1–16 characters")
        |> redirect(to: ~p"/")

      true ->
        case ThistleTea.Account.register(username, password) do
          {:ok, _account} ->
            conn
            |> put_flash(:info, "account created — log in with the credentials you just entered")
            |> redirect(to: ~p"/")

          {:error, message} ->
            conn
            |> put_flash(:error, String.downcase(message))
            |> redirect(to: ~p"/")
        end
    end
  end
end
