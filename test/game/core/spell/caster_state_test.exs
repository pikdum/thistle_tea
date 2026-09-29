defmodule ThistleTea.Game.Core.Spell.CasterStateTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CasterState
  alias ThistleTea.Game.Core.Spell.Cooldowns
  alias ThistleTea.Game.Core.Spell.Effect

  describe "validate/4" do
    test "school immunity escapes matching controls and checks every remaining holder" do
      caster = caster([control(:mod_stun, :physical), control(:mod_fear, :shadow)])
      physical = immunity(:school_immunity, 1)
      assert {:error, :fleeing} = CasterState.validate(caster, physical, 0)
      all = %{physical | effects: physical.effects ++ immunity(:school_immunity, 126).effects}
      assert :ok = CasterState.validate(caster, all, 0)
      assert {:error, :stunned} = CasterState.validate(caster, %{all | attributes: MapSet.new()}, 0)
    end

    test "dispel immunity can escape poison control without ignoring magic control" do
      poison = %{control(:mod_stun, :nature) | spell: %Spell{id: 1, school: :nature, dispel_type: 4}}
      magic = %{control(:mod_confuse, :arcane) | spell: %Spell{id: 2, school: :arcane, dispel_type: 1}}
      spell = immunity(:dispel_immunity, 4)
      assert :ok = CasterState.validate(caster([poison]), spell, 0)
      assert {:error, :confused} = CasterState.validate(caster([poison, magic]), spell, 0)
    end

    test "stun escape skips silence while silence alone still prevents Blink" do
      stun = control(:mod_stun, :physical)
      silence = control(:mod_silence, :shadow)
      blink = immunity(:mechanic_immunity, 12)
      assert :ok = CasterState.validate(caster([stun, silence]), blink, 0)
      assert {:error, :silenced} = CasterState.validate(caster([silence]), blink, 0)
      assert {:error, :stunned} = CasterState.validate(caster([stun, silence]), %Spell{}, 0)
    end

    test "control and school lockout bypasses require explicit spell permissions" do
      controlled = caster([control(:mod_stun, :physical), control(:mod_silence, :shadow)])
      spell = %Spell{school: :fire, prevention_type: 1}
      assert :ok = CasterState.validate(controlled, spell, 0, triggered?: true)

      assert :ok =
               CasterState.validate(
                 controlled,
                 %{spell | attributes: MapSet.new([:ignore_caster_and_target_restrictions])},
                 0
               )

      locked = Cooldowns.lock_schools(caster([]), Spell.school_mask(:fire), 5_000, 0)
      assert {:error, :silenced} = CasterState.validate(locked, spell, 1_000)
      assert :ok = CasterState.validate(locked, spell, 1_000, triggered?: true)
      assert :ok = CasterState.validate(locked, spell, 5_000)
    end

    test "stun interrupt flags apply to timed casts while instant spells still require escape" do
      caster = caster([control(:mod_stun, :physical)])
      timed = %Spell{cast_time_ms: 1_000, interrupt_flags: 0}
      assert :ok = CasterState.validate(caster, timed, 0)
      assert {:error, :stunned} = CasterState.validate(caster, %{timed | interrupt_flags: 2}, 0)
      assert {:error, :stunned} = CasterState.validate(caster, %{timed | cast_time_ms: 0}, 0)
    end

    test "immunity rescan considers spell mechanics and only the active effect's mechanic" do
      holder = control(:mod_confuse, :arcane)
      effect = %Effect{index: 1, type: :apply_aura, aura: :mod_confuse, mechanic: 12}
      holder = %{holder | spell: %{holder.spell | effects: [effect]}}
      spell = immunity(:mechanic_immunity, 12)
      assert {:error, :confused} = CasterState.validate(caster([holder]), spell, 0)
      active = %{holder | auras: [%Aura{index: 1, type: :mod_confuse}]}
      assert :ok = CasterState.validate(caster([active]), spell, 0)
      whole = %{holder | spell: %{holder.spell | mechanic: 12}}
      assert :ok = CasterState.validate(caster([whole]), spell, 0)
    end

    test "state immunity and suppressed fear retain their existing escape paths" do
      fear = control(:mod_fear, :shadow)
      state = immunity(:state_immunity, :mod_fear)
      assert :ok = CasterState.validate(caster([fear]), state, 0)
      assert :ok = CasterState.validate(caster([fear, control(:prevent_fleeing, :physical)]), %Spell{}, 0)
      assert {:error, :fleeing} = CasterState.validate(caster([fear]), %Spell{}, 0)
    end

    test "silence and pacification preserve prevention type requirements" do
      caster = caster([control(:mod_pacify_silence, :shadow)])
      assert {:error, :silenced} = CasterState.validate(caster, %Spell{prevention_type: 1}, 0)
      assert {:error, :pacified} = CasterState.validate(caster, %Spell{prevention_type: 2}, 0)
      assert :ok = CasterState.validate(caster, %Spell{prevention_type: 0}, 0)
      assert :ok = CasterState.validate(caster, immunity(:school_immunity, 32), 0)
    end
  end

  defp caster(holders), do: %Character{unit: %Unit{auras: holders}, internal: %Internal{}}

  defp control(type, school) do
    %Holder{
      spell: %Spell{id: 1, school: school},
      auras: [%Aura{index: 0, type: type}],
      negative?: true
    }
  end

  defp immunity(type, value) do
    %Spell{
      id: 2,
      prevention_type: 1,
      attributes: MapSet.new([:immunity_purges_effect]),
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, misc_value: value, implicit_target_a: :caster}]
    }
  end
end
