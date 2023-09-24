defmodule TwitterClient do
  use GenServer

  def start_link(client_no, simulator_input,clients_to_follow,num_subscribers) do
    GenServer.start_link(__MODULE__, {client_no, simulator_input,clients_to_follow,num_subscribers})
  end

  def init({client_no, simulator_input, clients_to_follow,num_subscribers}) do
    #IO.puts("Client: #{client_no}:: Started")

    server_pid = :global.whereis_name(:twitter_server)

    tweets_per_client = if(simulator_input[:use_zipf_distribution] == 1) do
                            num_subscribers * 10
                        else
                            simulator_input[:tweets_per_client]
                        end

    username = "USER#{client_no}"

    #Initialize state
    state= %{client_no: client_no,
             server_pid: server_pid,
             username: username,
             password: "asdf#{client_no}",
             num_clients: simulator_input[:num_clients],
             num_clients_to_follow: simulator_input[:num_clients_to_follow],
             percent_retweet: simulator_input[:percent_retweet],
             tweets_per_client: tweets_per_client,
             percent_tweets_with_other_user: simulator_input[:percent_tweets_with_other_user],
             percent_tweets_with_hash: simulator_input[:percent_tweets_with_hash],
             gen_logfile: simulator_input[:gen_logfile],
             use_zipf_distribution: simulator_input[:use_zipf_distribution],
             do_checks: simulator_input[:do_checks],
             clients_to_follow: clients_to_follow,
             num_subscribers: num_subscribers,
             num_tweets_retweets_sent: 0,
             timer_thread_is_on: 0,
             tweet_no: 1,
             tweet_interval: simulator_input[:tweet_interval],
             logfile: [],
             user_tweet_state: :idle
            }
   IO.puts("Client: #{client_no}:: State = #{inspect state}")

   #Register to server using user name and password
   #remove_logfile(state)
   state = open_logfile(state)
   register(state)
   state = follow_other_clients(state)
   close_logfile(state)
    {:ok,state}
  end


  def handle_call(:start_tweeting, _from, state) do

      #Login specific
      my_pid = self()
      receive_task = Task.async(fn -> receive_inputs(my_pid,[]) end)   #This to to receive all live messages when they happen
      receive_task_pid = receive_task.pid
      login(state,receive_task_pid,1)

      #Check our home timeline
      home_timeline = get_timeline(state, :get_hometimeline)
      print_info(state, "HOME_TIMELINE", home_timeline)

      #Check the user timeline
      user_timeline = get_timeline(state, :get_usertimeline)
      print_info(state, "USER_TIMELINE", user_timeline)

      #Get tweets where I am mentioned list
      mentioned_tweets = get_timeline(state, :get_mentioned_tweets)
      print_info(state, "TWEETS_MENTIONING_ME", mentioned_tweets)

      #Send tweets
      state = send_tweets(state)

      #Wait for sometime until everyone sends something
      Process.sleep(500)

      #Do some retweets from our hometimeline
      home_timeline = get_timeline(state, :get_hometimeline)
      state = send_retweet(state, home_timeline)

      #Check all messages we received while we were tweeting
      send(receive_task_pid, {:get_notifications})

      receive do
        {:messages, messages} -> print_info(state, "LIVE_NOTIFICATIONS_UNTIL_NOW", messages)
                                 if(state[:do_checks] == 1)do
                                    check_that_I_did_receive_live_notifications(messages,state)
                                 end
      end



      #Check our home timeline again in case someone retweeted and display everything
      home_timeline = get_timeline(state, :get_hometimeline)
      print_info(state, "HOME_TIMELINE", home_timeline)

      #Check the user timeline and display it
      user_timeline = get_timeline(state, :get_usertimeline)
      print_info(state, "USER_TIMELINE", user_timeline)

      #Get tweets where I am mentioned list
      mentioned_tweets = get_timeline(state, :get_mentioned_tweets)
      print_info(state, "TWEETS_MENTIONING_ME", mentioned_tweets)

      #Search for some hashtag and get all tweets corresponding the hashtag
      hash_tag_to_search = get_rand_hash_string()
      matching_tweets = GenServer.call(state[:server_pid],{:search,hash_tag_to_search},:infinity)
      print_info(state, "TWEETS_WITH_HASH=#{hash_tag_to_search}",matching_tweets)
      if(state[:do_checks] == 1) do
        check_hashtag_results_have_the_hashtag(hash_tag_to_search,matching_tweets,state)
      end

      #Logout
      logout(state)
      send(receive_task_pid,{:end_task})

      IO.puts("Client #{state[:client_no]}: Waiting for receive task")
      Task.await(receive_task)
      IO.puts("Client #{state[:client_no]}: Got receive task")

      {:reply, state, state}
  end


  def handle_call(:do_timeline_checks, _from, state) do
      home_timeline = get_timeline(state, :get_hometimeline)
      check_hometimeline_has_tweets_from_everyone_I_follow(home_timeline,state)

      user_timeline = get_timeline(state, :get_usertimeline)
      check_all_my_tweets_are_present_in_usertimeline(user_timeline,state)
      {:reply, state, state}
  end


  def handle_call({:run_multiple_connect_disconnect, num_times}, _from, state) do

    my_pid = self()
    receive_task = Task.async(fn -> receive_inputs(my_pid,[]) end)   #This to to receive all live messages when they happen
    receive_task_pid = receive_task.pid

    Enum.each(1..num_times, fn _x ->

      #50 percent of time try loging in with wrong password first to ensure login does not succeed
      use_correct_password = if (:rand.uniform(100) < 50), do: 1, else: 0
      login(state,receive_task_pid,use_correct_password)

      #Send tweets
      send_tweets(state)

      #Logout
      logout(state)

    end)

    send(receive_task_pid,{:end_task})
    Task.await(receive_task)

    {:reply, state, state}
  end


  def handle_call(:delete_account, _from, state) do
      GenServer.call(state[:server_pid], {:delete_account, state[:username], state[:password]},:infinity)
      {:reply, state, state}
  end

  def handle_call(:close_logfile, _from, state) do
      close_logfile(state)
      {:reply, state, state}
  end


  def timer_thread(time_delay, parent_pid, interrupt_number)do
    receive do
        {:end_task}         ->  1
    after
         time_delay          -> interrupt_number = interrupt_number + 1;
                                GenServer.call(parent_pid, {:timer_interrupt, interrupt_number})
                                timer_thread(time_delay, parent_pid, interrupt_number)
    end
  end

  #======================== For directed tests =====================================
  def handle_call(:login, _from, state) do
      state = open_logfile(state)
      my_pid = self()
      receive_task = Task.async(fn -> receive_inputs(my_pid,[]) end)   #This to to receive all live messages when they happen
      receive_task_pid = receive_task.pid
      login(state,receive_task_pid,1)
      state = Map.put(state,:receive_task,receive_task)
      state = Map.put(state,:receive_task_pid,receive_task_pid)
      {:reply, state, state}
  end

  def handle_call({:post_this_tweet, tweet}, _from, state) do
      GenServer.call(state[:server_pid], {:send_tweet, state[:username], tweet},:infinity)
      Process.sleep(200)
      {:reply, state, state}
  end

  def handle_call({:tweet_at_intervals, time_interval}, _from, state) do
     {state, reply } = if(state[:user_tweet_state] == :idle) do
                            my_pid = self()
                            timer_task = Task.async(fn -> timer_thread(state[:tweet_interval],my_pid, 0) end)
                            state = Map.put(state,:timer_thread_is_on,1)
                            state = Map.put(state,:timer_task,timer_task)
                            state = Map.put(state,:timer_task_pid,timer_task.pid)
                            state = Map.put(state, :user_tweet_state, :tweeting)
                            {state, :ok}
                       else
                            {state, :users_tweeting_already}
                       end
      {:reply, reply, state}
  end

  def handle_call({:timer_interrupt, timer_number}, _from, state) do
      current_time = get_current_time_string
      IO.puts("#{state[:client_no]}: Time = #{current_time}: Sending next tweet because timer fired ")
      send_tweets(state, state[:tweet_no])
      state = Map.update!(state, :tweet_no, &(&1 + 1))
      {:reply, state, state}
  end

  def handle_call(:retweet_first_tweet_in_hometimeline, _from, state) do
      home_timeline = get_timeline(state, :get_hometimeline)
      post = Enum.at(home_timeline,0)
      GenServer.call(state[:server_pid], {:send_retweet, state[:username], post},:infinity)
      Process.sleep(200)
      {:reply, post, state}
  end


  def handle_call(:logout, _from, state) do
      {state, reply } = if(state[:user_tweet_state] == :tweeting) do
                            state = open_logfile(state)
                            do_all_timeline_and_other_accesses(state)
                            logout(state)
                            send(state[:receive_task_pid],{:end_task})
                            Task.await(state[:receive_task])
                            if(state[:timer_thread_is_on] == 1)do
                                send(state[:timer_task_pid],{:end_task})
                                Task.await(state[:timer_task])
                            end
                            close_logfile(state)
                            state = Map.put(state, :user_tweet_state, :idle)

                            {state, :ok}
                          else
                            {state, :already_stopped_and_logged_out}
                          end
      {:reply, reply, state}
  end


  def do_all_timeline_and_other_accesses(state) do
    #Check all messages we received while we were tweeting
    IO.puts("Client #{state[:client_no]}: do_all_timeline_and_other_accesses 1")

    send(state[:receive_task_pid], {:get_notifications})
    IO.puts("Client #{state[:client_no]}: do_all_timeline_and_other_accesses 2")
    receive do
      {:messages, messages} -> print_info(state, "LIVE_NOTIFICATIONS_UNTIL_NOW", messages)
    end

    #Check our home timeline again in case someone retweeted and display everything
    IO.puts("Client #{state[:client_no]}: do_all_timeline_and_other_accesses 3")
    home_timeline = get_timeline(state, :get_hometimeline)
    print_info(state, "HOME_TIMELINE", home_timeline)

    #Check the user timeline and display it
    IO.puts("Client #{state[:client_no]}: do_all_timeline_and_other_accesses 4")
    user_timeline = get_timeline(state, :get_usertimeline)
    print_info(state, "USER_TIMELINE", user_timeline)

    #Get tweets where I am mentioned list
    IO.puts("Client #{state[:client_no]}: do_all_timeline_and_other_accesses 5")
    mentioned_tweets = get_timeline(state, :get_mentioned_tweets)
    print_info(state, "TWEETS_MENTIONING_ME", mentioned_tweets)
    IO.puts("Client #{state[:client_no]}: do_all_timeline_and_other_accesses 6")
  end



  def handle_call(:return_live_notifications, _from, state) do
    send(state[:receive_task_pid], {:get_notifications})
    live_messages = receive do
                    {:messages, messages}  -> messages
                   end
    {:reply, live_messages, state}
  end

  def handle_call(:print_all_timelines, _from, state) do

    state = open_logfile(state)

    home_timeline = get_timeline(state, :get_hometimeline)
    print_info(state, "HOME_TIMELINE", home_timeline)

    #Check the user timeline and display it
    user_timeline = get_timeline(state, :get_usertimeline)
    print_info(state, "USER_TIMELINE", user_timeline)

    #Get tweets where I am mentioned list
    mentioned_tweets = get_timeline(state, :get_mentioned_tweets)
    print_info(state, "TWEETS_MENTIONING_ME", mentioned_tweets)

    close_logfile(state)
    {:reply, :ok, state}
  end


  #=================================================================================





  def get_timeline(state, timeline) do
    GenServer.call(state[:server_pid],{timeline, state[:username]},:infinity)
  end


  def receive_inputs(owner_pid,messages) do
    receive do
        {:live_notification,:tweet_from_subscription,message} ->
                                                receive_inputs(owner_pid, messages ++ [message])

        {:live_notification,:tweet_mentioning_you, message} ->
                                                receive_inputs(owner_pid, messages ++ [message])


        {:get_notifications} ->
                              send(owner_pid, {:messages, messages})
                              receive_inputs(owner_pid, messages)

        {:end_task} -> 1
    end
  end






  def register(state) do
    GenServer.call(state[:server_pid], {:register, state[:username], state[:password]},:infinity)
  end


  def login(state,receive_task_pid,use_correct_password) do
    is_web_user = 0

    password = if (use_correct_password == 1), do: state[:password], else: "RAND_PASSWORD"
    return = GenServer.call(state[:server_pid], {:login, state[:username], password,receive_task_pid,is_web_user},:infinity)

    if(password != state[:password])do
        if(return != :incorrect_password)do
            exit("ERROR: I am expecting incorrect password error. But got #{return} even though password is #{password}")
        end
        #Now login properly

        GenServer.call(state[:server_pid], {:login, state[:username], password,receive_task_pid, is_web_user},:infinity)
    end
    print_info(state, "LOGGED IN", [])
  end


  def logout(state) do
    GenServer.call(state[:server_pid], {:logout, state[:username]},:infinity)
    print_info(state, "LOGGED OUT", [])
  end


  def follow_other_clients(state) do
    random_other_clients = if(state[:clients_to_follow] != nil) do
                                state[:clients_to_follow]
                           else
                              if(state[:use_zipf_distribution] == 0)do
                                other_clients = get_list_of_other_clients(state)
                                _random_other_clients = Enum.take_random(other_clients, state[:num_clients_to_follow])
                              else
                                []
                              end
                           end

    follow_usernames = Enum.map(random_other_clients, fn x ->
                          "USER#{x}"
                      end)

    GenServer.call(state[:server_pid], {:follow,state[:username],follow_usernames},:infinity)
    print_info(state, "Following", follow_usernames)
    Map.put(state,:clients_to_follow,follow_usernames)
  end


  def get_current_time_string() do
    {{year, month, date}, {hour, min, sec}} = :calendar.local_time()
    "#{hour}:#{min}:#{sec} :: "
  end


  def get_time_string() do
    #{{year, month, date}, {hour, min, sec}} = :calendar.local_time()
    #{}"#{hour}:#{min}:#{sec} :: "
    ""
  end

  def send_tweets(state) do
    send_tweets(state, -1)
  end

  def send_tweets(state, tweet_no) do
    tweets = Enum.map(1..state[:tweets_per_client],
      fn x ->
            tweet_other_user = if (:rand.uniform(100) <= state[:percent_tweets_with_other_user]), do: get_other_user_string(state), else: ""
            tweet_hashtag = if (:rand.uniform(100) <= state[:percent_tweets_with_hash]), do: get_rand_hash_string(), else: ""
            tweet_no = if (tweet_no == -1), do: x, else: tweet_no
            tweet = get_time_string() <> "Hi. This is my tweet no: #{tweet_no}. #{tweet_other_user} #{tweet_hashtag}"
            #IO.puts("Client #{state[:client_no]}: Sending tweet: #{tweet}")
            GenServer.call(state[:server_pid], {:send_tweet, state[:username], tweet},:infinity)
            tweet
    end)
    print_info(state, "TWEETS SENT", tweets)
    num_tweets_sent = Kernel.length(tweets)
    Map.update!(state, :num_tweets_retweets_sent, fn x -> x + num_tweets_sent end)
  end

  def send_retweet(state, home_timeline) do
    {_, num_retweets} = Enum.map_reduce(home_timeline, 0, fn x, acc ->
                                acc = if (:rand.uniform(100) < state[:percent_retweet]) do
                                            GenServer.call(state[:server_pid], {:send_retweet, state[:username], x},:infinity)
                                            acc + 1;
                                      else
                                            acc
                                      end
                            {0, acc}
                          end)
      Map.update!(state, :num_tweets_retweets_sent, fn x -> x + num_retweets end)
  end


  def get_list_of_other_clients(state) do
    other_clients = 1 .. state[:num_clients]
    other_clients_list = Enum.to_list(other_clients)
    List.delete(other_clients_list, state[:client_no])          #Remove myself
  end

  def get_other_user_string(state) do
    chosen_user = (:rand.uniform(state[:num_clients]))
    if(chosen_user == state[:client_no]) do
        get_other_user_string(state)
    else
        "Hello @USER#{chosen_user}. "
    end
  end

  def get_rand_hash_string() do
    hash_strings = ["win", "giveaway", "travel", "COP5615isgreat"]
    chosen_index = (:rand.uniform(Kernel.length(hash_strings))) - 1
    chosen_hashtag = Enum.at(hash_strings, chosen_index)
    "##{chosen_hashtag}"
  end

  #=============================================
  def remove_logfile(state) do
    File.rm("log_client_#{state[:client_no]}")
  end

  def open_logfile(state) do
    if(state[:gen_logfile] == 1) do
        #Open the logfile
        {:ok, logfile} = File.open("log_client_#{state[:client_no]}", [:append])
        Map.update!(state, :logfile, fn _ -> logfile end)
    else
      state
    end
  end

  def close_logfile(state) do
    if(state[:gen_logfile] == 1) do
        File.close(state[:logfile])
    end
  end

  def print_info(state, tag, message) do
    if(state[:gen_logfile] == 1) do
      IO.write(state[:logfile], "================== #{tag} ==================================== \n")
      Enum.each(message, fn x -> IO.write(state[:logfile],"#{x}\n") end)
    end
  end

  #======================================================================================
  # All checks
  # =====================================================================================
  def check_hometimeline_has_tweets_from_everyone_I_follow(home_timeline,state) do
    if(state[:use_zipf_distribution] == 0) do
      if(state[:use_zipf_distribution] == 0)do
        Enum.each(state[:clients_to_follow], fn x ->
            string_to_search = "Client #{x} tweeted"
            length_of_timeline = Kernel.length(home_timeline) - 1
            {found, tweet} = search_timeline(string_to_search,home_timeline,length_of_timeline)

            if(found == 0) do
                exit("ERROR: Client #{state[:client_no]}: I did not get any tweets from Client #{x} even though I am following him/her")
            end
        end)
      end
   end
  end

  def check_all_my_tweets_are_present_in_usertimeline(user_timeline, state)do
      num_tweets_in_usertimeline = Kernel.length(user_timeline)
      expected_num_tweets = state[:num_tweets_retweets_sent]
      if(num_tweets_in_usertimeline != expected_num_tweets)do
          exit("ERROR: Client #{state[:client_no]}: I am expecting #{expected_num_tweets} tweets in usertimeline. But I see #{num_tweets_in_usertimeline} instead")
      end
  end

  def check_hashtag_results_have_the_hashtag(search_string,matching_tweets,state)do
      Enum.each(matching_tweets, fn x->
          if(x =~ search_string)do
          else
            exit("ERROR: Client #{state[:client_no]}: Server returned #{x} when I searched #{search_string}")
          end
      end)
  end

 def check_that_I_did_receive_live_notifications(messages,state) do
   if(state[:use_zipf_distribution] == 0)do
      if(Kernel.length(messages) == 0) do
          #exit("ERROR: Client #{state[:client_no]}: I did not receive any live notifications!")
      end
   end
 end




  def search_timeline(search_string, array, index) do
    if(index == -1)do
      {0, ""};
    else
      current_tweet = Enum.at(array, index)
      if(current_tweet =~ search_string) do
         {1, current_tweet};
      else
         search_timeline(search_string, array, index - 1)
      end
    end
  end








end
