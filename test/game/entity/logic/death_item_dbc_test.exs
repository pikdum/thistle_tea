defmodule ThistleTea.Game.Entity.Logic.DeathItemDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:target]

  describe "receive/4" do
    test "lethal Shadowburn ranks capture their shard aura before damage", %{target: target, context: context} do
      for id <- [17_877, 18_867, 18_868, 18_869, 18_870, 18_871] do
        {dead, events} = SpellEffect.receive(target, context, SpellLoader.load(id), 1_000)
        assert dead.unit.health == 0
        assert dead.unit.auras == []
        assert [%Effects.DeathItemReward{target_guid: 7, item_id: 6265, count: 1}] = rewards(dead, events)
      end
    end

    test "resisted and expired Shadowburn do not produce shards", %{target: target, context: context} do
      spell = SpellLoader.load(17_877)
      {alive, events} = SpellEffect.receive(target, %{context | hit_outcome: :resist}, spell, 1_000)
      assert alive.unit.health == target.unit.health
      assert rewards(alive, events) == []
      assert alive.unit.auras == []

      target = %{target | unit: %{target.unit | health: 10_000, max_health: 10_000}}
      {alive, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert rewards(alive, events) == []
      assert length(alive.unit.auras) == 1
      {expired, events} = Aura.expire_due(alive, 1_000 + spell.duration_ms)
      assert expired.unit.auras == []
      {dead, _absorbed} = Core.take_damage_with_absorb(expired, 10_000, 10_000, source: 7)
      assert rewards(dead, events) == []
    end
  end

  describe "load/1" do
    test "loads positive death items without turning the zero-count Infernal Fire into a reward" do
      for {id, item, count} <- [
            {1120, 6265, 1},
            {8288, 6265, 1},
            {8289, 6265, 1},
            {11_675, 6265, 1},
            {7914, 6435, 1},
            {16_627, 12_648, 1},
            {16_628, 12_649, 1},
            {24_826, 19_960, 0}
          ] do
        effect = SpellLoader.load(id).effects |> Enum.find(&(&1.aura == :channel_death_item))
        assert effect.item_type == item
        assert Effect.roll(effect, 0) == count
      end
    end
  end

  defp rewards(entity, events),
    do: Enum.filter(entity.internal.events ++ events, &is_struct(&1, Effects.DeathItemReward))

  defp target(_context) do
    mob = %Mob{}

    target = %{
      mob
      | object: %{mob.object | guid: Guid.from_low_guid(:mob, 1, 1)},
        unit: %{mob.unit | level: 60, health: 1, max_health: 100, shadow_resistance: 0, auras: []},
        internal: %{mob.internal | loot: %Loot{tapped_by: %Tap{player: 7}}}
    }

    context = %CastContext{
      caster_guid: 7,
      caster_level: 60,
      caster_type: :player,
      target_hostile?: true,
      target_role: :other,
      hit_outcome: :hit,
      spell_crit_chance: 0
    }

    %{target: target, context: context}
  end
end
