defmodule ThistleTea.Game.Entity.Logic.AutoRepeat do
  @moduledoc """
  Pure lifecycle transitions for player auto-repeat spells.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target

  def start(%Character{} = character, %Spell{} = spell, %Target{} = targets, now) do
    next_at = max(character.internal.ranged_attack_at || now, now + 500)
    shot = %{spell: spell, targets: targets, target_guid: Target.unit_guid(targets), next_at: next_at}

    character
    |> then(&%{&1 | internal: %{&1.internal | auto_shot: shot}})
    |> Effects.enqueue(Effects.spell_cast_result(spell.id))
  end

  def interrupt(%Character{internal: %Internal{auto_shot: %{spell: spell} = shot}} = character, now) do
    if Spell.wand?(spell) do
      {character, effects} = cancel(character)
      Effects.enqueue(character, effects)
    else
      shot =
        shot
        |> Map.put(:next_at, max(shot.next_at, now + 500))
        |> Map.put(:paused?, true)
        |> Map.delete(:pending?)

      %{character | internal: %{character.internal | auto_shot: shot}}
    end
  end

  def interrupt(character, _now), do: character

  def resume(%Character{internal: %Internal{auto_shot: %{paused?: true} = shot}} = character, now) do
    shot = shot |> Map.put(:next_at, max(shot.next_at, now + 500)) |> Map.delete(:paused?)
    %{character | internal: %{character.internal | auto_shot: shot}}
  end

  def resume(character, _now), do: character

  def launched(%Character{} = character, shot, now) do
    next_at = now + max(character.unit.ranged_attack_time || 2_000, 1)
    shot = shot |> Map.put(:next_at, next_at) |> Map.delete(:pending?)
    %{character | internal: %{character.internal | auto_shot: shot, ranged_attack_at: next_at}}
  end

  def moving?(%{movement_block: %MovementBlock{} = movement}) do
    MovementBlock.translating?(movement) or MovementBlock.airborne?(movement)
  end

  def moving?(_character), do: false

  def cancel(%Character{internal: %Internal{auto_shot: nil}} = character), do: {character, []}

  def cancel(%Character{internal: %Internal{} = internal} = character) do
    character = %{character | internal: %{internal | auto_shot: nil}}
    {character, [Effects.cancel_auto_repeat()]}
  end

  def cancel(entity), do: {entity, []}
end
