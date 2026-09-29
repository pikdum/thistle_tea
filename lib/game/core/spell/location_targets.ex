defmodule ThistleTea.Game.Core.Spell.LocationTargets do
  @moduledoc "Resolved spell destinations and any units or objects that supplied them."

  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CasterLocation
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.ObjectTargets
  alias ThistleTea.Game.Core.Spell.Target

  defstruct by_effect: %{}, error: nil

  defmodule Selection do
    @moduledoc false
    defstruct [:guid, :position, :kind]
  end

  def required?(%Spell{effects: effects}), do: Enum.any?(effects, &location?/1)

  def location?(%Effect{} = effect),
    do: scripted?(effect) or database?(effect) or selected_unit?(effect) or CasterLocation.required?(effect)

  def selected_unit?(%Effect{} = effect),
    do: Enum.any?([effect.implicit_target_a, effect.implicit_target_b], &(&1 in [:enemy_location, :unit_location]))

  def enemy?(%Effect{} = effect), do: :enemy_location in [effect.implicit_target_a, effect.implicit_target_b]

  def database?(%Effect{type: :teleport_units}), do: false

  def database?(%Effect{} = effect), do: :database_location in [effect.implicit_target_a, effect.implicit_target_b]

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

  def for_packet(18_392, %Target{} = targets), do: %{targets | destination_location: nil}
  def for_packet(_spell_id, %Target{} = targets), do: targets

  def direct_guids(%__MODULE__{by_effect: locations}, %Effect{} = effect, kind) do
    case Map.get(locations, effect.index) do
      %Selection{guid: guid, kind: ^kind} when is_integer(guid) ->
        if direct_recipient?(effect), do: [guid], else: []

      _ ->
        []
    end
  end

  def direct_guids(_locations, _effect, _kind), do: []

  defp direct_recipient?(%Effect{implicit_target_a: :script_location_near_caster, type: type}),
    do: type != :persistent_area_aura

  defp direct_recipient?(%Effect{implicit_target_a: :unit_location, implicit_target_b: target})
       when target in [nil, :caster_destination], do: true

  defp direct_recipient?(effect), do: enemy?(effect)

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
