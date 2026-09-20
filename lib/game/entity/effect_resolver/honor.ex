defmodule ThistleTea.Game.Entity.EffectResolver.Honor do
  @moduledoc """
  Captures controlling players at damage receipt and resolves eligible honor
  participants from current group membership and world presence at death.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Honor.Damage
  alias ThistleTea.Game.Entity.Data.Honor.Participant
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Honor, as: HonorLogic
  alias ThistleTea.Game.Entity.Logic.Honor.Contribution
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party

  def resolve(%Effects.HonorDamage{} = effect, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:owner_guid]))

    [
      %Effects.HonorContribution{
        player_guid: controlling_player(effect.source_guid, metadata),
        damage: effect.damage,
        now: effect.now,
        lethal?: effect.lethal?,
        honorless?: effect.honorless?
      }
    ]
  end

  def shares(%Character{} = entity, %Damage{} = history, now, opts \\ []) do
    group_of = Keyword.get(opts, :group_of, &Party.group_of/1)
    metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:race, :alive?]))
    position = Keyword.get(opts, :position, &World.position/1)

    participants =
      history.by_player
      |> Map.keys()
      |> Enum.filter(&(&1 > 0))
      |> Enum.flat_map(&members(&1, group_of.(&1)))
      |> Map.new()
      |> Enum.map(fn {guid, group_id} ->
        row = metadata.(guid) || %{}

        %Participant{
          guid: guid,
          team: HonorLogic.team(Map.get(row, :race)),
          group_id: group_id,
          alive?: Map.get(row, :alive?) == true,
          in_range?: in_range?(entity, position.(guid))
        }
      end)

    Contribution.shares(history, participants, HonorLogic.team(entity.unit.race), now)
  end

  defp members(_guid, %Group{id: id, members: members}), do: Enum.map(members, &{&1.guid, id})
  defp members(guid, nil), do: [{guid, nil}]

  defp in_range?(%Character{internal: %{world: world}, movement_block: %{position: {x, y, z, _o}}}, {world, px, py, pz}) do
    Math.distance({x, y, z}, {px, py, pz}) <= Experience.group_reward_distance()
  end

  defp in_range?(_entity, _position), do: false

  defp controlling_player(guid, metadata) when is_integer(guid) and guid > 0 do
    if Guid.entity_type(guid) == :player do
      guid
    else
      player_owner(metadata.(guid))
    end
  end

  defp controlling_player(_guid, _metadata), do: nil

  defp player_owner(%{owner_guid: owner}) when is_integer(owner) and owner > 0 do
    if Guid.entity_type(owner) == :player, do: owner
  end

  defp player_owner(_metadata), do: nil
end
