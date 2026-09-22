defmodule ThistleTea.Game.Entity.Logic.StackingProcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcRule

  setup [:caster]

  describe "apply_spell/5" do
    test "Unstable Power initializes twelve stacks and replenishes on a new use", %{caster: caster} do
      buffed = apply_buff(caster, 24_658, 0)
      assert power(buffed) == {204, 408}
      assert holder(buffed, 24_659).stacks == 12
      assert stack_byte(buffed, 24_659) == 11
      {spent, _} = react(buffed, damage_spell(), 1_000)
      assert power(spent) == {187, 374}
      refreshed = apply_buff(spent, 24_658, 2_000)
      assert power(refreshed) == {204, 408}
      assert holder(refreshed, 24_659).expires_at == 22_000
    end

    test "late triggered bonuses cannot restore an ended parent", %{caster: caster} do
      for id <- [24_659, 28_204] do
        {unchanged, events} = Aura.apply_spell(caster, 1, 60, buff(id), 1_000)
        assert unchanged == caster
        assert events == []
      end
    end
  end

  describe "reactions/3" do
    test "Unstable Power spends one stack per cast through exhaustion", %{caster: caster} do
      buffed = apply_buff(caster, 24_658, 0)

      exhausted =
        Enum.reduce(1..12, buffed, fn cast, current ->
          {updated, events} = react(current, damage_spell(), cast * 1_000)
          assert events == []
          assert power(updated) == {17 * (12 - cast), 34 * (12 - cast)}
          updated
        end)

      refute holder(exhausted, 24_659)
      assert holder(exhausted, 24_658)
      assert power(elem(react(exhausted, damage_spell(), 13_000), 0)) == {0, 0}
    end

    test "damage, healing, periodic spells, area casts and supported totems consume once", %{caster: caster} do
      buffed = apply_buff(caster, 24_658, 0)

      spells = [
        damage_spell(),
        %{damage_spell() | effects: [%Effect{type: :heal}]},
        %{damage_spell() | effects: [%Effect{type: :school_damage, area_target?: true}]},
        %{damage_spell() | effects: [%Effect{type: :apply_aura, aura: :periodic_damage}]},
        %{damage_spell() | effects: [%Effect{type: :apply_aura, aura: :periodic_heal}]},
        %{damage_spell() | spell_visual: 319, spell_icon: 1647, effects: [%Effect{type: :summon_totem}]}
      ]

      for spell <- spells do
        {spent, _} = react(buffed, spell, 1_000)
        assert holder(spent, 24_659).stacks == 11
      end

      for spell <- [
            %{damage_spell() | school: :physical},
            %{damage_spell() | effects: [%Effect{type: :apply_aura, aura: :mod_stat}]}
          ] do
        {unchanged, _} = react(buffed, spell, 1_000)
        assert holder(unchanged, 24_659).stacks == 12
      end
    end

    test "Ascendance grows to five stacks and the sixth cast removes both holders", %{caster: caster} do
      buffed = apply_buff(caster, 28_200, 0)
      assert holder(buffed, 28_200).charges == 6
      assert stack_byte(buffed, 28_200) == 5

      buffed =
        Enum.reduce(1..5, buffed, fn cast, current ->
          {updated, events} = react(current, damage_spell(), cast * 1_000)
          assert holder(updated, 28_200).charges == 6 - cast
          updated = deliver_triggers(updated, events, cast * 1_000)
          assert power(updated) == {40 * cast, 75 * cast}
          updated
        end)

      saved = CastContext.from_caster(buffed, damage_spell(), 2)
      {exhausted, events} = react(buffed, damage_spell(), 6_000)
      assert events == []
      assert exhausted.unit.auras == []
      assert power(exhausted) == {0, 0}
      assert saved.spell_damage_bonus.fire == 200
      assert saved.healing_bonus == 375
    end

    test "Ascendance rejects area and script-effect casts and both ignore impact feedback", %{caster: caster} do
      buffed = apply_buff(caster, 28_200, 0)

      for effect <- [%Effect{type: :school_damage, area_target?: true}, %Effect{type: :script_effect}] do
        {unchanged, events} = react(buffed, %{damage_spell() | effects: [effect]}, 1_000)
        assert unchanged.unit.auras == buffed.unit.auras
        assert events == []
      end

      for id <- [24_658, 28_200] do
        buffed = apply_buff(caster, id, 0)
        context = %{spell: damage_spell(), proc_type: :deal_harmful_spell, outcome: :normal, victim_guid: 2, now: 1_000}
        {unchanged, events} = Aura.reactions(buffed, :spell_hit_dealt, context)
        assert unchanged == buffed
        assert events == []
      end
    end
  end

  describe "transition/2" do
    test "parent removal cleans bonuses for every cause and expiry respects the original deadline", %{caster: caster} do
      for id <- [24_658, 28_200] do
        buffed = apply_buff(caster, id, 0)
        {buffed, events} = react(buffed, damage_spell(), 19_000)
        buffed = deliver_triggers(buffed, events, 19_000)

        for cause <- Change.causes() -- [:applied, :ticked, :delayed] do
          kept = Enum.reject(buffed.unit.auras, &(&1.spell.id == id))
          {removed, _} = Aura.transition(buffed, %Change{holders: kept, cause: cause, now: 19_500})
          assert removed.unit.auras == []
          assert power(removed) == {0, 0}
        end

        {expired, _} = Aura.tick(buffed, 20_000)
        assert expired.unit.auras == []
        dead = Core.take_damage(buffed, 100, 19_500)
        assert dead.unit.auras == []
      end
    end
  end

  defp caster(_context) do
    %{
      caster: %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 100, max_health: 100, level: 60, class: 8, auras: []},
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp apply_buff(caster, id, now) do
    {caster, events} = Aura.apply_spell(caster, 1, 60, buff(id), now)
    deliver_triggers(caster, events, now)
  end

  defp deliver_triggers(caster, events, now) do
    Enum.reduce(events, caster, fn
      %Effects.TriggerSpell{spell_id: id}, current -> elem(Aura.apply_spell(current, 1, 60, buff(id), now), 0)
      _event, current -> current
    end)
  end

  defp react(caster, spell, now) do
    Aura.reactions(caster, :spell_cast_completed, %{
      spell: spell,
      proc_type: Proc.cast_type(spell),
      outcome: :cast_end,
      victim_guid: 2,
      now: now
    })
  end

  defp holder(caster, id), do: Enum.find(caster.unit.auras, &(&1.spell.id == id))

  defp power(caster) do
    context = CastContext.from_caster(caster, damage_spell(), 2)
    {context.spell_damage_bonus.fire, context.healing_bonus}
  end

  defp stack_byte(caster, id) do
    slot = holder(caster, id).slot
    :binary.at(caster.unit.aura_applications, slot)
  end

  defp damage_spell, do: %Spell{id: 133, school: :fire, dmg_class: 1, effects: [%Effect{type: :school_damage}]}

  defp buff(id) do
    %Spell{
      id: id,
      duration_ms: 20_000,
      proc_type_mask: 0x15550,
      proc_chance: 100,
      proc_rule: %ProcRule{proc_ex: 0x80000}
    }
    |> buff_effects(id)
  end

  defp buff_effects(spell, 24_658), do: %{spell | effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy}]}

  defp buff_effects(spell, 28_200),
    do: %{spell | effects: [%Effect{index: 0, type: :apply_aura, aura: :proc_trigger_spell, trigger_spell_id: 28_204}]}

  defp buff_effects(spell, id) do
    {damage, healing, cap, duration} = if id == 24_659, do: {17, 34, 12, 20_000}, else: {40, 75, 5, -1}

    %{
      spell
      | stack_amount: cap,
        duration_ms: duration,
        effects: [
          %Effect{index: 0, type: :apply_aura, aura: :mod_damage_done, base_points: damage, misc_value: 126},
          %Effect{index: 1, type: :apply_aura, aura: :mod_healing_done, base_points: healing, misc_value: 126}
        ]
    }
  end
end
