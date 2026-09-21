defmodule ThistleTea.Game.Entity.Logic.AI.BT.Ranged do
  @moduledoc """
  Player auto-repeat attacks paced by the derived ranged weapon speed.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Detection
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.AutoRepeat
  alias ThistleTea.Game.Entity.Logic.CombatControl
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.WeaponDamage
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  def sequence do
    BT.sequence([BT.condition(&active?/2), BT.action(&shoot_with_context/3), BT.action(&wait/3)])
  end

  def active?(%Character{internal: %Internal{auto_shot: %{target_guid: target_guid}}} = character, %Blackboard{})
      when is_integer(target_guid) and target_guid > 0, do: not Core.dead?(character)

  def active?(_state, _blackboard), do: false

  defp shoot_with_context(
         %Character{internal: %Internal{auto_shot: %{}}} = character,
         %Blackboard{} = blackboard,
         %Context{now: now} = context
       ) do
    if AutoRepeat.moving?(character) or not is_nil(character.internal.casting) do
      {:success, AutoRepeat.interrupt(character, now), blackboard}
    else
      character = AutoRepeat.resume(character, now)
      auto_shot = character.internal.auto_shot
      distance = combat_distance(character, auto_shot.target_guid, context)
      shoot_at_distance(character, blackboard, now, distance, auto_shot)
    end
  end

  defp shoot_with_context(character, blackboard, %Context{}), do: {:failure, character, blackboard}

  defp shoot_at_distance(character, blackboard, now, distance, auto_shot) do
    cond do
      blocked?(character, auto_shot.spell) ->
        {:failure, stop(character), blackboard}

      not is_number(distance) ->
        {:failure, stop(character), blackboard}

      outside_range?(distance, auto_shot.spell) ->
        {:failure, stop(character), blackboard}

      now < auto_shot.next_at ->
        {:success, character, blackboard}

      Map.get(auto_shot, :pending?, false) ->
        {:success, character, blackboard}

      true ->
        speed = max(character.unit.ranged_attack_time || 2_000, 1)
        auto_shot = auto_shot |> Map.put(:next_at, now + speed) |> Map.put(:pending?, true)
        character = %{character | internal: %{character.internal | auto_shot: auto_shot}}
        request = %Effects.LaunchRanged{kind: :repeat, request: auto_shot, now: now}
        {:success, Effects.enqueue(character, request), blackboard}
    end
  end

  defp blocked?(character, spell) do
    CombatControl.pacified?(character) or CombatControl.prevention(character, spell) != :ok or
      :ranged in (character.player.broken_equipment || [])
  end

  defp wait(%Character{internal: %Internal{auto_shot: %{next_at: next_at}}} = character, blackboard, %Context{now: now}) do
    delay = max(next_at - now, 50)
    {{:running, delay}, character, blackboard}
  end

  defp wait(character, blackboard, %Context{}), do: {:failure, character, blackboard}

  def stop(%Character{} = character) do
    {character, effects} = AutoRepeat.cancel(character)
    Effects.enqueue(character, effects)
  end

  def fire(%Character{} = character, auto_shot, now) do
    {character, events} = Aura.remove_with_interrupt_flags(character, Aura.interrupt_mask(:attack), now)
    character = Effects.enqueue(character, events)
    spell = WeaponDamage.prepare_spell(character, auto_shot.spell)
    context = CastContext.from_caster(character, spell, auto_shot.target_guid)

    character
    |> AutoRepeat.launched(auto_shot, now)
    |> Effects.enqueue(Effects.spell_go(character.object.guid, spell.id, [auto_shot.target_guid], auto_shot.targets))
    |> Effects.enqueue(Effects.deliver_spell(auto_shot.target_guid, context, spell))
  end

  defp combat_distance(%Character{unit: unit} = character, target_guid, %Context{perception: perception} = context) do
    with distance when is_number(distance) <- Perception.distance(perception, target_guid),
         target when is_map(target) <- Perception.metadata(perception, target_guid),
         true <- Map.get(target, :alive?, true),
         true <- Perception.line_of_sight?(perception, target_guid),
         true <- Detection.detectable?(character, target_guid, context) do
      max(distance - combat_reach(unit.combat_reach) - combat_reach(Map.get(target, :combat_reach)), 0.0)
    else
      _unknown -> nil
    end
  end

  defp combat_reach(reach) when is_number(reach) and reach > 0, do: reach
  defp combat_reach(_reach), do: 0.0

  defp outside_range?(distance, %Spell{min_range_yards: min_range, range_yards: max_range}) do
    (is_number(min_range) and min_range > 0 and distance < min_range) or
      (is_number(max_range) and max_range > 0 and distance > max_range)
  end
end
