defmodule TwitterWeb.HomeController do
  use TwitterWeb, :controller

  alias TwitterWeb.Router.Helpers, as: Routes

  def index(conn, _params) do

    username = get_session(conn, :username)
    IO.puts("Homecontroller: username = #{username}")

    conn |> clear_flash()

    nav_options = [
                    %{display_name: "Home Timeline", id: :home_timeline},
                    %{display_name: "User Timeline", id: :user_timeline},
                    %{display_name: "Mentioned Tweets", id: :mentioned_tweets},
                    %{display_name: "Post Tweet", id: :post_tweet},
                    %{display_name: "Send Direct Message", id: :send_msg},
                    %{display_name: "Direct Messages Received", id: :direct_messages_received},
                    %{display_name: "Follow Users", id: :follow_users},
                    %{display_name: "Search", id: :search},
                    %{display_name: "Log Out", id: :log_out}
                  ]

    render(conn, "index.html", nav_options: nav_options)
  end


  def show(conn, %{"id" => id}) do

    IO.puts("home_controller: show :: Received id = #{id}")
    username = get_session(conn, :username)

    nav_options = [
                    %{display_name: "Home Timeline", id: :home_timeline},
                    %{display_name: "User Timeline", id: :user_timeline},
                    %{display_name: "Mentioned Tweets", id: :mentioned_tweets},
                    %{display_name: "Post Tweet", id: :post_tweet},
                    %{display_name: "Send Direct Message", id: :send_msg},
                    %{display_name: "Direct Messages Received", id: :direct_messages_received},
                    %{display_name: "Follow Users", id: :follow_users},
                    %{display_name: "Search", id: :search},
                    %{display_name: "Log Out", id: :log_out}
                  ]

    case id do
        "home_timeline"     ->
                              home_timeline = get_timeline(username,:get_hometimeline)
                              IO.puts("HomeController: hometimeline = #{inspect home_timeline}")
                              render(conn, "show.html", heading: "HOME TIMELINE", data: home_timeline, nav_options: nav_options)
        "user_timeline"     ->
                              user_timeline = get_timeline(username,:get_usertimeline)
                              render(conn, "show.html", heading: "USER TIMELINE", data: user_timeline, nav_options: nav_options)
        "mentioned_tweets" ->
                              mentioned_tweets = get_timeline(username, :get_mentioned_tweets)
                              render(conn, "show.html", heading: "MENTIONED TWEETS", data: mentioned_tweets, nav_options: nav_options)
        "post_tweet"       ->
                              render(conn, "post_tweet.html", changeset: conn, nav_options: :nav_options)


        "follow_users"     -> render(conn, "follow_users.html", changeset: conn, nav_options: :nav_options)

        "search"           -> render(conn, "search_hashtag.html", changeset: conn, data: [])

        "send_msg"         -> render(conn, "direct_message.html", changeset: conn, data: [])

        "direct_messages_received" -> direct_messags = get_timeline(username, :get_direct_message)
                                      render(conn, "show.html", heading: "DIRECT MESSAGES RECEIVED", data: direct_messags, nav_options: nav_options)

        "log_out"          ->  do_logout(conn)


          _                -> split_array = String.split(id, ["_____"])
                              IO.puts("split array = #{inspect split_array}")
                              if(length(split_array) >= 2  && List.first(split_array) == "RETWEET") do
                                  do_retweet(conn, Enum.at(split_array,1),nav_options)
                              else
                                  IO.puts("ERROR: Home Controller Received id = #{id}. Not sure what to do with this")
                              end
    end
  end

  def do_retweet(conn, tweet, nav_options) do
    username = get_session(conn, :username)
    GenServer.call(:twitter_server, {:send_retweet, username, tweet},:infinity)
    home_timeline = get_timeline(username,:get_hometimeline)
    conn
     |> put_flash(:info, "Retweet sent")
    render(conn, "show.html", heading: "HOME TIMELINE", data: home_timeline, nav_options: nav_options)
  end



  def do_logout(conn) do
    username = get_session(conn, :username)
    GenServer.call(:twitter_server, {:logout, username},:infinity)
    conn
     |> clear_session
     |> put_flash(:info, "Logged out")
     |> redirect(to: Routes.page_path(conn, :index))
  end

  def send_tweet(conn, home_params, tweet) do
    IO.puts("home_controller: This tweet will be created with = #{inspect home_params}")
    username = get_session(conn, :username)
    GenServer.call(:twitter_server, {:send_tweet, username, tweet},:infinity)
    conn
      |> put_flash(:info, "Tweet Sent")
      |> redirect(to: Routes.home_path(conn, :index))
  end

  def follow_users(conn, home_params, users_to_follow_input) do
    IO.puts("home_controller: I will be following = #{inspect home_params}")
    username = get_session(conn, :username)
    users_to_follow = String.split(users_to_follow_input)
    GenServer.call(:twitter_server, {:follow, username, users_to_follow},:infinity)
    conn
      |> put_flash(:info, "You will be following the users you selected")
      |> redirect(to: Routes.home_path(conn, :index))
  end

  def do_search_hashtag(conn, hashtag) do
    IO.puts("Going to search for Hashtag #{hashtag}")
    matching_tweets = GenServer.call(:twitter_server,{:search,hashtag},:infinity)
    IO.puts("Hashtag results returned: #{inspect matching_tweets}")
    render(conn, "search_hashtag.html", changeset: conn, data: matching_tweets)
  end


  def create(conn, %{"home" => home_params}) do
      IO.puts("HomeController: Create: Received #{inspect home_params}")

      case home_params do
          %{"tweet" => tweet} -> send_tweet(conn, home_params, tweet)
          %{"users_to_follow" => users_to_follow_input} -> follow_users(conn, home_params, users_to_follow_input)
          %{"search_hashtag" => search_hashtag} -> do_search_hashtag(conn, search_hashtag)
          %{"direct_message_body" => body, "direct_message_dest" => dest} -> send_direct_message(conn, dest, body)
      end

  end

  def send_direct_message(conn, dest, body) do
      username = get_session(conn, :username)
      GenServer.call(:twitter_server, {:send_direct_message, username, dest, body},:infinity)
      conn
      |> put_flash(:info, "Message Sent")
      |> redirect(to: Routes.home_path(conn, :index))
  end


  def delete(conn, %{"id" => id}) do
    IO.puts("Called delete")

    #First logout
    username = get_session(conn, :username)
    GenServer.call(:twitter_server, {:logout, username},:infinity)
    GenServer.call(:twitter_server, {:delete_account, username, "rand_password"},:infinity)

    conn
      |> clear_session
      |> put_flash(:info, "Your profile has been deleted")
      |> redirect(to: Routes.page_path(conn, :index))
  end


  def get_timeline(username, timeline) do
      GenServer.call(:twitter_server,{timeline, username},:infinity)
  end




end
