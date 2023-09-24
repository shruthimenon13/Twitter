defmodule TwitterWeb.RegistrationController do
  use TwitterWeb, :controller
  alias TwitterWeb.Router.Helpers, as: Routes

  alias Twitter.Accounts

  def new(conn, _) do
    render(conn, "new.html", changeset: conn)
  end

  def create(conn, %{"registration" => registration_params}) do
    IO.puts("You are registered. Params = #{inspect registration_params}")

    username = registration_params["username"]
    #{username, ""} = Integer.parse(registration_params["username"])

    if(registration_params["password"] != registration_params["password_confirmation"])do
        conn
            |> put_flash(:error, "Passwords do not match. Please reenter")
            |> render("new.html",changeset: conn)
    else

      GenServer.call(:twitter_server, {:register, username, registration_params["password"]},:infinity)
      conn
        |> put_flash(:info, "You've Signed up ! Please login to continue")
        |> redirect(to: Routes.page_path(conn, :index))
    end
  end


  def login(conn, _) do
    #render(conn, "login.html", changeset: conn)
    conn
  end


end
