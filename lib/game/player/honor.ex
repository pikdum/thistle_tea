defmodule ThistleTea.Game.Player.Honor do
  @moduledoc """
  Owner-side synchronization of the realm honor ledger into player fields.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Honor.Award
  alias ThistleTea.Game.Entity.Data.Honor.Snapshot
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Honor, as: HonorLogic
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message.MsgInspectHonorStats
  alias ThistleTea.Game.Network.Message.SmsgPvpCredit
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.System.Honor, as: HonorSystem

  def sync(%Character{} = character, server \\ HonorSystem) do
    snapshot =
      HonorSystem.register(character.object.guid, HonorLogic.team(character.unit.race), character.unit.level, server)

    apply_snapshot(character, snapshot)
  end

  def apply_snapshot(%Character{} = character, %Snapshot{} = snapshot) do
    player = HonorLogic.project(snapshot.honor, character.player, snapshot.day, snapshot.week_start)

    %{character | player: player}
    |> Core.mark_broadcast_update()
    |> CharacterStore.put()
  end

  def apply_snapshot(%Character{} = character, nil), do: character

  def credit(%Award{} = award) do
    %SmsgPvpCredit{
      honor: trunc(award.points) * if(award.type == :dishonorable, do: -1, else: 1),
      victim_guid: award.victim_guid,
      victim_rank: award.victim_rank
    }
  end

  def inspect(%{character: %Character{} = character} = state, guid) do
    case inspect_reply(character, guid) do
      %MsgInspectHonorStats{} = message -> Network.send_packet(message)
      nil -> :ok
    end

    state
  end

  def inspect_reply(%Character{} = character, guid, opts \\ []) do
    online? = Keyword.get(opts, :online?, &Entity.online?/1)
    position = Keyword.get(opts, :position, &World.position/1)
    attackable? = Keyword.get(opts, :attackable?, &Hostility.valid_attack_target?/2)
    snapshot = Keyword.get(opts, :snapshot, &HonorSystem.snapshot/1)

    with true <- online?.(guid),
         true <- inspect_range?(character, position.(guid)),
         false <- attackable?.(character, guid),
         %Snapshot{} = snapshot <- snapshot.(guid) do
      player = HonorLogic.project(snapshot.honor, %Player{}, snapshot.day, snapshot.week_start)
      %MsgInspectHonorStats{guid: guid, player: player}
    else
      _unavailable -> nil
    end
  end

  defp inspect_range?(
         %Character{internal: %{world: world}, movement_block: %{position: {x, y, z, _o}}},
         {world, px, py, pz}
       ) do
    Math.distance({x, y, z}, {px, py, pz}) <= 10.0
  end

  defp inspect_range?(_character, _position), do: false
end
