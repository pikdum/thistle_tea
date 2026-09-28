defmodule ThistleTea.Game.Entity.Logic.AI.Script.PetCommand do
  @moduledoc "Admits scripted companion commands using the current owner and target observations."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Entity.Logic.Hostility

  @commands {:stay, :follow, :attack, :dismiss}
  @unit_flag_pacified 0x00020000

  def apply(
        %Mob{internal: %{pet: %Pet{owner_guid: owner}, world: world}} = state,
        command,
        target,
        %Context{} = context
      )
      when command in 0..3 do
    with metadata when is_map(metadata) <- Perception.metadata(context.perception, owner),
         {^world, _, _, _} <- Perception.position(context.perception, owner),
         true <- command != 2 or attack_allowed?(state, owner, target, context) do
      PetBT.command(state, elem(@commands, command), target, context.now)
    else
      _ -> state
    end
  end

  def apply(%Mob{} = state, _command, _target, %Context{}), do: state

  defp attack_allowed?(%Mob{internal: %{world: world}} = state, owner, target, %Context{perception: perception})
       when is_integer(target) and target > 0 do
    with {^world, _, _, _} <- Perception.position(perception, target),
         %{alive?: true} = target_metadata <- Perception.metadata(perception, target) do
      owner = Perception.actor(perception, owner)
      transport = state.movement_block.transport_guid || 0

      (Map.get(owner, :unit_flags, 0) &&& @unit_flag_pacified) == 0 and
        (Map.get(target_metadata, :transport_guid) || 0) == transport and
        Hostility.valid_attack_target?(owner, Perception.actor(perception, target))
    else
      _ -> false
    end
  end

  defp attack_allowed?(_state, _owner, _target, _context), do: false
end
