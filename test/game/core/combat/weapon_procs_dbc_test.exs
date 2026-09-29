defmodule ThistleTea.Game.Core.Combat.WeaponProcsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat.WeaponProcs
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "spell_allowed?/1" do
    test "real melee abilities qualify while ordinary ranged spells do not" do
      for id <- [78, 1752, 6770, 2973], do: assert(WeaponProcs.spell_allowed?(SpellLoader.load(id)))
      for id <- [75, 19_434, 2764, 5019, 133], do: refute(WeaponProcs.spell_allowed?(SpellLoader.load(id)))
    end
  end

  describe "innate_events/6" do
    test "Destiny buffs its wielder through implicit targeting and expires without leaving strength" do
      spell = SpellLoader.load(17_152)
      assert spell.proc_chance == 101
      assert spell.duration_ms == 10_000

      character = %Character{
        object: %Object{guid: 1},
        player: %Player{},
        unit: %Unit{level: 60, health: 100, max_health: 100, base_strength: 20, strength: 20},
        internal: %Internal{spellbook: %{spell.id => spell}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      item = Item.build(%ItemTemplate{entry: 647, class: 2, delay: 2600, spellid_1: spell.id, spelltrigger_1: 2}, 99)
      hit = %Effects.TriggerWeaponProcs{source_guid: 1, target_guid: 2, hand: :mainhand}

      assert {[trigger], true} =
               WeaponProcs.innate_events(character, hit, item, %{spell.id => spell}, 1_000, fn -> 0.04 end)

      events = Spells.resolve(character, trigger)

      assert [%Effects.DeliverSpell{target_guid: 1, cast_context: context}] =
               Enum.filter(events, &is_struct(&1, Effects.DeliverSpell))

      assert context.cast_item_guid == 99
      assert context.triggered?
      {buffed, _events} = SpellEffect.receive(character, context, spell, 1_000)
      assert buffed.unit.strength == 220
      assert [%{spell: %{id: 17_152}, expires_at: 11_000}] = buffed.unit.auras
      {expired, _events} = Aura.expire_due(buffed, 11_000)
      assert expired.unit.strength == 20
      assert expired.unit.auras == []
    end
  end
end
