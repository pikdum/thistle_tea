defmodule ThistleTea.Game.InstanceScript.Effects do
  @moduledoc false

  defmodule OperateGameObject do
    @moduledoc false
    @enforce_keys [:entry, :action]
    defstruct [:entry, :action]
  end

  defmodule Schedule do
    @moduledoc false
    @enforce_keys [:key, :delay_ms]
    defstruct [:key, :delay_ms]
  end

  defmodule CancelSchedules do
    @moduledoc false
    @enforce_keys [:keys]
    defstruct [:keys]
  end

  defmodule SummonCreature do
    @moduledoc false
    @enforce_keys [:entry, :position, :despawn_delay_ms]
    defstruct [:entry, :position, :despawn_delay_ms]
  end

  defmodule MonsterTalk do
    @moduledoc false
    @enforce_keys [:creature_entry, :broadcast_text_id]
    defstruct [:creature_entry, :broadcast_text_id]
  end

  defmodule CastPlayerSpell do
    @moduledoc false
    @enforce_keys [:spell_id]
    defstruct [:spell_id]
  end

  defmodule RemovePlayerAuras do
    @moduledoc false
    @enforce_keys [:spell_ids]
    defstruct [:spell_ids]
  end

  defmodule QuestKillCredit do
    @moduledoc false
    @enforce_keys [:creature_entry]
    defstruct [:creature_entry]
  end

  defmodule ModifyCreatureNpcFlags do
    @moduledoc false
    @enforce_keys [:creature_entry, :flags, :mode]
    defstruct [:creature_entry, :flags, :mode]
  end

  defmodule MoveCreature do
    @moduledoc false
    @enforce_keys [:creature_entry, :position]
    defstruct [:creature_entry, :position]
  end

  defmodule TriggerCreatureSpell do
    @moduledoc false
    @enforce_keys [:creature_entry, :spell_id]
    defstruct [:creature_entry, :spell_id]
  end
end
