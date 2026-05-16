defmodule ThistleTea.Game.Entity.Logic.CombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Event

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

  describe "Event queue" do
    test "enqueues and drains pending events from internal state" do
      mob = %Mob{object: %Object{guid: 1}, unit: %Unit{}, internal: %Internal{}}
      event = Combat.attack_start(1, 2)

      mob = Event.enqueue(mob, event)
      assert {mob, [^event]} = Event.drain(mob)
      assert mob.internal.events == []
    end
  end
end
