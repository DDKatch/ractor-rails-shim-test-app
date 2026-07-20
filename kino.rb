# Mode is intentionally NOT pinned here. Select it at launch time via
#   `kino -m ractor -C kino.rb config_ractor.ru`   (Ractor workers)
#   `kino -m threaded -C kino.rb config.ru`        (threaded Puma/Falcon style)
# or via the `KINO_MODE` env var that config_ractor.ru / config.ru read.
# Hardcoding `mode :ractor` here would let `-C kino.rb` silently override a
# conflicting `-m threaded` flag on the command line.
workers 1
threads 1
port 9293
bind "127.0.0.1"
log_requests true
