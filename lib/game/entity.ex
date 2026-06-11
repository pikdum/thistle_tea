defmodule ThistleTea.Game.Entity do
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry

  def register(guid), do: EntityRegistry.register(guid)
  def unregister(guid), do: EntityRegistry.unregister(guid)
  def online?(guid), do: EntityRegistry.registered?(guid)

  def pid(target) do
    case resolve_pid(target) do
      {:ok, pid} -> pid
      _ -> nil
    end
  end

  def request_update_from(entity, target \\ self()) do
    dispatch_cast(entity, {:send_update_to, target})
  end

  def move_to(entity, {x, y, z}) do
    dispatch_cast(entity, {:move_to, x, y, z})
  end

  def receive_spell(entity, caster, spell) do
    dispatch_cast(entity, {:receive_spell, caster, spell})
  end

  def receive_attack(entity, attack) do
    dispatch_cast(entity, {:receive_attack, attack})
  end

  def reward_kill(entity, victim) do
    dispatch_cast(entity, {:reward_kill, victim})
  end

  def destroy_object(entity, guid) do
    dispatch_cast(entity, {:destroy_object, guid})
  end

  def visibility_changed(entity, guid) do
    dispatch_cast(entity, {:visibility_changed, guid})
  end

  def set_speed(entity, rate) do
    dispatch_cast(entity, {:set_speed, rate})
  end

  def call(entity, message) do
    case resolve_pid(entity) do
      {:ok, pid} -> GenServer.call(pid, message)
      error -> error
    end
  catch
    :exit, _ -> {:error, :not_found}
  end

  defp dispatch_cast(target, message) do
    case resolve_pid(target) do
      {:ok, pid} -> GenServer.cast(pid, message)
      error -> error
    end
  end

  defp resolve_pid(pid) when is_pid(pid), do: {:ok, pid}

  defp resolve_pid(guid) when is_integer(guid) do
    case EntityRegistry.whereis(guid) do
      pid when is_pid(pid) -> {:ok, pid}
      _ -> {:error, :not_found}
    end
  end

  defp resolve_pid(_target), do: {:error, :invalid_target}
end
