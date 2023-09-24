defmodule TwitterWeb.RoomChannel do
  use TwitterWeb, :channel

  def join("room:" <> room_id, _params, socket) do
    send(self(), :after_join)
    {:ok, %{channel: room_id}, assign(socket, :room_id, room_id)}
  end


  def join(channel_name, _params, socket) do
      IO.puts("room_channel: Joined #{channel_name}")
      {:ok, %{channel: channel_name}, socket}
  end


  def handle_info(:after_join, socket) do
    {:noreply, socket}
  end

end
