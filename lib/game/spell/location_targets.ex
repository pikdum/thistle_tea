defmodule ThistleTea.Game.Spell.LocationTargets do
  @moduledoc "Script-selected destinations and the units or objects that supplied them."

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ObjectTargets
  alias ThistleTea.Game.Spell.Target

  defstruct by_effect: %{}, error: nil

  defmodule Selection do
    @moduledoc false
    defstruct [:guid, :position, :kind]
  end

  def required?(%Spell{effects: effects}), do: Enum.any?(effects, &scripted?/1)

  def scripted?(%Effect{} = effect),
    do: :script_location_near_caster in [effect.implicit_target_a, effect.implicit_target_b]

  def validate(%Spell{} = spell, targets) do
    case {required?(spell), targets} do
      {false, _} -> :ok
      {true, %__MODULE__{error: nil}} -> :ok
      {true, %__MODULE__{error: reason}} -> {:error, reason}
      {true, _missing} -> {:error, :bad_targets}
    end
  end

  def apply(%Target{} = targets, %__MODULE__{by_effect: locations}) do
    case Enum.max_by(locations, &elem(&1, 0), fn -> nil end) do
      {_index, %Selection{position: position}} -> %{targets | destination_location: position}
      nil -> targets
    end
  end

  def apply(%Target{} = targets, _locations), do: targets

  def direct_guids(%__MODULE__{by_effect: locations}, %Effect{} = effect, kind) do
    case {effect.implicit_target_a, effect.type, Map.get(locations, effect.index)} do
      {:script_location_near_caster, type, %Selection{guid: guid, kind: ^kind}}
      when type != :persistent_area_aura ->
        [guid]

      _ ->
        []
    end
  end

  def direct_guids(_locations, _effect, _kind), do: []

  def put_objects(%ObjectTargets{} = objects, %Spell{effects: effects}, locations) do
    by_effect =
      Enum.reduce(effects, objects.by_effect, fn effect, targets ->
        case direct_guids(locations, effect, :game_object) do
          [] -> targets
          guids -> Map.update(targets, effect.index, guids, &Enum.uniq(&1 ++ guids))
        end
      end)

    %{objects | by_effect: by_effect}
  end
end
