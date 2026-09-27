defmodule ThistleTea.Game.Spell.CastTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastResolution
  alias ThistleTea.Game.Spell.CastResolution.Costs
  alias ThistleTea.Game.Spell.CastResolution.Followups
  alias ThistleTea.Game.Spell.Target

  describe "new/4" do
    test "indefinite channels retain their duration and schedule future ticks" do
      spell = %Spell{cast_time_ms: 2_000, duration_ms: -1, attributes: MapSet.new([:channeled])}
      cast = Cast.new(spell, Target.none(), -10_000)
      assert Cast.channeled?(cast)
      assert cast.channel_ms == -1
      assert cast.ends_at == nil
      assert Cast.launch_at(cast) == -8_000
      cast = Cast.apply_speed_multiplier(cast, 0.5)
      assert Cast.launch_at(cast) == -9_000
      assert cast.ends_at == nil
      {cast, delay} = Cast.push_back_cast(cast, -9_500)
      assert delay == 500
      assert Cast.launch_at(cast) == -8_500
      assert cast.ends_at == nil
      assert Cast.next_channel_delay(cast, -8_500) == 1_000
      cast = Cast.advance_channel_tick(cast, 60_000)
      assert Cast.next_channel_delay(cast, 60_000) in 1..1_000
    end
  end

  describe "transition/2" do
    test "accepts only state-machine edges" do
      cast = Cast.new(%Spell{id: 1}, Target.none(), 1_000)
      resolution = resolution()

      cast =
        cast
        |> Cast.transition(:launch)
        |> Cast.put_resolution(resolution)
        |> Cast.transition(:impact)
        |> Cast.transition(:channel_tick)
        |> Cast.transition(:finish)

      assert cast.phase == :finish
      assert cast.resolution == resolution
    end

    test "rejects skipped phases" do
      cast = Cast.new(%Spell{id: 1}, Target.none(), 1_000)

      assert_raise ArgumentError, ~r/preparing.*impact/, fn ->
        Cast.transition(cast, :impact)
      end
    end
  end

  defp resolution do
    %CastResolution{
      hits: [],
      misses: [],
      costs: %Costs{
        power: %CastResolution.PowerCost{power_type: 0, amount: 0},
        channel_power: %CastResolution.PowerCost{power_type: 0, amount: 0},
        reagents: [],
        cast_item_guid: nil,
        modifier_holder_ids: []
      },
      impacts: [],
      followups: %Followups{
        packet_hits: [],
        selected_unit_guid: nil,
        object_guid: nil,
        item_guid: nil,
        ground_position: nil,
        area_position: nil
      }
    }
  end
end
