defmodule TwitterWeb.AdminSessionController do
  use TwitterWeb, :controller
  alias TwitterWeb.Router.Helpers, as: Routes
  alias TwitterWeb.Accounts

  def new(conn, _) do
    render(conn, "new.html")
  end

  def create(conn, %{"admin" => %{"username" => username, "password" => password}}) do

    if(username != "admin" || password != "admin123")do
        conn
            |> put_flash(:error, "Addmin details not correct. Please reenter")
            |> render("new.html")
    else
        conn
          |> put_session(:username, username)
          |> put_flash(:info, "Welcome #{username}! Signing you in as Admin")
          |> redirect(to: Routes.admin_home_path(conn, :index))
    end
 end

end
