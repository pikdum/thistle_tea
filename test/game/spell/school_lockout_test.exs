defmodule ThistleTea.Game.Spell.SchoolLockoutTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.EventSink.Spells
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Time

  setup [:caster]

  describe "lock_schools/4" do
    test "overlapping locks extend but never shorten a school", %{entity: entity} do
      entity = entity |> Cooldowns.lock_schools(4, 10_000, 1_000) |> Cooldowns.lock_schools(4, 1_000, 2_000)
      assert Cooldowns.school_cooldowns(entity, 2_000) == [{133, 9_000}, {2136, 9_000}]
      entity = Cooldowns.lock_schools(entity, 20, 15_000, 3_000)
      assert Cooldowns.school_cooldowns(entity, 3_000) == [{116, 15_000}, {133, 15_000}, {2136, 15_000}]
      assert Cooldowns.school_cooldowns(entity, 18_000) == []
    end

    test "preserves longer spell and category cooldowns and deferred entries", %{entity: entity} do
      spell = %{
        entity.internal.spellbook[2136]
        | recovery_time_ms: 30_000,
          category: 8,
          category_recovery_time_ms: 20_000
      }

      other = %{entity.internal.spellbook[133] | category: 8}
      deferred = %Spell{id: 99, school: :fire, attributes: MapSet.new([:cooldown_on_event]), recovery_time_ms: 5_000}
      entity = %{entity | internal: %{entity.internal | spellbook: %{133 => other, 2136 => spell, 99 => deferred}}}

      entity =
        entity
        |> Cooldowns.start(spell, 1_000)
        |> Cooldowns.start(deferred, 1_000)
        |> Cooldowns.lock_schools(4, 10_000, 2_000)

      assert Cooldowns.school_cooldowns(entity, 2_000) == []
      assert Cooldowns.ready_at(entity, spell) == 31_000
      assert Cooldowns.pending(entity, 99)
    end
  end

  describe "initial/3" do
    test "restores school timers without changing ordinary cooldown sources", %{entity: entity} do
      spell = %{entity.internal.spellbook[2136] | recovery_time_ms: 5_000}
      entity = entity |> Cooldowns.start(spell, 1_000) |> Cooldowns.lock_schools(4, 10_000, 2_000)

      assert [%{spell_id: 133, spell_ms: 8_000}, %{spell_id: 2136, spell_ms: 8_000}] =
               Cooldowns.initial(entity, entity.internal.spellbook, 4_000)

      assert Cooldowns.ready_at(entity, spell) == 6_000
      assert Cooldowns.initial(entity, entity.internal.spellbook, 12_000) == []
    end
  end

  describe "emit/3" do
    test "clearing a spell cooldown restores its active school timer", %{entity: entity} do
      now = Time.now()
      entity = Cooldowns.lock_schools(entity, 4, 10_000, now)
      Spells.emit(entity, Effects.clear_cooldown(entity.object.guid, 133), Context.new(self()))
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgClearCooldown{spell_id: 133}}}
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgSpellCooldown{cooldowns: [{133, remaining}]}}}
      assert remaining in 1..10_000
    end
  end

  defp caster(_context) do
    spells = [%Spell{id: 133, school: :fire}, %Spell{id: 2136, school: :fire}, %Spell{id: 116, school: :frost}]
    %{entity: %Character{object: %Object{guid: 1}, internal: %Internal{spellbook: Map.new(spells, &{&1.id, &1})}}}
  end
end
