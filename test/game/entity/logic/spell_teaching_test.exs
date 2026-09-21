defmodule ThistleTea.Game.Entity.Logic.SpellTeachingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Script
  alias ThistleTea.Game.Entity.Logic.SpellTeaching
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:teaching]

  describe "apply/5" do
    test "emits one owner request for multiple taught spells and a skill step", context do
      %{character: character, spell: spell} = context
      cast = %CastContext{caster_guid: character.object.guid, caster_level: 50, cast_item_guid: 99}

      events =
        Enum.flat_map(spell.effects, fn effect ->
          assert {^character, events} = Script.apply(character, cast, spell, effect, 1_000)
          events
        end)

      assert [%Effects.TeachSpell{spell: ^spell, skill_steps: [{185, 3}], cast_item_guid: 99}] = events
      assert SpellTeaching.spell_ids(spell) == [3413, 818]
    end

    test "NPC teaching reaches a player without transferring a caster's item cost", context do
      %{character: character, spell: spell} = context
      cast = %CastContext{caster_guid: character.object.guid + 1, cast_item_guid: 99}

      assert {^character, [%Effects.TeachSpell{cast_item_guid: nil}]} =
               Script.apply(character, cast, spell, hd(spell.effects), 1_000)

      mob = %Mob{object: %Object{guid: 3}}
      assert {^mob, []} = Script.apply(mob, cast, spell, hd(spell.effects), 1_000)
    end
  end

  describe "apply_steps/2" do
    test "sets the exact cap and preserves points and slots" do
      skills = Skills.learn_rank(%{}, 185, 300)
      skills = put_in(skills[185].value, 125)
      stepped = SpellTeaching.apply_steps(skills, [{185, 3}])
      assert %{value: 125, max: 225, step: 3} = stepped[185]
      assert stepped[185].slot == skills[185].slot
      assert %{129 => %{value: 1, max: 75, step: 1}} = SpellTeaching.apply_steps(%{}, [{129, 1}])
    end

    test "ignores invalid and negative steps and retains the existing step for zero" do
      effects = [
        %Effect{type: :skill_step, misc_value: 185, base_points: -2, base_dice: 1},
        %Effect{type: :skill_step, misc_value: 0, base_points: 0, base_dice: 1}
      ]

      assert SpellTeaching.skill_steps(%Spell{id: 1, effects: effects}) == []
      skills = Skills.learn_rank(%{}, 185, 75)
      assert %{185 => %{value: 1, max: 0, step: 1}} = SpellTeaching.apply_steps(skills, [{185, 0}])
    end
  end

  describe "emit/3" do
    test "uses the explicit owner context without ambient delivery", %{character: character, spell: spell} do
      event = %Effects.TeachSpell{spell: spell, skill_steps: [{185, 3}]}
      assert EventSink.emit(character, event) == character
      refute_received {:teach_spell, _}
      assert EventSink.emit(character, event, Context.new(self())) == character
      assert_received {:teach_spell, ^event}
    end
  end

  defp teaching(_context) do
    %{
      character: %Character{
        object: %Object{guid: System.unique_integer([:positive, :monotonic])},
        unit: %Unit{level: 50},
        player: %Player{},
        internal: %Internal{}
      },
      spell: %Spell{
        id: 100,
        effects: [
          %Effect{index: 0, type: :learn_spell, trigger_spell_id: 3413},
          %Effect{index: 1, type: :learn_spell, trigger_spell_id: 818},
          %Effect{index: 2, type: :skill_step, misc_value: 185, base_points: 2, base_dice: 1}
        ]
      }
    }
  end
end
