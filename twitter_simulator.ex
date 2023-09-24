defmodule TwitterSimulator do
  use GenServer

  def start_link(simulator_input) do
    GenServer.start_link(__MODULE__,simulator_input)
  end

  def init(simulator_input)do
    IO.puts("TwitterSimulator: Init starting with inputs => #{inspect simulator_input}")

    # Register
    :global.register_name(:twitter_simulator,self())

    #do_all_tasks(simulator_input, client_pids)
    state = %{}

    try do
      System.cmd("/bin/sh", ["-c", "rm log_client_*"])
    rescue
      _error ->
          IO.puts("Not removing files because /bin/sh is not available in this system")
    end

    {:ok,state}
  end

  def handle_call({:create_clients,simulator_input}, _from, state) do

    {num_subscribers_list, clients_to_follow_map} = if(simulator_input[:use_zipf_distribution] == 1)do
                                                      get_clients_to_follow(simulator_input[:num_clients])
                                               else
                                                    dummy_list = Enum.to_list(1..simulator_input[:num_clients])
                                                    {dummy_list,nil}
                                               end

    #Instantiate clients
    #Clients will also register to server and add followers
    client_pids = Enum.map(1..simulator_input[:num_clients], fn x ->
                          clients_to_follow = clients_to_follow_map[x]
                          num_subscribers = Enum.at(num_subscribers_list, x - 1)
                          {:ok, pid} = TwitterClient.start_link(x,simulator_input,clients_to_follow, num_subscribers)
                          pid
                  end)

    state= %{client_pids: client_pids, num_clients: simulator_input[:num_clients]}
    {:reply, state, state}
  end


  def handle_call(:return_state, _from, state) do
      {:reply, state, state}
  end


  def handle_call({:ask_users_to_tweet,time_interval}, _from, state) do
    num_clients = state[:num_clients]
    client_pids = state[:client_pids]
    client_tweet_pids = Enum.map(1..num_clients, fn x ->
                                client_pid = Enum.at(client_pids, x - 1)
                                Task.async(fn ->
                                    GenServer.call(client_pid, :login, :infinity)
                                    GenServer.call(client_pid, {:tweet_at_intervals, time_interval}, :infinity)
                                end)
                        end)
    Enum.each(client_tweet_pids, fn x -> Task.await(x, :infinity) end)
    {:reply, state, state}
  end

  def handle_call(:ask_users_to_stop_tweeting, _from, state) do
    num_clients = state[:num_clients]
    client_pids = state[:client_pids]
    client_tweet_pids = Enum.map(1..num_clients, fn x ->
                                  client_pid = Enum.at(client_pids, x - 1)
                                  Task.async(fn ->
                                      GenServer.call(client_pid, :logout, :infinity)
                                    end)
                          end)
      Enum.each(client_tweet_pids, fn x -> Task.await(x, :infinity) end)
      {:reply, state, state}
  end





  def do_all_tasks(simulator_input, client_pids) do
    # ===============================================================
    #Ask client to login, send out tweets, read all messages and logout
    # ===============================================================
    start_time = System.system_time(:millisecond)
    client_tweet_pids = Enum.map(1..simulator_input[:num_clients], fn x ->
                                client_pid = Enum.at(client_pids, x - 1)
                                Task.async(fn -> GenServer.call(client_pid, :start_tweeting, :infinity) end)
                        end)
    Enum.each(client_tweet_pids, fn x -> Task.await(x, :infinity) end)
    end_time = System.system_time(:millisecond)
    time_diff = end_time - start_time
    IO.puts "Time taken to complete: #{time_diff} milliseconds"
    # At this point all clients are logged out


    # If we are doing testing, also ask each client to make sure it received tweets from all followers
    # Also check that it can read all its tweets by accessing userTimeline
    if(simulator_input[:do_checks] == 1) do
      client_tweet_pids = Enum.map(1..simulator_input[:num_clients], fn x ->
                                  client_pid = Enum.at(client_pids, x - 1)
                                  Task.async(fn -> GenServer.call(client_pid, :do_timeline_checks, :infinity) end)
                          end)
            Enum.each(client_tweet_pids, fn x -> Task.await(x, :infinity) end)
    end



     #New stuff to test intervals
      client_tweet_pids = Enum.map(1..simulator_input[:num_clients], fn x ->
                                  client_pid = Enum.at(client_pids, x - 1)
                                  Task.async(fn ->
                                      time_interval = 2000
                                      GenServer.call(client_pid, :login, :infinity)
                                      GenServer.call(client_pid, {:tweet_at_intervals, time_interval}, :infinity)
                                  end)
                          end)
      Enum.each(client_tweet_pids, fn x -> Task.await(x, :infinity) end)

      Process.sleep(10000)

      #Ask everyone to logout
      client_tweet_pids = Enum.map(1..simulator_input[:num_clients], fn x ->
                                  client_pid = Enum.at(client_pids, x - 1)
                                  Task.async(fn ->
                                      GenServer.call(client_pid, :logout, :infinity)
                                  end)
                          end)
      Enum.each(client_tweet_pids, fn x -> Task.await(x, :infinity) end)








    # For bonus, we already did the zipf above
    # Here we are asking clients to run several rounds of login, logout, tweets
    # Also when we logic we sometimes use incorrect passwords to make sure login does not succeed
    if(simulator_input[:simulate_connection_disconnection] == 1) do
      client_tweet_pids = Enum.map(1..simulator_input[:num_clients], fn x ->
                                  client_pid = Enum.at(client_pids, x - 1)
                                  Task.async(fn -> GenServer.call(client_pid, {:run_multiple_connect_disconnect, 5}, :infinity) end)
                          end)
      Enum.each(client_tweet_pids, fn x -> Task.await(x, :infinity) end)
    end


    # =========================================
    # Now ask each client to delete the profile
    # =========================================
    if(simulator_input[:delete_accounts] == 1) do
      client_tweet_pids = Enum.map(1..simulator_input[:num_clients], fn x ->
                                    client_pid = Enum.at(client_pids, x - 1)
                                    Task.async(fn -> GenServer.call(client_pid, :delete_account, :infinity) end)
                                end)
                          Enum.each(client_tweet_pids, fn x -> Task.await(x, :infinity) end)
    end


    # =================================================
    # Tell all clients to close their logfiles if opened
    # ==================================================
    if(simulator_input[:gen_logfile] == 1) do
      client_tweet_pids = Enum.map(1..simulator_input[:num_clients], fn x ->
                                    client_pid = Enum.at(client_pids, x - 1)
                                    Task.async(fn -> GenServer.call(client_pid, :close_logfile, :infinity) end)
                                end)
                          Enum.each(client_tweet_pids, fn x -> Task.await(x, :infinity) end)
    end


    # ===============================================================
    # Print out the performance data
    # ===============================================================
    server_pid = :global.whereis_name(:twitter_server)
    GenServer.call(server_pid, :print_perf_info)



  end



  # ===============================================================
  # Tasks for the zipf distribution
  # ===============================================================


  def get_clients_to_follow(num_clients) do
      s = 1
      c = calculate_c(num_clients,s)
      {number_of_subscribers_list , clients_to_follow } = Enum.map_reduce(1..num_clients, %{}, fn x, acc ->
                                      {number_of_subscribers, subscribers} = generate_subscribers_for(x,c,s,num_clients)
                                      {_, acc} = Enum.map_reduce(subscribers, acc, fn y, updated_acc ->
                                                updated_acc = Map.update(updated_acc, y, [x], fn clients_to_follow -> clients_to_follow ++ [x] end)
                                                {0,updated_acc}
                                            end)
                                      {number_of_subscribers, acc}
                                 end)
    #  IO.inspect(clients_to_follow, charlists: :as_lists, limit: :infinity)
      {number_of_subscribers_list, clients_to_follow}
  end

  def calculate_c(num_clients_pending,s) do
      if(num_clients_pending == 1) do
          1
      else
          divider = :math.pow(num_clients_pending,s)
          c = (1 / divider) + calculate_c(num_clients_pending - 1, s)
      end
  end


  def generate_subscribers_for(client,c,s,num_clients) do
      probability_for_this_client = (c / :math.pow(client, s))
      number_of_subscribers = ceil(probability_for_this_client * num_clients / 100)

      subscriber_list = get_subscribers(client, number_of_subscribers, num_clients, [client])
      subscriber_list = subscriber_list -- [client]

      #IO.puts("Subscribers for #{client} => #{inspect subscriber_list, charlists: :as_lists}, Num_subscribers = #{number_of_subscribers}")
      {number_of_subscribers, subscriber_list}
  end

  def get_subscribers(client, number_of_subscribers, num_clients, subscriber_list) do
    if(number_of_subscribers == 0) do
        subscriber_list
    else
        new_subscriber_candidate = :rand.uniform(num_clients)
        if(Enum.member?(subscriber_list, new_subscriber_candidate)) do
            get_subscribers(client, number_of_subscribers, num_clients, subscriber_list)
        else
            subscriber_list = subscriber_list ++ [new_subscriber_candidate]
            get_subscribers(client, number_of_subscribers - 1, num_clients, subscriber_list)
        end
    end
  end
end
