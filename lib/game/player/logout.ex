defmodule ThistleTea.Game.Player.Logout do
  @moduledoc "Owner-local logout countdowns and cancellation, with stale timer rejection."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Logout, as: LogoutLogic
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.System.Trade

  @logout_delay_ms 20_000

  def request(%State{character: %Character{}} = state) do
    state = state |> clear() |> Looting.release()

    case LogoutLogic.admission(state.character) do
      {:ok, speed} ->
        Trade.cancel(state.guid)
        Network.send_packet(%Message.SmsgLogoutResponse{result: 0, speed: Message.SmsgLogoutResponse.speed(speed)})
        character = if speed == :delayed, do: LogoutLogic.start(state.character, Time.now()), else: state.character
        token = make_ref()
        delay = if speed == :instant, do: 0, else: @logout_delay_ms
        ref = Process.send_after(self(), {:logout_complete, token}, delay)
        %{state | character: character, logout_timer: %{token: token, ref: ref}}

      {:error, reason} ->
        Network.send_packet(%Message.SmsgLogoutResponse{result: Message.SmsgLogoutResponse.result(reason), speed: 0})
        state
    end
  end

  def request(state), do: state

  def cancel(%State{} = state) do
    state = clear(state)
    Network.send_packet(%Message.SmsgLogoutCancelAck{})
    state
  end

  def cancel(state), do: state

  def clear(%State{} = state) do
    case state.logout_timer do
      %{ref: ref} -> Process.cancel_timer(ref)
      _ -> :ok
    end

    character = if state.character, do: LogoutLogic.cancel(state.character, Time.now())
    %{state | character: character, logout_timer: nil}
  end
end
