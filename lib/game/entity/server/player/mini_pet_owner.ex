defmodule ThistleTea.Game.Entity.Server.Player.MiniPetOwner.Monitor do
  @moduledoc false
  @enforce_keys [:token, :guid]
  defstruct [:token, :guid]
end

defmodule ThistleTea.Game.Entity.Server.Player.MiniPetOwner do
  @moduledoc """
  Spawns and monitors a player's noncombat pet without changing combat-pet
  controls or restoring a critter after logout or world changes.
  """

  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.MiniPet
  alias ThistleTea.Game.Entity.Server.Player.MiniPetOwner.Monitor
  alias ThistleTea.Game.Entity.Server.Player.PacketSink
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Summon

  def summon(%State{} = state, %Effects.SummonMiniPet{entry: entry} = effect) do
    if Death.alive?(state.character) do
      case MiniPet.active_ref(state.character) do
        %EntityRef{entry: ^entry} -> dismiss(state)
        _ -> replace(state, effect)
      end
    else
      state
    end
  end

  def dismiss(%State{character: nil} = state), do: clear_monitor(state)

  def dismiss(%State{} = state) do
    state = clear_monitor(state)
    character = state.character |> MiniPet.dismiss() |> EventSink.emit_pending()
    %{state | character: character}
  end

  def process_down(%State{mini_pet_monitor: %Monitor{token: token, guid: guid}} = state, token) do
    %{state | character: MiniPet.removed(state.character, guid), mini_pet_monitor: nil}
  end

  def process_down(%State{} = state, _token), do: state

  defp replace(state, %Effects.SummonMiniPet{} = effect) do
    case Summon.build_mini_pet(effect.entry, state.character, effect.spell_id, effect.duration_ms) do
      %Mob{} = pet ->
        state = dismiss(state)

        case MobLoader.start_mob(pet) do
          {:ok, pid} ->
            ref = %EntityRef{guid: pet.object.guid, entry: effect.entry, spell_id: effect.spell_id}
            monitor = %Monitor{token: Process.monitor(pid), guid: pet.object.guid}
            character = MiniPet.activate(state.character, ref)
            state = %{state | character: character, mini_pet_monitor: monitor}
            PacketSink.ensure_created(state, Core.update_object(pet))

          _failed ->
            state
        end

      _missing ->
        state
    end
  end

  defp clear_monitor(%State{mini_pet_monitor: %Monitor{token: token}} = state) do
    Process.demonitor(token, [:flush])
    %{state | mini_pet_monitor: nil}
  end

  defp clear_monitor(%State{} = state), do: state
end
