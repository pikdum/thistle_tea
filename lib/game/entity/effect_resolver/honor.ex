defmodule ThistleTea.Game.Entity.EffectResolver.Honor do
  @moduledoc """
  Captures controlling players at damage receipt and resolves eligible honor
  participants from current group membership and world presence at death.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Honor.Damage
  alias ThistleTea.Game.Entity.Data.Honor.Participant
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.KillReward
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Honor, as: HonorLogic
  alias ThistleTea.Game.Entity.Logic.Honor.Contribution
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Battleground
  alias ThistleTea.Game.World.System.Party

  def resolve(%Effects.HonorDamage{} = effect, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:owner_guid]))

    [
      %Effects.HonorContribution{
        player_guid: KillReward.controlling_player(effect.source_guid, metadata),
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
    battleground = Keyword.get(opts, :participants, &Battleground.participants/1)
    players = battleground.(entity.internal.world)

    participants =
      history.by_player
      |> Map.keys()
      |> Enum.filter(&(&1 > 0))
      |> Enum.flat_map(&members(&1, players, group_of))
      |> Map.new()
      |> Enum.map(fn {guid, group_id} ->
        row = metadata.(guid) || %{}

        %Participant{
          guid: guid,
          team: HonorLogic.team(Map.get(row, :race)),
          group_id: group_id,
          alive?: Map.get(row, :alive?) == true,
          in_range?: KillReward.in_range?(entity, position.(guid))
        }
      end)

    Contribution.shares(history, participants, HonorLogic.team(entity.unit.race), now)
  end

  def creature_kill(%Mob{} = victim, %Effects.HonorCreatureKill{} = effect, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, &Metadata.query(&1, [:owner_guid, :level, :alive?]))

    recipients =
      case KillReward.selection(victim, effect.source_guid, opts) do
        {:group, group} -> KillReward.eligible_members(victim, group, opts)
        {:solo, guid} -> living_player(guid, metadata.(guid))
        nil -> []
      end

    Enum.flat_map(recipients, fn %{guid: guid, level: level} ->
      case HonorLogic.creature_award(victim, level) do
        nil -> []
        award -> [%Effects.HonorAward{target_guid: guid, award: award}]
      end
    end)
  end

  defp living_player(guid, %{level: level, alive?: true}), do: [%{guid: guid, level: level}]
  defp living_player(_guid, _metadata), do: []

  defp members(_guid, %Group{id: id, members: members}), do: Enum.map(members, &{&1.guid, id})
  defp members(guid, nil), do: [{guid, nil}]

  defp members(guid, players, group_of) do
    case Map.get(players, guid) do
      %{team: team} ->
        players
        |> Enum.filter(fn {_guid, player} -> player.team == team end)
        |> Enum.map(fn {guid, _player} -> {guid, {:battleground, team}} end)

      nil ->
        members(guid, group_of.(guid))
    end
  end
end
