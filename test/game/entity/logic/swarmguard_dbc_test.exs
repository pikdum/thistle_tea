defmodule ThistleTea.Game.Entity.Logic.SwarmguardDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ResistancePenetration
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db
  @badge 26_480
  @insight 26_481

  setup [:character]

  describe "receive/4" do
    test "ranged procs stack six armor penetration buffs on the bearer", %{character: character, parent: parent} do
      assert parent.duration_ms == 30_000
      child = character.internal.spellbook[@insight]
      assert child.duration_ms == -1
      assert child.stack_amount == 6
      {character, _} = Aura.apply_spell(character, 1, 60, parent, 0)

      stacked =
        Enum.reduce(1..7, character, fn hit, current ->
          {current, event} = shoot(current, hit * 1_000)
          current = deliver(current, event, hit * 1_000)
          holder = Enum.find(current.unit.auras, &(&1.spell.id == @insight))
          assert holder.stacks == min(hit, 6)
          assert :binary.at(current.unit.aura_applications, holder.slot) == min(hit, 6) - 1

          assert ResistancePenetration.resistance(2_000, ResistancePenetration.snapshot(current), :physical) ==
                   2_000 - min(hit, 6) * 200

          current
        end)

      {expired, _} = Aura.expire_due(stacked, 30_000)
      assert expired.unit.auras == []
      assert ResistancePenetration.snapshot(expired) == []
      {cancelled, _} = Aura.cancel_spell(stacked, @badge, 10_000)
      assert cancelled.unit.auras == []
      dead = Core.take_damage(stacked, stacked.unit.health, 10_000)
      assert dead.unit.health == 0
      assert dead.unit.auras == []
    end

    test "queued procs cannot restore the permanent buff after the badge expires", %{
      character: character,
      parent: parent
    } do
      {character, _} = Aura.apply_spell(character, 1, 60, parent, 0)
      {character, event} = shoot(character, 29_999)
      [delivery] = deliveries(character, event)
      assert delivery.target_guid == 1
      assert delivery.cast_context.required_aura_source != nil
      {expired, _} = Aura.expire_due(character, 30_000)

      for delivery <- [delivery | deliveries(expired, event)] do
        {unchanged, _} = SpellEffect.receive(expired, delivery.cast_context, delivery.spell, 30_001)
        assert unchanged.unit.auras == []
        assert ResistancePenetration.snapshot(unchanged) == []
      end
    end
  end

  defp character(_context) do
    parent = %{SpellLoader.load(@badge) | proc_rule: %ProcRule{ppm_rate: 10}}
    book = %{@badge => parent, @insight => SpellLoader.load(@insight)}

    %{
      parent: parent,
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{},
        internal: %Internal{spellbook: book},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        unit: %Unit{class: 3, level: 60, health: 100, max_health: 100, auras: [], base_ranged_attack_time: 6_000}
      }
    }
  end

  defp shoot(character, now) do
    payload = %{victim_guid: 2, proc_type: :deal_ranged_attack, outcome: :normal, damage: 30}
    character = SpellFeedback.receive(character, payload, SpellLoader.load(75), now)
    {character, events} = Effects.drain(character)
    assert [%Effects.TriggerSpell{spell_id: @insight} = event] = events
    {character, event}
  end

  defp deliveries(character, event),
    do: Enum.filter(Spells.resolve(character, event), &is_struct(&1, Effects.DeliverSpell))

  defp deliver(character, event, now) do
    [delivery] = deliveries(character, event)
    assert delivery.target_guid == character.object.guid
    {character, _} = SpellEffect.receive(character, delivery.cast_context, delivery.spell, now)
    character
  end
end
