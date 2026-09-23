defmodule ThistleTea.Game.Spell.DeferredCooldownsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:cooldown_source]

  describe "activate_on_event/3" do
    test "retains item overrides and applies current cooldown modifiers once", %{character: character, spell: spell} do
      item_spell = %{spell | recovery_time_ms: 60_000, category: 94, category_recovery_time_ms: 10_000}
      character = Cooldowns.start(character, item_spell, 1_000, 4_396)

      modifier = %Holder{
        spell: %Spell{id: 2, spell_family: 8},
        auras: [%Aura{type: :add_pct_modifier, misc_value: 11, amount: -50, class_mask: 1}]
      }

      character = %{character | unit: %{character.unit | auras: [modifier]}}
      removed = %Holder{spell: spell, caster_guid: 1, cooldown_started_at: 1_000}
      {character, [event]} = Cooldowns.activate_on_event(character, [removed], 5_000)

      assert %Effects.CooldownEvent{spell_id: 14_177} = event
      assert Cooldowns.ready_at(character, item_spell) == 35_000
      assert Cooldowns.ready_at(character, %{item_spell | id: 99}) == 15_000
      assert {^character, []} = Cooldowns.activate_on_event(character, [removed], 8_000)
      assert [%{item_id: 4_396, spell_ms: 29_000, category_ms: 9_000}] = Cooldowns.initial(character, %{}, 6_000)
    end

    test "removal requests the caster's timer and replacement keeps it disabled", %{character: character, spell: spell} do
      character = Cooldowns.start(character, spell, 100)
      removed = %Holder{spell: spell, caster_guid: 9, cooldown_started_at: 50}

      assert {^character, [%Effects.ActivateCooldown{target_guid: 9, started_at: 50}]} =
               Cooldowns.activate_on_event(character, [removed], 500)

      assert Cooldowns.pending(character, spell.id)

      own = %{removed | caster_guid: 1, cooldown_started_at: 100}
      character = %{character | unit: %{character.unit | auras: [own]}}
      assert {^character, []} = Cooldowns.activate_on_event(character, [own], 500)
    end
  end

  describe "handle_event/3" do
    test "old completion and cancellation cannot affect a newer cast", %{character: character, spell: spell} do
      event = %Effects.ActivateCooldown{target_guid: 1, spell_id: spell.id, started_at: 100}
      character = character |> Cooldowns.start(spell, 100) |> Cooldowns.reset([spell.id]) |> Cooldowns.start(spell, 200)

      assert {^character, []} = Cooldowns.handle_event(character, event, 500)
      assert {^character, []} = Cooldowns.handle_event(character, %{event | cancel?: true}, 500)
      current = %{event | started_at: 200}
      {character, [_]} = Cooldowns.handle_event(character, current, 600)
      assert Cooldowns.ready_at(character, spell) == 180_600
      assert {^character, []} = Cooldowns.handle_event(character, current, 700)
    end

    test "canceling a pending object releases its shared category", %{character: character, spell: spell} do
      spell = %{spell | category: 94}
      character = Cooldowns.start(character, spell, 100)
      event = %Effects.ActivateCooldown{target_guid: 1, spell_id: spell.id, started_at: 100, cancel?: true}

      assert Cooldowns.on_cooldown?(character, %{spell | id: 99}, 500)
      {character, [%Effects.ClearCooldown{}]} = Cooldowns.handle_event(character, event, 500)
      refute Cooldowns.on_cooldown?(character, spell, 500)
      refute Cooldowns.on_cooldown?(character, %{spell | id: 99}, 500)
    end
  end

  describe "initial/3" do
    test "includes unlearned item spells and the permanent cooldown wire flag", %{character: character, spell: spell} do
      spell = %{spell | category: 94}
      character = Cooldowns.start(character, spell, 100, 4_396)

      assert [%{spell_id: 14_177, item_id: 4_396, category: 94, spell_ms: 1, category_ms: 0x80000000}] =
               Cooldowns.initial(character, %{99 => %{spell | id: 99}}, 1_000_000)
    end
  end

  describe "reset/2" do
    test "resetting a category preserves the originating spell's own timer", %{character: character, spell: spell} do
      spell = %{spell | category: 94, attributes: MapSet.new(), category_recovery_time_ms: 10_000}
      character = character |> Cooldowns.start(spell, 100) |> Cooldowns.reset([{:category, 94}])
      assert Cooldowns.on_cooldown?(character, spell, 500)
      refute Cooldowns.on_cooldown?(character, %{spell | id: 99}, 500)
      character = Cooldowns.start(character, %{spell | id: 99}, 500)

      assert [
               %{spell_id: 99, category: 94, category_ms: 9_500},
               %{spell_id: 14_177, category: 0, spell_ms: 179_100, category_ms: 0}
             ] = Cooldowns.initial(character, %{}, 1_000)
    end
  end

  describe "cancel/2" do
    test "canceled rituals clear the pending timer before asynchronous object cleanup", %{
      character: character,
      spell: spell
    } do
      spell = %{
        spell
        | effects: [%Effect{type: :trans_door}],
          duration_ms: 10_000,
          attributes: MapSet.put(spell.attributes, :channeled)
      }

      casting = Cast.new(spell, Target.self(1), 100)
      character = character |> Cooldowns.start(spell, 100) |> then(&%{&1 | internal: %{&1.internal | casting: casting}})
      character = Casting.cancel(character, 500)
      refute Cooldowns.on_cooldown?(character, spell, 500)
      assert Enum.any?(character.internal.events, &match?(%Effects.ClearCooldown{spell_id: 14_177}, &1))
    end
  end

  defp cooldown_source(_context) do
    character = %Character{object: %Object{guid: 1}, unit: %Unit{health: 100, auras: []}, internal: %Internal{}}

    spell = %Spell{
      id: 14_177,
      spell_family: 8,
      family_flags_0: 1,
      recovery_time_ms: 180_000,
      attributes: MapSet.new([:cooldown_on_event])
    }

    %{character: character, spell: spell}
  end
end
