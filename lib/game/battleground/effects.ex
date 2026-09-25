defmodule ThistleTea.Game.Battleground.Effects do
  @moduledoc false

  defmodule StartBuffs do
    @moduledoc false
    @enforce_keys [:positions]
    defstruct [:positions]
  end

  defmodule StopBuffs do
    @moduledoc false
    defstruct []
  end

  defmodule SetEvent do
    @moduledoc false
    @enforce_keys [:event, :state]
    defstruct [:event, :state]
  end

  defmodule StopEventRespawns do
    @moduledoc false
    @enforce_keys [:event]
    defstruct [:event]
  end

  defmodule ScheduleTimer do
    @moduledoc false
    @enforce_keys [:key, :delays]
    defstruct [:key, :delays]
  end

  defmodule ObjectiveAnnouncement do
    @moduledoc false
    @enforce_keys [:name, :kind, :team, :action]
    defstruct [:name, :kind, :team, :action]
  end

  defmodule NodeAnnouncement do
    @moduledoc false
    @enforce_keys [:node, :team, :action]
    defstruct [:node, :team, :action, :actor_guid]
  end

  defmodule QuestKillCredit do
    @moduledoc false
    @enforce_keys [:guid, :entry]
    defstruct [:guid, :entry]
  end

  defmodule TeamSpell do
    @moduledoc false
    @enforce_keys [:team, :spell_id]
    defstruct [:team, :spell_id]
  end

  defmodule ArmorUpgrade do
    @moduledoc false
    @enforce_keys [:team, :tier]
    defstruct [:team, :tier]
  end

  defmodule OperateGates do
    @moduledoc false
    @enforce_keys [:action]
    defstruct [:action]
  end

  defmodule DespawnGhostGates do
    @moduledoc false
    defstruct []
  end

  defmodule UpdateStatus do
    @moduledoc false
    defstruct []
  end

  defmodule HideGameObject do
    @moduledoc false
    @enforce_keys [:guid]
    defstruct [:guid]
  end

  defmodule ShowBaseFlag do
    @moduledoc false
    @enforce_keys [:team]
    defstruct [:team]
  end

  defmodule HideBaseFlags do
    @moduledoc false
    defstruct []
  end

  defmodule SpawnDroppedFlag do
    @moduledoc false
    @enforce_keys [:guid, :team, :position]
    defstruct [:guid, :team, :position]
  end

  defmodule DespawnGameObject do
    @moduledoc false
    @enforce_keys [:guid]
    defstruct [:guid]
  end

  defmodule ApplyFlagAura do
    @moduledoc false
    @enforce_keys [:guid, :team]
    defstruct [:guid, :team]
  end

  defmodule RemoveFlagAura do
    @moduledoc false
    @enforce_keys [:guid, :team]
    defstruct [:guid, :team]
  end

  defmodule UpdateWorldStates do
    @moduledoc false
    @enforce_keys [:states]
    defstruct [:states]
  end

  defmodule Announce do
    @moduledoc false
    @enforce_keys [:broadcast_text_id, :audience]
    defstruct [:broadcast_text_id, :audience, :actor_guid]
  end

  defmodule PlaySound do
    @moduledoc false
    @enforce_keys [:sound_id]
    defstruct [:sound_id]
  end

  defmodule PlayerJoined do
    @moduledoc false
    @enforce_keys [:guid]
    defstruct [:guid]
  end

  defmodule PlayerLeft do
    @moduledoc false
    @enforce_keys [:guid]
    defstruct [:guid]
  end

  defmodule ResurrectPlayers do
    @moduledoc false
    @enforce_keys [:guids]
    defstruct [:guids]
  end

  defmodule Scoreboard do
    @moduledoc false
    @enforce_keys [:ended?, :players]
    defstruct [:ended?, :winner, :players]
  end

  defmodule RewardPlayers do
    @moduledoc false
    @enforce_keys [:winner, :players]
    defstruct [:winner, :players]
  end

  defmodule RewardReputation do
    @moduledoc false
    @enforce_keys [:team, :faction_id, :amount]
    defstruct [:team, :faction_id, :amount]
  end

  defmodule RewardHonor do
    @moduledoc false
    @enforce_keys [:guids, :amount]
    defstruct [:guids, :amount]
  end

  defmodule ExitPlayers do
    @moduledoc false
    @enforce_keys [:destinations]
    defstruct [:destinations]
  end
end
