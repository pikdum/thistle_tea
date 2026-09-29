defmodule ThistleTea.Game.World.Entity.Player.Honor do
  @moduledoc """
  Owner-side synchronization of the realm honor ledger into player fields.
  """

  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Honor, as: HonorCore
  alias ThistleTea.Game.Core.Honor.Award
  alias ThistleTea.Game.Core.Honor.Snapshot
  alias ThistleTea.Game.Network.Message.MsgInspectHonorStats
  alias ThistleTea.Game.Network.Message.SmsgPvpCredit
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player.Inspection
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.System.Honor, as: HonorSystem

  def sync(%Character{} = character, server \\ HonorSystem) do
    snapshot =
      HonorSystem.register(character.object.guid, HonorCore.team(character.unit.race), character.unit.level, server)

    apply_snapshot(character, snapshot)
  end

  def apply_snapshot(%Character{} = character, %Snapshot{} = snapshot) do
    player = HonorCore.project(snapshot.honor, character.player, snapshot.day, snapshot.week_start)

    %{character | player: player}
    |> Entity.mark_broadcast_update()
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
      %MsgInspectHonorStats{} = message -> Outbound.send_packet(message)
      nil -> :ok
    end

    state
  end

  def inspect_reply(%Character{} = character, guid, opts \\ []) do
    snapshot = Keyword.get(opts, :snapshot, &HonorSystem.snapshot/1)

    with true <- Inspection.available?(character, guid, opts),
         %Snapshot{} = snapshot <- snapshot.(guid) do
      player = HonorCore.project(snapshot.honor, %Player{}, snapshot.day, snapshot.week_start)
      %MsgInspectHonorStats{guid: guid, player: player}
    else
      _unavailable -> nil
    end
  end
end
