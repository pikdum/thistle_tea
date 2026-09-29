defmodule ThistleTea.Game.World.Loader.QuestRewardsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "cached/1" do
    test "Arcane Cloaking triggers the periodic hidden quest credit spell" do
      caster = %Character{
        object: %Object{guid: 7},
        unit: %Unit{health: 100, level: 60},
        player: %Player{},
        internal: %Internal{}
      }

      spell = SpellLoader.cached(28_006)
      context = %CastContext{caster_guid: 7, caster_level: 60, target_guid: 7, target_role: :caster, triggered?: true}
      {_caster, events} = SpellEffect.receive(caster, context, spell, 1000)
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 29_296, target_guid: 7}, &1))
      trigger = SpellLoader.cached(29_296)
      assert Enum.any?(trigger.effects, &match?(%{aura: :periodic_trigger_spell, trigger_spell_id: 29_294}, &1))
      credit = SpellLoader.cached(29_294)
      assert Enum.any?(credit.effects, &match?(%{type: :quest_complete, misc_value: 9378}, &1))
    end
  end
end
