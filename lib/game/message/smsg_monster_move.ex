defmodule ThistleTea.Game.Message.SmsgMonsterMove do
  alias ThistleTea.Game.FieldStruct
  alias ThistleTea.Util

  # @move_type_normal 0
  # @move_type_stop 1
  @move_type_facing_spot 2
  @move_type_facing_target 3
  @move_type_facing_angle 4

  defstruct [
    :guid,
    :spline_point,
    :spline_id,
    :move_type,
    :target,
    :angle,
    :position,
    :spline_flags,
    :duration,
    :splines
  ]

  def build(%{
        object: %FieldStruct.Object{guid: guid},
        movement_block: %FieldStruct.MovementBlock{
          position: {x0, y0, z0, _o},
          spline_nodes: spline_nodes,
          duration: duration,
          spline_flags: spline_flags
        },
        internal: %FieldStruct.Internal{spline_id: spline_id}
      }) do
    %__MODULE__{
      guid: guid,
      spline_point: {x0, y0, z0},
      spline_id: spline_id,
      move_type: 0,
      spline_flags: spline_flags,
      duration: duration,
      splines: spline_nodes
    }
  end

  def to_binary(%__MODULE__{
        guid: guid,
        spline_point: spline_point,
        spline_id: spline_id,
        move_type: move_type,
        target: target,
        angle: angle,
        position: position,
        spline_flags: spline_flags,
        duration: duration,
        splines: splines
      }) do
    {x0, y0, z0} = spline_point

    spline_count = Enum.count(splines)

    [{xd, yd, zd} = destination | rest] = Enum.reverse(splines)
    splines = Enum.reverse(rest)

    initial_acc =
      <<spline_count::little-size(32), xd::little-float-size(32), yd::little-float-size(32), zd::little-float-size(32)>>

    splines_binary =
      Enum.reduce(splines, initial_acc, fn vec, acc ->
        offset = offset(destination, vec) |> adjust_offset()
        packed = Util.pack_vector(offset)
        acc <> <<packed::little-size(32)>>
      end)

    Util.pack_guid(guid) <>
      <<
        # initial position
        x0::little-float-size(32),
        y0::little-float-size(32),
        z0::little-float-size(32),
        spline_id::little-size(32),
        move_type::little-size(8)
      >> <>
      case move_type do
        @move_type_facing_target ->
          <<target::little-size(64)>>

        @move_type_facing_angle ->
          <<angle::little-float-size(32)>>

        @move_type_facing_spot ->
          {x, y, z} = position
          <<x::little-float-size(32), y::little-float-size(32), z::little-float-size(32)>>

        _ ->
          <<>>
      end <>
      <<
        spline_flags::little-size(32),
        duration::little-size(32)
      >> <> splines_binary
  end

  defp offset({xd, yd, zd}, {xi, yi, zi}) do
    {xd - xi, yd - yi, zd - zi}
  end

  defp adjust_offset({x, y, z}) do
    if abs(x) < 0.25 and abs(y) < 0.25 and abs(z) < 0.25 do
      if z < 0 do
        {x, y, z + 0.51}
      else
        {x, y, z + 0.26}
      end
    else
      {x, y, z}
    end
  end
end
