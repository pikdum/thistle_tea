defmodule ThistleTea.Game.Entity.Logic.AI.BT.Ranged do
  @moduledoc """
  Player Auto Shot loop paced by the derived ranged weapon speed.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World

  @minimum_range 8.0

  def sequence do
    BT.sequence([BT.condition(&active?/2), BT.action(&shoot/2), BT.action(&wait/2)])
  end

  def active?(%Character{internal: %Internal{auto_shot: %{target_guid: target_guid}}}, %Blackboard{})
      when is_integer(target_guid) and target_guid > 0, do: true

  def active?(_state, _blackboard), do: false

  def shoot(%Character{} = character, %Blackboard{} = blackboard), do: shoot(character, blackboard, Time.now())

  def shoot(%Character{internal: %Internal{auto_shot: auto_shot}} = character, %Blackboard{} = blackboard, now) do
    distance = World.distance_to_guid(character, auto_shot.target_guid)

    cond do
      not is_number(distance) ->
        {:failure, stop(character), blackboard}

      distance < @minimum_range or distance > auto_shot.spell.range_yards ->
        {:success, character, blackboard}

      now < auto_shot.next_at ->
        {:success, character, blackboard}

      true ->
        {:success, fire(character, auto_shot, now), blackboard}
    end
  end

  def shoot(character, blackboard, _now), do: {:failure, character, blackboard}

  def wait(%Character{internal: %Internal{auto_shot: %{next_at: next_at}}} = character, blackboard) do
    delay = max(next_at - Time.now(), 0)
    {{:running, delay}, character, blackboard}
  end

  def wait(character, blackboard), do: {:failure, character, blackboard}

  def stop(%Character{internal: %Internal{} = internal} = character),
    do: %{character | internal: %{internal | auto_shot: nil}}

  defp fire(character, auto_shot, now) do
    context = CastContext.from_caster(character, auto_shot.spell, auto_shot.target_guid)
    speed = max(character.unit.ranged_attack_time || 2_000, 1)
    auto_shot = %{auto_shot | next_at: now + speed}

    character
    |> then(&%{&1 | internal: %{&1.internal | auto_shot: auto_shot}})
    |> Event.enqueue(
      Event.spell_go(character.object.guid, auto_shot.spell.id, [auto_shot.target_guid], auto_shot.raw_targets)
    )
    |> Event.enqueue(Event.deliver_spell(auto_shot.target_guid, context, auto_shot.spell))
    |> consume_ammo(auto_shot.spell)
  end

  defp consume_ammo(character, %Spell{} = spell) do
    case Hunter.ammo_reagents(character, spell) do
      [] -> character
      reagents -> Event.enqueue(character, Event.consume_reagents(reagents))
    end
  end
end
