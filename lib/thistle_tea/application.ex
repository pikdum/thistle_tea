defmodule ThistleTea.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # {ThousandIsland, port: 8085, handler_module: ThistleTea.GameProxy},
      # {ThousandIsland, port: 3724, handler_module: ThistleTea.AuthProxy, handler_options: %{}}
      {ThousandIsland, port: 3724, handler_module: ThistleTea.Auth, handler_options: %{}}
      # Starts a worker by calling: ThistleTea.Worker.start_link(arg)
      # {ThistleTea.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ThistleTea.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
