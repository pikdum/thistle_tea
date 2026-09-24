defmodule ThistleTea.Game.Entity.Logic.AI.BT.TotemTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Totem, as: TotemBT
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.WorldRef

  describe "lifetime/3" do
    test "expires independently of combat and rejects absent, distant, and other-copy owners" do
      ward = ward(1)
      observation = owner(1)
      assert {:failure, ^ward, _} = TotemBT.lifetime(ward, %Blackboard{}, context(observation, 999))

      for {observed, now} <- [
            {observation, 1000},
            {nil, 999},
            {%{observation | distance: 120.1}, 999},
            {%{observation | position: {WorldRef.instance(529, 2), 0.0, 0.0, 0.0}}, 999}
          ] do
        assert {:success, stopped, _} = TotemBT.lifetime(ward, %Blackboard{}, context(observed, now))
        assert [%Effects.DespawnSelf{duration_ms: 0}] = stopped.internal.events
      end
    end

    test "player death removes wards but creature death preserves them until expiry" do
      assert {:success, _stopped, _} =
               TotemBT.lifetime(ward(1), %Blackboard{}, context(%{owner(1) | metadata: %{alive?: false}}, 999))

      guid = Guid.runtime(:mob, 1234)
      ward = ward(guid)

      assert {:failure, ^ward, _} =
               TotemBT.lifetime(ward, %Blackboard{}, context(%{owner(guid) | metadata: %{alive?: false}}, 999))
    end
  end

  describe "tick/3" do
    test "preserves final due pulses but rejects pulses after expiry or owner loss" do
      ward = ward(1)

      holder = %Holder{
        spell: %Spell{id: 8443},
        caster_guid: 2,
        auras: [%Aura{type: :periodic_trigger_spell, amplitude_ms: 500, next_tick_at: 500, trigger_spell_id: 8349}]
      }

      ward = %{
        ward
        | unit: %{ward.unit | auras: [holder]},
          internal: %{ward.internal | totem: %{ward.internal.totem | passive_spell_started?: true}}
      }

      {_, active} = BehaviorRunner.tick(TotemBT.tree(), ward, context(owner(1), 999))
      assert Enum.count(active.internal.events, &is_struct(&1, Effects.TriggerSpell)) == 1

      for now <- [1000, 1500] do
        {:success, stopped} = BehaviorRunner.tick(TotemBT.tree(), ward, context(owner(1), now))
        assert Enum.count(stopped.internal.events, &is_struct(&1, Effects.TriggerSpell)) == 1
        assert Enum.any?(stopped.internal.events, &is_struct(&1, Effects.DespawnSelf))
      end

      holder = %{holder | auras: [%{hd(holder.auras) | next_tick_at: 1500}]}
      ward = %{ward | unit: %{ward.unit | auras: [holder]}}

      for {observation, now} <- [{owner(1), 1000}, {owner(1), 1500}, {nil, 2000}] do
        {:success, stopped} = BehaviorRunner.tick(TotemBT.tree(), ward, context(observation, now))
        assert [%Effects.DespawnSelf{}] = stopped.internal.events
        assert stopped.unit.auras == [holder]
      end
    end
  end

  defp ward(owner) do
    %Mob{
      object: %Object{guid: 2},
      unit: %Unit{health: 1500, max_health: 1500},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.instance(529, 1),
        totem: %Totem{owner_guid: owner, expires_at: 1000},
        in_combat: true
      }
    }
  end

  defp owner(guid),
    do: %Observation{
      guid: guid,
      position: {WorldRef.instance(529, 1), 0.0, 0.0, 0.0},
      distance: 2.0,
      metadata: %{alive?: true}
    }

  defp context(observation, now) do
    entities = if observation, do: %{observation.guid => observation}, else: %{}
    Context.new(now, perception: Perception.new(now, nil, entities, %{}))
  end
end
