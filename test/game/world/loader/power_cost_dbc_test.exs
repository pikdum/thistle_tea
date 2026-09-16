defmodule ThistleTea.Game.World.Loader.PowerCostDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "Burst of Knowledge reduces real spell costs until cancellation or expiry" do
      burst = SpellLoader.load(15_646)
      heal = SpellLoader.load(10_396)
      lay_on_hands = SpellLoader.load(633)
      character = character()
      baseline = Resources.power_cost(character, heal)
      assert baseline > 100
      assert [%{aura: :mod_power_cost_school, base_points: -101, misc_value: 126}] = burst.effects

      {active, _events} = Aura.apply_spell(character, 1, 60, burst, 1_000)
      assert Resources.power_cost(active, heal) == baseline - 100
      assert Resources.power_cost(active, lay_on_hands) == 3_000
      assert Resources.spend_power(active, heal, 2_000).unit.power1 == 3_000 - baseline + 100
      assert active.internal.broadcast_update?

      {cancelled, _events} = Aura.cancel_spell(active, burst.id, 2_000)
      assert Resources.power_cost(cancelled, heal) == baseline
      assert cancelled.unit.power_cost_modifier == <<0::size(224)>>

      {expired, _events} = Aura.expire_due(active, 1_000 + burst.duration_ms)
      assert Resources.power_cost(expired, heal) == baseline
      assert expired.unit.power_cost_modifier == <<0::size(224)>>
      refute Aura.has_spell?(expired, burst.id)
    end
  end

  defp character do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 100, max_health: 100, power1: 3_000, max_power1: 3_000, auras: []},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
