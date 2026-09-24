defmodule ThistleTea.Game.Entity.Logic.FeignDeath do
  @moduledoc """
  Feign Death keeps its resistance result on the aura that owns the death pose.
  Success ends combat and prevents direct NPC targeting; resistance only stops
  the owner's attacks. Neither outcome changes whether the unit is alive.
  """
  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Target

  defmodule Attempt do
    @moduledoc false
    defstruct resisted?: false, pet_in_combat?: false
  end

  def spell?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.aura == :feign_death))

  def successful?(%{unit: %Unit{auras: holders}}), do: successful?(holders)
  def successful?(%{feigning_death?: active?}), do: active?
  def successful?(holders) when is_list(holders), do: Enum.any?(holders, &successful_holder?/1)
  def successful?(_entity), do: false

  def interrupt_holders(previous, desired) do
    if successful?(desired) and not successful?(previous),
      do: Enum.reject(desired, &Holder.interruptible?(&1, 0x00100000)),
      else: desired
  end

  def reconcile(%{unit: %Unit{} = unit} = entity, previous, current, now) do
    holder = Enum.find(current, &Holder.has_aura_type?(&1, :feign_death))
    previous_holder = Enum.find(previous, &Holder.has_aura_type?(&1, :feign_death))
    flags = unit.dynamic_flags || 0

    flags =
      cond do
        holder -> flags ||| 0x20
        previous_holder -> flags &&& bnot(0x20)
        true -> unit.dynamic_flags
      end

    entity = %{entity | unit: %{unit | dynamic_flags: flags}}

    if holder && (is_nil(previous_holder) or attempt(holder).resisted? != attempt(previous_holder).resisted?),
      do: entity |> Casting.cancel(now) |> stop_movement(now) |> apply_attempt(attempt(holder), now),
      else: {entity, []}
  end

  def target_lost(entity, target_guid, now) do
    entity =
      case entity.internal.casting do
        %Cast{targets: %Target{} = targets} ->
          if Target.unit_guid(targets) == target_guid, do: Casting.interrupt(entity, now), else: entity

        _ ->
          entity
      end

    case entity do
      %Character{unit: %Unit{target: ^target_guid}} ->
        {entity, events} = PlayerCombat.stop_attack(entity)
        Effects.enqueue(entity, events)

      _ ->
        entity
    end
  end

  defp successful_holder?(%Holder{} = holder),
    do: Holder.has_aura_type?(holder, :feign_death) and not attempt(holder).resisted?

  defp attempt(%Holder{cast_context: %CastContext{feign_death: %Attempt{} = attempt}}), do: attempt
  defp attempt(_holder), do: %Attempt{}

  defp stop_movement(%{movement_block: %MovementBlock{}} = entity, now) do
    entity = Movement.stop(entity, now)

    %{
      entity
      | movement_block: %{entity.movement_block | movement_flags: entity.movement_block.movement_flags &&& bnot(0x30)}
    }
  end

  defp stop_movement(entity, _now), do: entity

  defp apply_attempt(%Character{} = character, %Attempt{resisted?: true}, _now) do
    {character, events} = PlayerCombat.stop_attack(character)
    {character, [%Effects.FeignDeathResisted{} | events]}
  end

  defp apply_attempt(%Character{} = character, %Attempt{} = attempt, now) do
    {character, events} = PlayerCombat.disengage(character)
    character = if attempt.pet_in_combat?, do: PlayerCombat.hold_combat(character, now, 6_000), else: character
    {character, [%Effects.FeignDeathApplied{} | events]}
  end

  defp apply_attempt(entity, %Attempt{resisted?: true}, _now), do: {entity, []}

  defp apply_attempt(%Mob{} = entity, %Attempt{}, _now) do
    %Engagement.Result{entity: entity} = Engagement.leave(entity, :feign_death)
    {entity, [%Effects.FeignDeathApplied{}]}
  end
end
