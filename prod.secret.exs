use Mix.Config

# In this file, we keep production configuration that
# you'll likely want to automate and keep away from
# your version control system.
#
# You should document the content of this
# file or create a script for recreating it, since it's
# kept out of version control and might be hard to recover
# or recreate for your teammates (or yourself later on).
config :twitter, TwitterWeb.Endpoint,
  secret_key_base: "v/2nMn83SOgr/dqBw+etB+PzbTj9CqfsvqI6O+MFJjxjHwwPbOseJ5GF0uHuRj6q"

# Configure your database
config :twitter, Twitter.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "twitter_prod",
  pool_size: 15
