defmodule ThistleTeaWeb.PageController do
  use ThistleTeaWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    game_server = Application.fetch_env!(:thistle_tea, :game_server)
    render(conn, :home, layout: false, game_server: game_server)
  end
end
