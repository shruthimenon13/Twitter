defmodule TwitterWeb.AdminHomeController do
  use TwitterWeb, :controller

  alias TwitterWeb.Router.Helpers, as: Routes

  def index(conn, _params) do

    username = get_session(conn, :username)
    IO.puts("AdminHomeController: username = #{username}")

    conn |> clear_flash()

    nav_options = [
                    %{display_name: "CREATE USERS", id: :start_simulation},
                    %{display_name: "TELL USERS TO LOGIN & START TWEETING", id: :start_tweeting},
                    %{display_name: "TELL USERS TO STOP TWEETING, CHECK TIMELINES & LOGOUT", id: :stop_tweeting},
                    %{display_name: "GET SERVER INFO", id: :get_server_info},
                  ]

    render(conn, "index.html", nav_options: nav_options)
  end



  def show(conn, %{"id" => id}) do

    IO.puts("home_controller: show :: Received id = #{id}")
    username = get_session(conn, :username)


    case id do
        "start_simulation" ->
                                render(conn, "simulation_info.html", changeset: conn)

        "start_tweeting" ->
                                reply = GenServer.call(:twitter_simulator, {:ask_users_to_tweet, 1000}, :infinity)
                                conn
                                    |> put_flash(:info, "Users started tweeting")
                                    |> redirect(to: Routes.admin_home_path(conn, :index))

        "stop_tweeting" ->
                                GenServer.call(:twitter_simulator, :ask_users_to_stop_tweeting, :infinity)
                                conn
                                   |> put_flash(:info, "Users stopped tweeting")
                                   |> redirect(to: Routes.admin_home_path(conn, :index))


        "get_server_info" ->
                                server_info = GenServer.call(:twitter_server,:print_perf_info)
                                render(conn, "server_info.html", changeset: conn, server_info: server_info)

        _                 ->    IO.puts("ERROR: Home Controller Received id = #{id}. Not sure what this is")
    end

  end


  def create(conn, %{"admin_home" => home_params}) do
      # This will come for creating new tweets (when post_tweet.html will call this)
      # A better place would be to add a new controller for this.
      # If you start, then change post_tweet to directly send to that controller and let the controller redirect back

      {num_clients, ""} = Integer.parse(home_params["num_clients"])
      {num_clients_to_follow, ""} = Integer.parse(home_params["num_clients_to_follow"])
      tweets_per_client = 1
      {percent_tweets_with_hash, ""} = Integer.parse(home_params["percent_tweets_with_hash"])
      {percent_tweets_with_other_user, ""} = Integer.parse(home_params["percent_tweets_with_other_user"])
      percent_retweet = 0
      {tweet_interval, ""} = Integer.parse(home_params["tweet_interval"])

      gen_logfile = if(home_params["gen_logfile"] == "YES") do
                        1
                    else
                        0
                    end


      user_inputs = %{
        :num_clients => num_clients,
        :num_clients_to_follow => num_clients_to_follow,
        :tweets_per_client => tweets_per_client,
        :percent_tweets_with_other_user => percent_tweets_with_other_user,
        :percent_tweets_with_hash => percent_tweets_with_hash,
        :percent_retweet => percent_retweet,
        :gen_logfile => gen_logfile,
        :use_zipf_distribution => 0,
        :tweet_interval => tweet_interval
      }

      IO.puts("home_controller: This tweet will be created with = #{inspect home_params}")
      IO.puts("home_controller: User inputs hash = #{inspect user_inputs}")

      GenServer.call(:twitter_simulator, {:create_clients, user_inputs},:infinity)


      #username = get_session(conn, :username)
      #tweet = home_params["tweet"]
      #GenServer.call(:twitter_server, {:send_tweet, username, tweet},:infinity)
      conn
        |> put_flash(:info, "Started #{num_clients} users with the inputs provided")
        |> redirect(to: Routes.admin_home_path(conn, :index))
  end


end
