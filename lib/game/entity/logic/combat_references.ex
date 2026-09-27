defmodule ThistleTea.Game.Entity.Logic.CombatReferences do
  @moduledoc """
  Incarnation-scoped hostile references validated against one world snapshot.
  """

  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception

  def prune(refs, world, %Perception{} = perception) do
    MapSet.filter(refs || MapSet.new(), &active?(&1, world, perception))
  end

  def targets(refs) do
    (refs || []) |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
  end

  def active?({guid, incarnation}, world, %Perception{} = perception) do
    case {Perception.position(perception, guid), Perception.metadata(perception, guid)} do
      {{^world, _, _, _}, %{alive?: true, incarnation_id: ^incarnation} = metadata} ->
        metadata[:in_combat] != false and metadata[:evading?] != true

      _ ->
        false
    end
  end
end
