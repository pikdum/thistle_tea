defmodule ThistleTea.Game.Battleground.Effects do
  @moduledoc false

  defmodule OperateGates do
    @moduledoc false
    @enforce_keys [:action]
    defstruct [:action]
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

  defmodule ExitPlayers do
    @moduledoc false
    @enforce_keys [:destinations]
    defstruct [:destinations]
  end
end
