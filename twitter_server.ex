defmodule TwitterServer do
  use GenServer

  def start_link(simulator_input) do
    GenServer.start_link(__MODULE__,simulator_input, name: TwitterServer)
  end

  def init(simulator_input) do
    IO.puts("TwitterServer: Started")
    :global.register_name(:twitter_server,self())
    create_tables();
    state= %{num_accounts_registered: 0,
             num_accounts_deleted: 0,
             login_time: {0, 0},
             tweets_with_hash: 0,
             tweets_with_other_user: 0,
             hometimeline_access_time: {0, 0},
             usertimeline_access_time: {0, 0},
             mentioned_tweets_access_time: {0, 0},
             hashtag_search_time: {0, 0},
             tweet_time: {0, 0},
             retweet_time: {0, 0},
             num_tweets_from_client: %{}
           }
    {:ok,state}
  end

  def create_tables do

      # Specific to user
      :ets.new(:client_info, [:set, :named_table])          # Client info will have password & if he is currently online. If yes, then pid
      :ets.new(:client_userTimeline, [:duplicate_bag, :named_table])  # This will be client's user Timeline
      :ets.new(:client_homeTimeline, [:duplicate_bag, :named_table])  # This will be client's home Timeline
      :ets.new(:client_subscribers, [:bag, :named_table])               # This will have list of followers following this client
      :ets.new(:client_mentions, [:duplicate_bag, :named_table])      # This will have the tweets in which this client is mentioned
      :ets.new(:client_direct_message, [:duplicate_bag, :named_table])      # This will have the tweets in which this client is mentioned

      #Specific to tweets
      :ets.new(:hashtag_table, [:duplicate_bag, :named_table])       # This will have for each hash, which tweets have this hash

  end

  # =========================================================================
  # ================== REGISTER, LOGIN, LOGOUT, DELETE related =====================
  # =========================================================================

  def handle_call({:register, username, password}, _from, state) do
      IO.puts("Registering user #{username} with password = #{password}")

      if(:ets.lookup(:client_info, username) == [])do
          client_info = %{password: password, online: 0, pid: 0, is_web_user: 0}
          :ets.insert(:client_info, {username, client_info})
          state = Map.update!(state, :num_accounts_registered, fn x -> x + 1 end)
          {:reply, :ok, state}
      else
          {:reply, :username_exists, state}
      end
  end

  def handle_call({:login, username, password,pid,is_web_user}, _from, state) do
    ets_lookup_response = :ets.lookup(:client_info, username)

    if(ets_lookup_response == []) do
          {:reply, :unknown_user, state}
    else
          [{_username, client_info}] = ets_lookup_response
          if(client_info[:password] == password) do
              client_info = Map.update!(client_info, :online, fn _ -> 1 end)
              client_info = Map.update!(client_info, :pid, fn _ -> pid end)
              client_info = Map.update!(client_info, :is_web_user, fn _ -> is_web_user end)
              :ets.insert(:client_info, {username, client_info})
              {:reply, :ok, state}
          else
              {:reply, :incorrect_password, state}

          end
    end
  end

  def handle_call({:logout, username}, _from, state) do
    [{_usename, client_info}] = :ets.lookup(:client_info, username)
    client_info = Map.update!(client_info, :online, fn _ -> 0 end)
    :ets.insert(:client_info, {username, client_info})
    {:reply, :ok, state}
  end

  def handle_call({:delete_account, username, password}, _from, state) do
    [{_username, client_info}] = :ets.lookup(:client_info, username)
      :ets.delete(:client_info, username)
      state = Map.update!(state, :num_accounts_deleted, fn x -> x + 1 end)
      {:reply, :ok, state}
  end

  # =========================================================================
  # ====================== FOLLOWERS related ================================
  # =========================================================================
  def handle_call({:follow, username, clients_to_follow},_from, state) do
      IO.puts("twitter_server: #{username} will be following #{clients_to_follow}")
      Enum.each(clients_to_follow, fn x -> :ets.insert(:client_subscribers,{x,username}) end)
      {:reply, :ok, state}
  end


  # =========================================================================
  # ====================  TIMELINE, HASHTAG Queries ==================================
  #==========================================================================
  def handle_call({:get_hometimeline, client}, _from, state) do
    start_time = get_current_time()
    home_timeline = :ets.lookup(:client_homeTimeline, client)
    home_timeline_array = Enum.map(home_timeline, fn {_key, value} -> value end)
    end_time = get_current_time()
    state = Map.update!(state, :hometimeline_access_time, fn {time, requests} -> {time + end_time - start_time, requests + 1} end)
    home_timeline_array = Enum.reverse(home_timeline_array) #Reverse so that the latest comes first
    {:reply, home_timeline_array, state}
  end

  def handle_call({:get_usertimeline, client}, _from, state) do
    start_time = get_current_time()
    timeline = :ets.lookup(:client_userTimeline, client)
    timeline_array = Enum.map(timeline, fn {_key, value} -> value end)
    end_time = get_current_time()
    state = Map.update!(state, :usertimeline_access_time, fn {time, requests} -> {time + end_time - start_time, requests + 1} end)
    timeline_array = Enum.reverse(timeline_array)  #Reverse so that the latest comes first
    {:reply, timeline_array, state}
  end

  def handle_call({:get_mentioned_tweets, client}, _from, state) do
    start_time = get_current_time()
    timeline = :ets.lookup(:client_mentions, client)
    timeline_array = Enum.map(timeline, fn {_key, value} -> value end)
    end_time = get_current_time()
    state = Map.update!(state, :mentioned_tweets_access_time, fn {time, requests} -> {time + end_time - start_time, requests + 1} end)
    timeline_array = Enum.reverse(timeline_array)  #Reverse so that the latest comes first
    {:reply, timeline_array, state}
  end

  def handle_call({:search, hashtag}, _from, state) do
    start_time = get_current_time()
    tweets = :ets.lookup(:hashtag_table, hashtag)
    tweets_array = Enum.map(tweets, fn {_key, value} -> value end)
    end_time = get_current_time()
    state = Map.update!(state, :hashtag_search_time, fn {time, requests} -> {time + end_time - start_time, requests + 1} end)
    tweets_array = Enum.reverse(tweets_array)  #Reverse so that the latest comes first
    {:reply, tweets_array, state}
  end


  def handle_call({:get_direct_message, client},_from, state) do
    timeline = :ets.lookup(:client_direct_message, client)
    timeline_array = Enum.map(timeline, fn {_key, value} -> value end)
    {:reply, timeline_array, state}
  end

  # =========================================================================
  # ========================= TWEET related =================================
  # =========================================================================
  def handle_call({:send_tweet, source, tweet},_from, state) do
      start_time = get_current_time()

      IO.puts("TwitterServer: Received tweet from #{source}. Tweet => #{tweet}")
      time_string = get_time_string()

      #Add this to source's own timeline
      :ets.insert(:client_userTimeline,{source, "#{time_string} You tweeted => #{tweet}"})

      #Send this to all followers
      send_tweet_to_followers(source, tweet, "#{time_string} #{source} tweeted => ")

      #Send this to whomever is mentioned
      user_mentioned = send_tweet_to_people_mentioned(source, tweet)

      #Add this to hashtag (for search)
      hash_tag_present = add_tweet_to_hashtag(source, tweet)

      end_time = get_current_time()

      state = Map.update!(state, :tweet_time, fn {time, requests} -> {time + end_time - start_time, requests + 1} end)
      state = Map.update!(state, :tweets_with_other_user, fn x -> x + Kernel.length(user_mentioned) end)
      state = Map.update!(state, :tweets_with_hash, fn x -> x + Kernel.length(hash_tag_present) end)

      num_tweet_hash = state[:num_tweets_from_client]
      num_tweet_hash_updated = if(num_tweet_hash[source] == nil)do
                                  Map.put(num_tweet_hash,source,1)
                               else
                                  Map.update!(num_tweet_hash,source, fn x -> x + 1 end)
                               end
      state = Map.update!(state, :num_tweets_from_client, fn _ -> num_tweet_hash_updated end)
      {:reply, :ok, state}
  end

  def handle_call({:send_retweet, source, tweet},_from,state) do
    start_time = get_current_time()
    time_string = get_time_string()

    #Add this to source's own timeline to specify he/she retweeted
    :ets.insert(:client_userTimeline,{source, "#{time_string} You retweeted => #{tweet}"})

    #Send this to all followers
    send_tweet_to_followers(source, tweet, "#{time_string} #{source} retweeted => ")

    end_time = get_current_time()
    state = Map.update!(state, :retweet_time, fn {time, requests} -> {time + end_time - start_time, requests + 1} end)
    {:reply, :ok, state}
  end


  def handle_call({:send_direct_message, source, dest, message},_from, state) do
      start_time = get_current_time()
      :ets.insert(:client_direct_message,{dest, "#{source} sent you this message => #{message}"})
      {:reply, :ok, state}
  end


  def send_tweet_to_followers(source, tweet, message_prefix) do
      #Add to the user timelines of followers
      full_tweet = message_prefix <> tweet

      followers_list = :ets.lookup(:client_subscribers,source)
      Enum.each(followers_list,
        fn x ->
          {_source, follower} = x
          :ets.insert(:client_homeTimeline,{follower, full_tweet})
          #If this follower is online, send him a live notification
          send_message_to_client_if_live(follower, :tweet_from_subscription, full_tweet)
        end)
  end




  def send_tweet_to_people_mentioned(source, tweet) do
      full_tweet = "You were mentioned in a tweet by #{source} => #{tweet}"
      users_list = Regex.scan(~r/\B@[a-zA-Z0-9_]+/, tweet)
      users_list = Enum.concat(users_list)

      IO.puts("TwitterServer: users_list  = #{inspect users_list}. Tweet = #{tweet}")

      Enum.each(users_list,
        fn x ->
            user_id = String.slice(x,1, String.length(x)-1)
            #{user_id, ""} = Integer.parse(user_id)
            IO.puts("TwitterServer: Got a tweet mentioning #{user_id}. So adding #{tweet} to his mentions timeline")

            :ets.insert(:client_mentions,{user_id, full_tweet})
            send_message_to_client_if_live(user_id, :tweet_mentioning_you, full_tweet)
        end
      )
      users_list
  end


  def add_tweet_to_hashtag(source, tweet) do

    full_tweet = "#{source} tweeted: #{tweet}"
    hash_tags_in_string = Regex.scan(~r/\B#[a-zA-Z0-9_]+/, tweet)
    #hash_tags_in_string = Regex.scan(~r{#[^\s]+}, tweet)
    hash_tags_in_string = Enum.concat(hash_tags_in_string)

    Enum.each(hash_tags_in_string,
      fn x ->
          :ets.insert(:hashtag_table,{x,full_tweet})
      end
    )

    hash_tags_in_string
  end

  def send_message_to_client_if_live(client, message_type, message) do
    [{username, client_info}] = :ets.lookup(:client_info, client)
    if(client_info[:online] == 1) do
      if(client_info[:is_web_user] != 1)do
          send(client_info[:pid],{:live_notification,message_type, message})
      else
          #FIXME
          IO.puts("Server: Not sending #{message} to #{username} because it is not ready yet")
      end
    end
  end


  # ===========================================================================
  # ======================= TIME RELATED  ======================================
  #============================================================================

  def get_current_time do
    System.system_time(:millisecond)
  end

  def get_time_string() do
    {{year, month, date}, {hour, min, sec}} = :calendar.local_time()
    "#{month}/#{date} @ #{hour}:#{min} ::"
  end



  # =========================================================================
  # ====================== RETURN STATE (for checking)=======================
  # =========================================================================
  def handle_call(:return_state, _from, state) do
      {:reply, state, state}
  end

  # ===========================================================================
  # ======================= PRINT TABLES ======================================
  #============================================================================

  def handle_call(:print_perf_info,_from,state) do
      { _ , total_tweets} = state[:tweet_time]
      { _ , total_retweets} = state[:retweet_time]

      #IO.puts("SERVER_STATE => #{inspect state}")
      IO.puts("========== SERVER PERFORMANCE DATA =============================")
      IO.puts("Total number of accounts registered = #{state[:num_accounts_registered]} ")
      IO.puts("Total number of tweets = #{ total_tweets } ")
      IO.puts("Total number of retweets = #{ total_retweets } ")
      avg_tweet_time = print_average(state[:tweet_time], "Average time to publish tweets ")
      avg_hometimeline_access_time = print_average(state[:hometimeline_access_time], "Average time to access hometimeline (ie, tweets followed by client) ")
      avg_usertimeline_access_time = print_average(state[:usertimeline_access_time], "Average time to access usertimeline (ie, tweets sent, retweeted by client) ")
      avg_mentioned_tweets_access_time = print_average(state[:mentioned_tweets_access_time], "Average time to access mentioned tweets (ie, tweets in which client is mentioned) ")
      avg_hashtag_search_time = print_average(state[:hashtag_search_time], "Average time to respond with hashtag searches ")

      return= %{num_accounts_registered: state[:num_accounts_registered],
               total_tweets: total_tweets,
               total_retweets: total_retweets,
               avg_tweet_time: avg_tweet_time,
               avg_hometimeline_access_time: avg_hometimeline_access_time,
               avg_usertimeline_access_time: avg_usertimeline_access_time,
               avg_mentioned_tweets_access_time: avg_mentioned_tweets_access_time,
               avg_hashtag_search_time: avg_hashtag_search_time,
             }

      {:reply, return, state}
  end

  def print_average(input, message) do
    {total_time, number} = input;
    avg = if(number > 0) do
                total_time / number
          else
                0
          end
    IO.puts("#{message} = #{avg}")
    avg
  end


  def handle_call(:print_tables,_from,state) do
    Enum.each([:client_subscribers, :client_userTimeline, :client_homeTimeline, :client_mentions],
        fn x ->
          #table_array = :ets.match_object(x, {:'$0', :'$1'})
          table_array = :ets.match_object(x, {1, :'$1'})
          IO.puts("=========== #{x} of USER1 ======================")
          Enum.each(table_array,
              fn y ->
                  {_ , value} = y
                  IO.puts(value)
          end)

          #IO.inspect("TwitterServer: print_tables => #{x} => #{inspect table_array}")
    end)


    table_array = :ets.match_object(:hashtag_table, {"#new", :'$1'})
    IO.puts("=========== Hash tag entries for new ======================")
    Enum.each(table_array,
        fn y ->
            {_ , value} = y
            IO.puts(value)
    end)


    {:reply, :ok, state}
  end






end
