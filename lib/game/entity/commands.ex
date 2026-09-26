defmodule ThistleTea.Game.Entity.Commands.ChargePathResolved do
  @moduledoc false
  @enforce_keys [:path, :duration_ms, :started_at]
  defstruct [:path, :duration_ms, :started_at, :attack_target, swing_delay_ms: 0]
end

defmodule ThistleTea.Game.Entity.Commands.FarsightStarted do
  @moduledoc false
  @enforce_keys [:guid]
  defstruct [:guid]
end

defmodule ThistleTea.Game.Entity.Commands.ChannelGameObjectStarted do
  @moduledoc false
  @enforce_keys [:guid]
  defstruct [:guid]
end

defmodule ThistleTea.Game.Entity.Commands.TotemStarted do
  @moduledoc false
  @enforce_keys [:slot, :guid]
  defstruct [:slot, :guid]
end

defmodule ThistleTea.Game.Entity.Commands.TotemStopped do
  @moduledoc false
  @enforce_keys [:guid]
  defstruct [:guid]
end
