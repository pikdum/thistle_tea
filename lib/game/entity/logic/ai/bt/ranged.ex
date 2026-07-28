defmodule ThistleTea.Game.Entity.Logic.AI.BT.Ranged do
  @moduledoc """
  Player Auto Shot loop paced by the derived ranged weapon speed.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext

  def sequence do
    BT.sequence([BT.condition(&active?/2), BT.action(&shoot_with_context/3), BT.action(&wait/3)])
  end

  def active?(%Character{internal: %Internal{auto_shot: %{target_guid: target_guid}}}, %Blackboard{})
      when is_integer(target_guid) and target_guid > 0, do: true

  def active?(_state, _blackboard), do: false

  defp shoot_with_context(
         %Character{internal: %Internal{auto_shot: auto_shot}} = character,
         %Blackboard{} = blackboard,
         %Context{now: now, perception: perception}
       ) do
    distance = combat_distance(character, auto_shot.target_guid, perception)
    shoot_at_distance(character, blackboard, now, distance, auto_shot)
  end

  defp shoot_with_context(character, blackboard, %Context{}), do: {:failure, character, blackboard}

  defp shoot_at_distance(character, blackboard, now, distance, auto_shot) do
    cond do
      not is_number(distance) ->
        {:failure, stop(character), blackboard}

      outside_range?(distance, auto_shot.spell) ->
        {:success, character, blackboard}

      now < auto_shot.next_at ->
        {:success, character, blackboard}

      true ->
        {:success, fire(character, auto_shot, now), blackboard}
    end
  end

  defp wait(%Character{internal: %Internal{auto_shot: %{next_at: next_at}}} = character, blackboard, %Context{now: now}) do
    delay = max(next_at - now, 0)
    {{:running, delay}, character, blackboard}
  end

  defp wait(character, blackboard, %Context{}), do: {:failure, character, blackboard}

  def stop(%Character{internal: %Internal{} = internal} = character),
    do: %{character | internal: %{internal | auto_shot: nil}}

  defp fire(character, auto_shot, now) do
    context = CastContext.from_caster(character, auto_shot.spell, auto_shot.target_guid)
    speed = max(character.unit.ranged_attack_time || 2_000, 1)
    auto_shot = %{auto_shot | next_at: now + speed}

    character
    |> then(&%{&1 | internal: %{&1.internal | auto_shot: auto_shot}})
    |> Effects.enqueue(
      Effects.spell_go(character.object.guid, auto_shot.spell.id, [auto_shot.target_guid], auto_shot.targets)
    )
    |> Effects.enqueue(Effects.deliver_spell(auto_shot.target_guid, context, auto_shot.spell))
    |> consume_ammo(auto_shot.spell)
  end

  defp consume_ammo(character, %Spell{} = spell) do
    case Hunter.ammo_reagents(character, spell) do
      [] -> character
      reagents -> Effects.enqueue(character, Effects.consume_reagents(reagents))
    end
  end

  defp combat_distance(%Character{unit: unit}, target_guid, %Perception{} = perception) do
    with distance when is_number(distance) <- Perception.distance(perception, target_guid),
         target when is_map(target) <- Perception.metadata(perception, target_guid) do
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
