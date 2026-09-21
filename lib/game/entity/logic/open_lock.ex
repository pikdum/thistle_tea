defmodule ThistleTea.Game.Entity.Logic.OpenLock do
  @moduledoc """
  Resolves a spell or key against ordered lock alternatives without world
  access. Equipment bonuses affect admission, while gains use learned skill.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Lock
  alias ThistleTea.Game.Entity.Data.Lock.Requirement
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  defstruct [:lock_id, :lock_type, :skill_id, required: 0, value: 0, gain?: false]

  def spell?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.type == :open_lock))

  def resolve(%Character{} = character, %Spell{} = spell, %Lock{} = lock, cast_item_entry \\ nil) do
    effects = Enum.filter(spell.effects, &(&1.type == :open_lock))

    Enum.reduce_while(effects, {:error, :bad_targets}, fn effect, _error ->
      case resolve_effect(character, effect, lock, cast_item_entry) do
        {:error, :bad_targets} = error -> {:cont, error}
        result -> {:halt, result}
      end
    end)
  end

  def key(%Lock{} = lock, count_item) when is_function(count_item, 1) do
    if Enum.any?(lock.requirements, &key_available?(&1, count_item)),
      do: {:ok, %__MODULE__{lock_id: lock.id}},
      else: {:error, :bad_targets}
  end

  def key(_lock, _count_item), do: {:error, :bad_targets}

  defp key_available?(%Requirement{type: :item, index: id}, count_item) when id > 0, do: count_item.(id) > 0
  defp key_available?(_requirement, _count_item), do: false

  defp resolve_effect(character, effect, lock, cast_item_entry) do
    Enum.reduce_while(lock.requirements, {:error, :bad_targets}, fn requirement, _error ->
      case requirement(character, effect, requirement, cast_item_entry) do
        :skip -> {:cont, {:error, :bad_targets}}
        {:ok, result} -> {:halt, {:ok, %{result | lock_id: lock.id}}}
        error -> {:halt, error}
      end
    end)
  end

  defp requirement(_character, _effect, %Requirement{type: :item, index: id}, id) when id > 0 do
    {:ok, %__MODULE__{}}
  end

  defp requirement(character, %Effect{misc_value: type} = effect, %Requirement{type: :skill, index: type} = req, item) do
    skill_id = skill_id(type)
    value = if is_nil(item), do: skill_value(character, skill_id), else: 0
    value = value + max((effect.base_points || -1) + 1, 0)
    required = if skill_id || type == 16, do: req.skill, else: 0

    if value >= required do
      {:ok,
       %__MODULE__{
         lock_type: type,
         skill_id: skill_id,
         value: value,
         required: required,
         gain?: is_nil(item) and Skills.known?(character.player.skills, skill_id)
       }}
    else
      {:error, :low_castlevel}
    end
  end

  defp requirement(_character, _effect, _requirement, _item), do: :skip

  defp skill_id(1), do: 633
  defp skill_id(2), do: 182
  defp skill_id(3), do: 186
  defp skill_id(19), do: 356
  defp skill_id(_type), do: nil

  defp skill_value(character, skill_id) do
    if Skills.known?(character.player.skills, skill_id) do
      {temporary, permanent} = Map.get(Skills.bonuses(character), skill_id, {0, 0})
      max(Skills.value(character.player.skills, skill_id) + temporary + permanent, 0)
    else
      0
    end
  end
end
