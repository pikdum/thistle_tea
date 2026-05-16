defmodule ThistleTea.Game.Entity.Logic.CombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "attack_start/2" do
    test "returns an attack_start event" do
      assert %Event{type: :attack_start, source_guid: 1, target_guid: 2} = Combat.attack_start(1, 2)
    end
  end

  describe "attacker_state_update/4" do
    test "returns an attacker_state_update event with attack details" do
      event = Combat.attacker_state_update(1, 2, 12, %{spell_id: 99})

      assert %Event{
               type: :attacker_state_update,
               source_guid: 1,
               target_guid: 2,
               damage: 12,
               attack: %{spell_id: 99}
             } = event
    end
  end

  describe "receive_attack/3" do
    test "applies damage and returns attacker update events" do
      mob = mob(2, 100)

      {mob, events} = Combat.receive_attack(mob, %{caster: 1, damage: 12}, 1_000)

      assert mob.unit.health == 88
      assert mob.internal.broadcast_update? == true

      assert [
               %Event{
                 type: :attacker_state_update,
                 source_guid: 1,
                 target_guid: 2,
                 damage: 12
               }
             ] = events
    end

    test "includes hit reaction events while target survives" do
      spell = damage_shield_spell()
      {mob, _events} = Aura.apply_spell(mob(2, 100), 2, 10, spell, 1_000)

      {_mob, events} = Combat.receive_attack(mob, %{caster: 1, damage: 12}, 1_000)

      assert [
               %Event{type: :attacker_state_update},
               %Event{
                 type: :trigger_spell,
                 source_guid: 2,
                 source_level: 10,
                 target_guid: 1,
                 spell_id: 6136
               }
             ] = events
    end

    test "does not include hit reaction events when target dies" do
      spell = damage_shield_spell()
      {mob, _events} = Aura.apply_spell(mob(2, 10), 2, 10, spell, 1_000)

      {_mob, events} = Combat.receive_attack(mob, %{caster: 1, damage: 12}, 1_000)

      assert [%Event{type: :attacker_state_update}] = events
    end
  end

  describe "Event queue" do
    test "enqueues and drains pending events from internal state" do
      mob = %Mob{object: %Object{guid: 1}, unit: %Unit{}, internal: %Internal{}}
      event = Combat.attack_start(1, 2)

      mob = Event.enqueue(mob, event)
      assert {mob, [^event]} = Event.drain(mob)
      assert mob.internal.events == []
    end
  end

  defp mob(guid, health) do
    %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: health, auras: []},
      internal: %Internal{}
    }
  end

  defp damage_shield_spell do
    %Spell{
      id: 168,
      effects: [
        %Effect{
          type: :apply_aura,
          aura: :damage_shield,
          trigger_spell_id: 6136
        }
      ]
    }
  end
end
