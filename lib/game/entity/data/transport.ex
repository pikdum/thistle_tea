defmodule ThistleTea.Game.Entity.Data.Transport do
  @moduledoc """
  Immutable route data for a moving game object.

  Ship routes contain timed spline keyframes derived from taxi-path data.
  Animation routes contain local offsets driven by a stationary spawn.
  """

  defmodule Keyframe do
    @moduledoc false

    defstruct [
      :node_index,
      :map_id,
      :position,
      :delay_seconds,
      :initial_orientation,
      :distance_from_previous,
      :distance_since_stop,
      :distance_until_stop,
      :time_from,
      :time_to,
      :arrive_at_ms,
      :depart_at_ms,
      :next_distance_from_previous,
      :next_arrive_at_ms,
      :teleport?,
      :refresh?,
      :spline,
      :spline_index,
      stop?: false
    ]
  end

  defmodule AnimationFrame do
    @moduledoc false

    defstruct [:time_ms, :position, :sequence]
  end

  defmodule Spline do
    @moduledoc false

    defstruct [:points, :lengths, :first, :last]
  end

  defmodule Pose do
    @moduledoc false

    defstruct [:map_id, :position, :progress_ms, :frame_index, moving?: false, teleport?: false]
  end

  defstruct [
    :entry,
    :name,
    :kind,
    :period_ms,
    :move_speed,
    :accel_rate,
    :accel_time,
    :accel_distance,
    :path_id,
    keyframes: [],
    animation_frames: [],
    maps: MapSet.new()
  ]
end
