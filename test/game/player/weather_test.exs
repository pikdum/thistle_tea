defmodule ThistleTea.Game.Player.WeatherTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message.SmsgWeather
  alias ThistleTea.Game.Player.Weather, as: PlayerWeather
  alias ThistleTea.Game.Weather
  alias ThistleTea.Game.World.System.Weather, as: WeatherSystem
  alias ThistleTea.Game.WorldRef

  setup [:player]

  describe "refresh/2" do
    test "clears weather on zone exit and rejects old subscriptions after reentry", %{state: state, world: world} do
      WeatherSystem.set(world, 12, :rain, 0.95)
      raining = PlayerWeather.refresh(state, 12)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgWeather{weather_type: 1, sound_id: 8535}}}
      assert PlayerWeather.refresh(raining, 12) == raining
      refute_received {:"$gen_cast", {:send_packet, %SmsgWeather{}}}

      clear = PlayerWeather.refresh(raining, 40)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgWeather{weather_type: 0, grade: +0.0}}}
      returned = PlayerWeather.refresh(clear, 12)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgWeather{weather_type: 1}}}
      PlayerWeather.update(returned, raining.weather_token, %Weather{type: :snow, grade: 0.9})
      refute_received {:"$gen_cast", {:send_packet, %SmsgWeather{}}}
      PlayerWeather.update(returned, returned.weather_token, %Weather{type: :snow, grade: 0.9})
      assert_receive {:"$gen_cast", {:send_packet, %SmsgWeather{weather_type: 2, sound_id: 8538}}}
    end

    test "rejects updates during world transfer and unsubscribes on departure", %{state: state} do
      state = PlayerWeather.refresh(state, 12)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgWeather{}}}
      transferring = %{state | pending_worldport?: true}
      assert PlayerWeather.update(transferring, state.weather_token, %Weather{}) == transferring
      refute_received {:"$gen_cast", {:send_packet, _}}
      moved = put_in(state.character.internal.world, WorldRef.open(1))
      assert PlayerWeather.update(moved, state.weather_token, %Weather{}) == moved
      refute_received {:"$gen_cast", {:send_packet, _}}
      assert PlayerWeather.leave(state).weather_key == nil
      refute Map.has_key?(WeatherSystem.snapshot().members, state.guid)
    end
  end

  defp player(_context) do
    guid = System.unique_integer([:positive]) + 90_000_000
    world = WorldRef.instance(529, guid)
    character = %Character{object: %Object{guid: guid}, internal: %Internal{world: world}}
    on_exit(fn -> WeatherSystem.clear_world(world) end)
    %{state: %State{ready: true, guid: guid, character: character}, world: world}
  end
end
