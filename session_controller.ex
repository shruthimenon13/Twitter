defmodule TwitterWeb.SessionController do
  use TwitterWeb, :controller

  alias TwitterWeb.Router.Helpers, as: Routes

  alias TwitterWeb.Accounts

  def new(conn, _) do
    render(conn, "new.html")
  end

  def create(conn, %{"session" => %{"username" => username, "password" => password}}) do

    receive_task_pid = self()
    is_web_user = 1

    return = GenServer.call(:twitter_server, {:login, username, password,receive_task_pid, is_web_user},:infinity)

    case return do
      :ok ->  conn
                |> put_session(:username, username)
                |> put_session(:current_user_id, username)
                |> assign(:current_user, username)
                |> assign(:signed_in?, true)
                |> put_flash(:info, "Welcome #{username}! Signing you in")
                |> redirect(to: Routes.home_path(conn, :index))

      :incorrect_password ->
              conn
                |> put_flash(:error, "Incorrect password")
                |> render("new.html")


      :unknown_user ->
              conn
                |> put_flash(:error, "Unknown User. Please check username")
                |> render("new.html")

      _      ->
              conn
                |> put_flash(:error, "Received some unknown value #{return} from the server ")
                |> render("new.html")
    end
  end

end
