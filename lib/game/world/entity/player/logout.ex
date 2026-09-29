defmodule ThistleTea.Game.World.Entity.Player.Logout do
  @moduledoc "Owner-local logout countdowns and cancellation, with stale timer rejection."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Player.Logout, as: LogoutCore
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Looting
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.System.Trade

  @logout_delay_ms 20_000

  def request(%State{character: %Character{}} = state) do
    state = state |> clear() |> Looting.release()

    case LogoutCore.admission(state.character) do
      {:ok, speed} ->
        Trade.cancel(state.guid)
        Outbound.send_packet(%Message.SmsgLogoutResponse{result: 0, speed: Message.SmsgLogoutResponse.speed(speed)})
        character = if speed == :delayed, do: LogoutCore.start(state.character, Time.now()), else: state.character
        token = make_ref()
        delay = if speed == :instant, do: 0, else: @logout_delay_ms
        ref = Process.send_after(self(), {:logout_complete, token}, delay)
        %{state | character: character, logout_timer: %{token: token, ref: ref}}

      {:error, reason} ->
        Outbound.send_packet(%Message.SmsgLogoutResponse{result: Message.SmsgLogoutResponse.result(reason), speed: 0})
        state
    end
  end

  def request(state), do: state

  def cancel(%State{} = state) do
    state = clear(state)
    Outbound.send_packet(%Message.SmsgLogoutCancelAck{})
    state
  end

  def cancel(state), do: state

  def clear(%State{} = state) do
    case state.logout_timer do
      %{ref: ref} -> Process.cancel_timer(ref)
      _ -> :ok
    end

    character = if state.character, do: LogoutCore.cancel(state.character, Time.now())
    %{state | character: character, logout_timer: nil}
  end
end
